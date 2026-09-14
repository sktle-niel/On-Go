import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/backend/mobile_backend.dart';
import 'mechanic_contact_store.dart';
import 'mechanic_notification_store.dart';

enum MechanicAccountMode { none, demo, registered }

/// Tracks the mechanic's account this session — mirrors ClientAccountStore's
/// demo/registered pattern, plus password, photo, and address, so mechanic
/// Settings and Profile can offer the same flows the client side has.
///
/// Verification is the one thing it does not own. A mechanic's account is
/// approved or rejected by a moderator working in the admin console, a
/// separate application; this store files the request through
/// [MobileBackend.verification] and then watches it for a verdict. Everything
/// downstream — [canPerformJobActions], the status banner on Jobs, the
/// "Account approved" notification — reads [accountRequest], so none of it
/// cares whether the answer came from this device or over the network.
class MechanicAccountStore extends ChangeNotifier {
  MechanicAccountStore._internal();
  static final MechanicAccountStore instance = MechanicAccountStore._internal();

  /// The last verdict this store saw, so a decision registers as a
  /// *transition* rather than re-firing on every update of the same request.
  ApprovalStatus? _lastSeenStatus;

  /// The live subscription to this mechanic's own request, opened by
  /// [registerAccount] and closed whenever the account changes.
  StreamSubscription<AccountVerificationRequest?>? _requestWatch;

  /// The latest copy of this mechanic's request. Null when there is none —
  /// no account yet, or a demo session.
  AccountVerificationRequest? _request;

  /// Applies an update to this mechanic's verification request. Crossing into
  /// approved is what puts "Account approved" on their bell; every other
  /// change just repaints.
  void _onRequestChanged(AccountVerificationRequest? request) {
    _request = request;
    final current = request?.status;
    if (current != _lastSeenStatus) {
      if (current == ApprovalStatus.approved) {
        MechanicNotificationStore.instance.add(
          kind: MechanicNotificationKind.accountApproved,
          mechanicName: name,
          clientName: '',
          detail: request?.reviewerName == null
              ? 'Reviewed by a moderator'
              : 'Reviewed by ${request!.reviewerName}',
        );
      }
      _lastSeenStatus = current;
    }
    notifyListeners();
  }

  void _stopWatching() {
    _requestWatch?.cancel();
    _requestWatch = null;
    _request = null;
    _lastSeenStatus = null;
  }

  static const Duration photoChangeCooldown = Duration(days: 30);

  MechanicAccountMode mode = MechanicAccountMode.none;

  String firstName = '';
  String lastName = '';
  String email = '';
  String phone = '';
  String address = '';
  String _password = '';

  String? photoPath;
  bool photoIsNetwork = false;
  DateTime? photoLastChangedAt;

  String get name => '$firstName $lastName'.trim();

  bool get isDemo => mode == MechanicAccountMode.demo;
  bool get isRegistered => mode == MechanicAccountMode.registered;
  bool get hasAccount => isRegistered;

  /// This mechanic's verification request as of the last update from
  /// [MobileBackend.verification], or null when there is none.
  AccountVerificationRequest? get accountRequest => _request;

  /// Why this account's verification request could not be filed, when it
  /// could not. Null when it was filed, or when there was nothing to file.
  ApiException? get verificationError => _verificationError;
  ApiException? _verificationError;

  ApprovalStatus? get status => _request?.status;

  bool get canPerformJobActions {
    if (isDemo) return true;
    return status == ApprovalStatus.approved;
  }

  void enterDemoMode() {
    mode = MechanicAccountMode.demo;
    firstName = 'Demo';
    lastName = 'Mechanic';
    email = '';
    phone = '';
    address = '';
    _password = '';
    photoPath = null;
    photoIsNetwork = false;
    photoLastChangedAt = null;
    _stopWatching();
    notifyListeners();
  }

  /// Registers the account and files its verification request.
  ///
  /// Awaits the filing rather than firing it off, so the caller knows the
  /// request reached the queue before it navigates away — that matters more,
  /// not less, once this is a network call that can fail.
  Future<void> registerAccount({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    String address = '',
    String password = '',
    String? photoPath,
    bool photoIsNetwork = false,
    List<String> documents = const [],
  }) async {
    mode = MechanicAccountMode.registered;
    this.firstName = firstName;
    this.lastName = lastName;
    this.email = email;
    this.phone = phone;
    this.address = address;
    _password = password;
    this.photoPath = photoPath;
    this.photoIsNetwork = photoIsNetwork;
    photoLastChangedAt = photoPath != null ? DateTime.now() : null;

    // Published under this mechanic's name, so a client opening their profile
    // can reach them. Recorded here rather than in the registration screen:
    // an account cannot be created without going through this method, so it
    // cannot be created without its contact details being on file.
    MechanicContactStore.instance.record(
      mechanicName: name,
      phone: phone,
      email: email,
    );

    _stopWatching();
    _verificationError = null;
    notifyListeners();

    final AccountVerificationRequest filed;
    try {
      filed = await MobileBackend.instance.verification.submit(
        SubmitVerificationRequest(
          name: '$firstName $lastName'.trim(),
          email: email,
          role: AccountRole.mechanic,
          documentNames: documents,
        ),
      );
    } on ApiException catch (error) {
      // The account exists; its request could not be filed — the API does not
      // serve verification yet (501), or could not be reached. Recorded rather
      // than thrown, and never replaced by a made-up Pending request.
      _verificationError = error;
      notifyListeners();
      return;
    }

    // Start from this request's own status, so the moderator's eventual
    // decision reads as a transition rather than inheriting a previous
    // account's state.
    _request = filed;
    _lastSeenStatus = filed.status;
    _requestWatch = MobileBackend.instance.verification
        .watchRequest(filed.id)
        .listen(_onRequestChanged);
    notifyListeners();
  }

  /// Takes on an account the On Go API signed in.
  ///
  /// Details this device already holds for the same email — from registering
  /// here this session, verification request included — are kept. Otherwise
  /// the server's display name stands in for the profile, and there is no
  /// verification request to watch: filing and reading those is not served by
  /// the API yet, so [status] stays null rather than guessing.
  void adoptServerAccount({required String email, required String displayName}) {
    final sameAccount = isRegistered && this.email.trim().toLowerCase() == email.trim().toLowerCase();
    mode = MechanicAccountMode.registered;
    if (!sameAccount) {
      firstName = displayName;
      lastName = '';
      this.email = email;
      phone = '';
      address = '';
      photoPath = null;
      photoIsNetwork = false;
      photoLastChangedAt = null;
      _verificationError = null;
      _stopWatching();
    }
    _password = '';
    notifyListeners();
  }

  bool get canChangePhoto {
    if (photoLastChangedAt == null) return true;
    return DateTime.now().difference(photoLastChangedAt!) >= photoChangeCooldown;
  }

  DateTime? get nextPhotoChangeAt => photoLastChangedAt?.add(photoChangeCooldown);

  bool changePhoto(String newPath, {bool isNetwork = false}) {
    if (!canChangePhoto) return false;
    photoPath = newPath;
    photoIsNetwork = isNetwork;
    photoLastChangedAt = DateTime.now();
    notifyListeners();
    return true;
  }

  bool changePassword({required String currentPassword, required String newPassword}) {
    if (_password != currentPassword) return false;
    _password = newPassword;
    notifyListeners();
    return true;
  }

  /// Sets a new password without knowing the old one. Only for the Forgot
  /// Password flow, which proves ownership with a one-time code instead —
  /// [changePassword] stays the path for a signed-in user.
  void resetPassword(String newPassword) {
    _password = newPassword;
    notifyListeners();
  }

  bool verifyPassword(String password) => _password == password;

  void clear() {
    mode = MechanicAccountMode.none;
    firstName = '';
    lastName = '';
    email = '';
    phone = '';
    address = '';
    _password = '';
    photoPath = null;
    photoIsNetwork = false;
    photoLastChangedAt = null;
    _stopWatching();
    notifyListeners();
  }
}