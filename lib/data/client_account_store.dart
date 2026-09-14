import 'package:flutter/foundation.dart';

enum ClientAccountMode { none, demo, registered }

/// Tracks the client's account this session — profile info, photo, and
/// password. Mirrors MechanicAccountStore's demo/registered pattern: "client"
/// on Sign In drops straight into a throwaway Demo Client identity with no
/// friction, and registering later (Welcome → Register as Client) upgrades
/// that same session into a real account instead of requiring a fresh
/// sign-in. There's no backend yet, so this is intentionally simple and
/// in-memory, same pattern as every other store in this app.
class ClientAccountStore extends ChangeNotifier {
  ClientAccountStore._internal();
  static final ClientAccountStore instance = ClientAccountStore._internal();

  static const Duration photoChangeCooldown = Duration(days: 30);

  ClientAccountMode mode = ClientAccountMode.none;

  bool get isDemo => mode == ClientAccountMode.demo;
  bool get isRegistered => mode == ClientAccountMode.registered;

  /// True once a real client account has been registered this session —
  /// checked by SignInScreen the same way MechanicAccountStore.hasAccount
  /// is, so "client" only falls back to demo mode when nothing real exists
  /// yet, and re-signs into the real account otherwise.
  bool get hasAccount => isRegistered;

  String firstName = '';
  String lastName = '';
  String email = '';
  String address = '';
  String phone = '';
  String _password = '';

  /// Local file path, or a remote URL if the client signed up with Google.
  String? photoPath;
  bool photoIsNetwork = false;
  DateTime? photoLastChangedAt;

  String get name => '$firstName $lastName'.trim();

  void enterDemoMode() {
    mode = ClientAccountMode.demo;
    firstName = 'Demo';
    lastName = 'Client';
    email = '';
    address = '';
    phone = '';
    _password = '';
    photoPath = null;
    photoIsNetwork = false;
    photoLastChangedAt = null;
    notifyListeners();
  }

  void registerAccount({
    required String firstName,
    required String lastName,
    required String email,
    required String address,
    required String phone,
    required String password,
    String? photoPath,
    bool photoIsNetwork = false,
  }) {
    mode = ClientAccountMode.registered;
    this.firstName = firstName;
    this.lastName = lastName;
    this.email = email;
    this.address = address;
    this.phone = phone;
    _password = password;
    this.photoPath = photoPath;
    this.photoIsNetwork = photoIsNetwork;
    photoLastChangedAt = photoPath != null ? DateTime.now() : null;
    notifyListeners();
  }

  /// Takes on an account the On Go API signed in.
  ///
  /// Details this device already holds for the same email — from registering
  /// here this session — are kept. Otherwise the server's display name stands
  /// in for the profile: the API has no profile route yet, so there is no
  /// address, phone or photo to fill in. The password is the server's and is
  /// never kept here.
  void adoptServerAccount({required String email, required String displayName}) {
    final sameAccount = isRegistered && this.email.trim().toLowerCase() == email.trim().toLowerCase();
    mode = ClientAccountMode.registered;
    if (!sameAccount) {
      firstName = displayName;
      lastName = '';
      this.email = email;
      address = '';
      phone = '';
      photoPath = null;
      photoIsNetwork = false;
      photoLastChangedAt = null;
    }
    _password = '';
    notifyListeners();
  }

  bool get canChangePhoto {
    if (photoLastChangedAt == null) return true;
    return DateTime.now().difference(photoLastChangedAt!) >= photoChangeCooldown;
  }

  /// When the client will next be allowed to change their photo — only
  /// meaningful when [canChangePhoto] is false.
  DateTime? get nextPhotoChangeAt =>
      photoLastChangedAt?.add(photoChangeCooldown);

  /// Returns false (and leaves the photo untouched) if the monthly cooldown
  /// hasn't elapsed yet.
  bool changePhoto(String newPath, {bool isNetwork = false}) {
    if (!canChangePhoto) return false;
    photoPath = newPath;
    photoIsNetwork = isNetwork;
    photoLastChangedAt = DateTime.now();
    notifyListeners();
    return true;
  }

  /// Verifies [currentPassword] before setting [newPassword]. Returns false
  /// (and leaves the password untouched) if the current password is wrong.
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
    mode = ClientAccountMode.none;
    firstName = '';
    lastName = '';
    email = '';
    address = '';
    phone = '';
    _password = '';
    photoPath = null;
    photoIsNetwork = false;
    photoLastChangedAt = null;
    notifyListeners();
  }
}