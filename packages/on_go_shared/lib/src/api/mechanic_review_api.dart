import '../models/mechanic_reviews.dart';

/// Reviews of mechanics, and the leaderboard built from them.
///
/// People are keyed by account id, not by display name. A new or edited review
/// reaches the rated mechanic on the event socket as `review.submitted`.
abstract interface class MechanicReviewApi {
  /// Creates or edits the caller's review of [mechanicId]. Clients only, and
  /// only once that mechanic has completed a paid job for them.
  Future<MechanicReviewEntry> submitReview(String mechanicId, ReviewSubmission review);

  /// A mechanic's reviews, newest first, with the average and star shares.
  Future<MechanicReviewSummary> fetchReviews(String mechanicId);

  /// Marks a review helpful, once per account. Clients and mechanics.
  Future<ReviewHelpfulState> markHelpful(String reviewId);

  /// Takes the caller's helpful mark back.
  Future<ReviewHelpfulState> unmarkHelpful(String reviewId);

  /// Approved, active mechanics ranked by [sort]. [search] matches part of a
  /// name literally; each entry's rank is its place before the search.
  Future<List<LeaderboardEntry>> fetchLeaderboard({
    LeaderboardSort sort = LeaderboardSort.rating,
    String? search,
    int limit = 50,
  });

  /// Reviews of the signed-in mechanic, as they are submitted or edited.
  Stream<MechanicReviewEntry> watchReviewsOfMe();
}
