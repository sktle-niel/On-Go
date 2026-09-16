import 'package:flutter/foundation.dart';

/// What a mechanic's bell can tell them about. Each value is raised from the
/// one method that performs it, so a notification can never be recorded for
/// something that didn't actually happen.
enum MechanicNotificationKind {
  /// A client accepted this mechanic's quote.
  quoteAccepted,

  /// A client turned this mechanic's quote down. Raised by
  /// `QuoteNotificationStore.clientRejectQuote` — a rejection is an answer,
  /// so the mechanic hears it rather than watching a quote go quiet.
  quoteRejected,

  /// A client left this mechanic a rating.
  rated,

  /// A client confirmed payment for a finished job.
  paymentReceived,

  /// A client posted an emergency job. Goes to every mechanic — nobody owns
  /// it until someone accepts it.
  emergencyPosted,

  /// A moderator approved this mechanic's account.
  accountApproved,
}

/// One entry in a mechanic's notification list — the mechanic-side twin of
/// `ClientNotification`.
class MechanicNotification {
  final String id;
  final MechanicNotificationKind kind;

  /// Who this is for. Null means every mechanic sees it — only
  /// [MechanicNotificationKind.emergencyPosted] is broadcast that way.
  final String? mechanicName;

  /// The job this is about, when there is one. Null for account approval and
  /// ratings, which are about the mechanic rather than a job.
  final String? requestId;

  /// The quote involved, for [MechanicNotificationKind.quoteAccepted] and
  /// [MechanicNotificationKind.quoteRejected]. Null otherwise.
  final String? quoteId;

  /// The other party's name, or an empty string when there isn't one.
  final String clientName;

  /// Short context line — the job's problem text, the rating given, the
  /// amount paid. Captured at the time so the entry still reads correctly if
  /// the job is later deleted.
  final String detail;
  final DateTime createdAt;

  /// Cleared by [MechanicNotificationStore.markSeenFor] — this is what the
  /// bell's badge counts.
  bool read;

  MechanicNotification({
    required this.id,
    required this.kind,
    required this.mechanicName,
    required this.clientName,
    required this.detail,
    required this.createdAt,
    this.requestId,
    this.quoteId,
    this.read = false,
  });

  String get title {
    switch (kind) {
      case MechanicNotificationKind.quoteAccepted:
        return 'Your quote was accepted';
      case MechanicNotificationKind.quoteRejected:
        return 'Your quote was rejected';
      case MechanicNotificationKind.rated:
        return 'You received a rating';
      case MechanicNotificationKind.paymentReceived:
        return 'Payment received';
      case MechanicNotificationKind.emergencyPosted:
        return 'New emergency job';
      case MechanicNotificationKind.accountApproved:
        return 'Account approved';
    }
  }

  String get message {
    switch (kind) {
      case MechanicNotificationKind.quoteAccepted:
        return '$clientName accepted your quote.';
      case MechanicNotificationKind.quoteRejected:
        return '$clientName turned down your quote. The job is still open to '
            'other mechanics, but you can no longer quote it.';
      case MechanicNotificationKind.rated:
        // A job evaluation is anonymous to the mechanic and carries no name;
        // a profile review is signed.
        return clientName.isEmpty ? 'A client rated your service.' : '$clientName reviewed your profile.';
      case MechanicNotificationKind.paymentReceived:
        return '$clientName sent your payment.';
      case MechanicNotificationKind.emergencyPosted:
        return '$clientName posted an emergency job near you.';
      case MechanicNotificationKind.accountApproved:
        return 'A moderator approved your account. You can take jobs now.';
    }
  }
}

/// The mechanic's notification log, behind the bell in the Mechanic shell.
///
/// It lives on its own rather than inside `QuoteNotificationStore` because
/// its six events come from three different stores — quotes/payments/
/// emergencies from `QuoteNotificationStore`, ratings from `ReviewStore`,
/// approvals from `MechanicAccountStore`. This file imports none of them, so
/// all three can raise into it without an import cycle.
///
/// Read/unread behaves exactly like the client's log: entries arrive unread,
/// and opening the list marks them read, which clears the badge.
class MechanicNotificationStore extends ChangeNotifier {
  MechanicNotificationStore._internal();
  static final MechanicNotificationStore instance = MechanicNotificationStore._internal();

  final List<MechanicNotification> _items = [];

  /// Everything [mechanicName] should see, newest first — their own entries
  /// plus the broadcast ones.
  List<MechanicNotification> notificationsFor(String mechanicName) => List.unmodifiable(
        _items.where((n) => n.mechanicName == null || n.mechanicName == mechanicName),
      );

  /// What the bell's badge displays for [mechanicName]. Zero hides the badge.
  int unreadCountFor(String mechanicName) =>
      notificationsFor(mechanicName).where((n) => !n.read).length;

  /// Called when the mechanic opens the notifications list — this is what
  /// makes the badge go away.
  void markSeenFor(String mechanicName) {
    if (unreadCountFor(mechanicName) == 0) return;
    for (final n in notificationsFor(mechanicName)) {
      n.read = true;
    }
    notifyListeners();
  }

  /// Records one event. Unlike the client log this notifies on its own, since
  /// the stores that raise into it are notifying their own listeners about a
  /// different change.
  void add({
    required MechanicNotificationKind kind,
    required String? mechanicName,
    required String clientName,
    required String detail,
    String? requestId,
    String? quoteId,
  }) {
    _items.insert(
      0,
      MechanicNotification(
        id: '${DateTime.now().microsecondsSinceEpoch}_${_items.length}',
        kind: kind,
        mechanicName: mechanicName,
        clientName: clientName,
        detail: detail,
        requestId: requestId,
        quoteId: quoteId,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  /// Drops everything tied to [requestId] — used when a client deletes the
  /// request, so no entry outlives the job it describes.
  void removeForRequest(String requestId) {
    final before = _items.length;
    _items.removeWhere((n) => n.requestId == requestId);
    if (_items.length != before) notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
