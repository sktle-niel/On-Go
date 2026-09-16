import 'package:flutter/foundation.dart';

import '../services/local/record_box.dart';
import 'app_session.dart';
import 'client_account_store.dart';
import 'mechanic_notification_store.dart';

/// A client's review of a mechanic's profile — their personal opinion of the
/// mechanic, written from the profile.
///
/// Not a job evaluation. A job evaluation ([JobEvaluationStore]) is about one
/// completed job, anonymous to the mechanic, and feeds performance statistics
/// and the future seasonal leaderboard. A profile review is signed, one per
/// client per mechanic, can be edited, and is what a mechanic's profile rating,
/// review count and rank are built from.
class MechanicReview {
  final String id;
  final String clientName;
  final String mechanicName;
  int rating;
  String comment;
  DateTime date;
  final Set<String> likedBy;

  MechanicReview({
    required this.id,
    required this.clientName,
    required this.mechanicName,
    required this.rating,
    required this.comment,
    required this.date,
    Set<String>? likedBy,
  }) : likedBy = likedBy ?? <String>{};

  int get helpfulCount => likedBy.length;
  bool likedByViewer(String? viewerId) => viewerId != null && likedBy.contains(viewerId);

  Map<String, dynamic> toJson() => {
        'id': id,
        'clientName': clientName,
        'mechanicName': mechanicName,
        'rating': rating,
        'comment': comment,
        'date': date.toIso8601String(),
        'likedBy': likedBy.toList(),
      };

  static MechanicReview? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final client = json['clientName'];
    final mechanic = json['mechanicName'];
    final rating = json['rating'];
    final date = DateTime.tryParse('${json['date']}');
    if (id is! String || client is! String || mechanic is! String || rating is! num || date == null) return null;
    if (rating < 1 || rating > 5) return null;
    return MechanicReview(
      id: id,
      clientName: client,
      mechanicName: mechanic,
      rating: rating.toInt(),
      comment: json['comment'] is String ? json['comment'] as String : '',
      date: date,
      likedBy: {
        if (json['likedBy'] is List) ...(json['likedBy'] as List).whereType<String>(),
      },
    );
  }
}

/// Mechanic profile reviews left by clients, saved on this device.
///
/// WRITING is CLIENT-ONLY, enforced at runtime: [submitReview] checks
/// [AppSession.instance.currentRole] and throws if called while anything
/// other than the Client UI is the active shell — not just "no write-review
/// button in the Mechanic UI." Mechanics (and clients) can freely READ via
/// [reviewsFor] / [averageRatingFor] / [ratingDistributionFor], and both can
/// mark a review helpful via [toggleHelpful] — liking isn't authorship, so
/// it isn't role-gated.
///
/// Enforces one review per client per mechanic — submitting again edits
/// the existing review instead of creating a duplicate.
class ReviewStore extends ChangeNotifier {
  ReviewStore._internal();
  static final ReviewStore instance = ReviewStore._internal();

  /// The single source of truth for "who is the client" when writing/owning
  /// a review — pulled live from ClientAccountStore so demo/registered
  /// clients are attributed correctly instead of a hardcoded placeholder
  /// name that never matched who was actually signed in. Jobs, and so their
  /// evaluations, are recorded against it too.
  static String get currentClientName {
    final name = ClientAccountStore.instance.name;
    return name.isEmpty ? 'Client' : name;
  }

  RecordWriter _writer = RecordWriter(const SharedPreferencesRecordBox('profile_reviews'));
  final List<MechanicReview> _reviews = [];

  /// Reads what was saved. Safe to call before `runApp`.
  Future<void> load() async {
    final records = await _writer.box.load();
    for (final json in records) {
      final review = MechanicReview.fromJson(json);
      if (review == null || _reviews.any((r) => r.id == review.id)) continue;
      // Anything already in memory is newer than what was saved.
      if (_reviews.any((r) => r.mechanicName == review.mechanicName && r.clientName == review.clientName)) continue;
      _reviews.add(review);
    }
    _reviews.sort((a, b) => a.date.compareTo(b.date));
    notifyListeners();
  }

  /// Every mechanic someone has reviewed.
  Set<String> get reviewedMechanics => {for (final review in _reviews) review.mechanicName};

  /// Most recent first.
  List<MechanicReview> reviewsFor(String mechanicName) =>
      _reviews.where((r) => r.mechanicName == mechanicName).toList()..sort((a, b) => b.date.compareTo(a.date));

  MechanicReview? reviewByCurrentClientFor(String mechanicName) {
    final match = _reviews.where((r) => r.mechanicName == mechanicName && r.clientName == currentClientName);
    return match.isEmpty ? null : match.first;
  }

  MechanicReview? reviewById(String reviewId) {
    final match = _reviews.where((r) => r.id == reviewId);
    return match.isEmpty ? null : match.first;
  }

  int ratingCountFor(String mechanicName) => _reviews.where((r) => r.mechanicName == mechanicName).length;

  double averageRatingFor(String mechanicName) {
    final list = reviewsFor(mechanicName);
    if (list.isEmpty) return 0;
    return list.map((r) => r.rating).reduce((a, b) => a + b) / list.length;
  }

  Map<int, double> ratingDistributionFor(String mechanicName) {
    final list = reviewsFor(mechanicName);
    if (list.isEmpty) return {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    final counts = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    for (final r in list) {
      counts[r.rating] = (counts[r.rating] ?? 0) + 1;
    }
    return counts.map((star, count) => MapEntry(star, count / list.length));
  }

  /// CLIENT-ONLY. Throws [StateError] if the active shell isn't the Client
  /// UI. Mechanics have no path to this method at all in their screens —
  /// this is the backstop in case anything ever tries to call it anyway.
  void submitReview({
    required String mechanicName,
    required int rating,
    required String comment,
  }) {
    if (AppSession.instance.currentRole != AppRole.client) {
      throw StateError('Only the Client UI can submit reviews. Mechanics can view reviews only.');
    }
    if (rating < 1 || rating > 5) {
      throw StateError('Choose a rating from 1 to 5 stars.');
    }
    if (mechanicName == currentClientName) {
      throw StateError("You can't review your own profile.");
    }

    final text = comment.trim();
    final existing = reviewByCurrentClientFor(mechanicName);
    if (existing != null) {
      existing.rating = rating;
      existing.comment = text;
      existing.date = DateTime.now();
    } else {
      _reviews.add(MechanicReview(
        id: 'rev_${DateTime.now().microsecondsSinceEpoch}',
        clientName: currentClientName,
        mechanicName: mechanicName,
        rating: rating,
        comment: text,
        date: DateTime.now(),
      ));
    }
    _save();
    // Editing an existing review counts too — the mechanic's rating changed
    // either way, and that is what they are being told about.
    MechanicNotificationStore.instance.add(
      kind: MechanicNotificationKind.rated,
      mechanicName: mechanicName,
      clientName: currentClientName,
      detail: '$rating★${text.isEmpty ? '' : ' · $text'}',
    );
    notifyListeners();
  }

  /// Toggles "helpful" on a review for the current viewer (client OR
  /// mechanic — liking is a read-side interaction, not authorship, so it's
  /// not role-gated the way [submitReview] is). No-op if there's no active
  /// viewer identity yet.
  void toggleHelpful(String reviewId) {
    final viewerId = AppSession.instance.currentViewerName;
    if (viewerId == null) return;
    final review = reviewById(reviewId);
    if (review == null) return;

    if (!review.likedBy.remove(viewerId)) review.likedBy.add(viewerId);
    _save();
    notifyListeners();
  }

  void _save() => _writer.write([for (final review in _reviews) review.toJson()]);

  /// Test hook: keeps reviews in [box] from now on, starting empty.
  @visibleForTesting
  void debugUse(RecordBox box) {
    _writer = RecordWriter(box);
    _reviews.clear();
    notifyListeners();
  }

  /// Test hook: what a restart does — forget memory, read what was saved.
  @visibleForTesting
  Future<void> debugRestart() async {
    await _writer.idle;
    _reviews.clear();
    await load();
  }
}
