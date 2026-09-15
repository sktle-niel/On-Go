import 'json.dart';

/// One client's review of a mechanic.
///
/// A client holds at most one review per mechanic and edits it in place, so
/// [updatedAt] moves on every edit; it is the date a review list shows.
class MechanicReviewEntry {
  final String id;
  final String mechanicId;
  final String clientId;
  final String clientName;

  /// The latest job the mechanic completed for this client when the review was
  /// saved.
  final String? requestId;

  /// 1 to 5 stars.
  final int rating;

  final String comment;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int helpfulCount;

  /// Whether the signed-in account marked this review helpful.
  final bool likedByMe;

  const MechanicReviewEntry({
    required this.id,
    required this.mechanicId,
    required this.clientId,
    required this.clientName,
    required this.rating,
    required this.createdAt,
    required this.updatedAt,
    this.requestId,
    this.comment = '',
    this.helpfulCount = 0,
    this.likedByMe = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'mechanicId': mechanicId,
        'clientId': clientId,
        'clientName': clientName,
        'requestId': requestId,
        'rating': rating,
        'comment': comment,
        'createdAt': writeDate(createdAt),
        'updatedAt': writeDate(updatedAt),
        'helpfulCount': helpfulCount,
        'likedByMe': likedByMe,
      };

  factory MechanicReviewEntry.fromJson(Map<String, dynamic> json) => MechanicReviewEntry(
        id: readString(json['id']),
        mechanicId: readString(json['mechanicId']),
        clientId: readString(json['clientId']),
        clientName: readString(json['clientName']),
        requestId: readStringOrNull(json['requestId']),
        rating: readInt(json['rating']),
        comment: readString(json['comment']),
        createdAt: readDate(json['createdAt']),
        updatedAt: readDate(json['updatedAt']),
        helpfulCount: readInt(json['helpfulCount']),
        likedByMe: readBool(json['likedByMe']),
      );
}

/// Everything a mechanic's reviews page shows, in one response.
class MechanicReviewSummary {
  final String mechanicId;

  /// The average over every review; zero with none.
  final double average;

  final int count;

  /// Each star's share of the reviews, keyed 1 to 5, as fractions of one;
  /// all zero with none.
  final Map<int, double> distribution;

  /// Newest first, at most 200.
  final List<MechanicReviewEntry> reviews;

  const MechanicReviewSummary({
    required this.mechanicId,
    this.average = 0,
    this.count = 0,
    this.distribution = const {},
    this.reviews = const [],
  });

  /// The share of reviews that gave [stars]; zero for a star nobody gave.
  double shareFor(int stars) => distribution[stars] ?? 0;

  Map<String, dynamic> toJson() => {
        'mechanicId': mechanicId,
        'average': average,
        'count': count,
        'distribution': {for (var stars = 1; stars <= 5; stars++) '$stars': shareFor(stars)},
        'reviews': reviews.map((review) => review.toJson()).toList(),
      };

  factory MechanicReviewSummary.fromJson(Map<String, dynamic> json) {
    final raw = readObject(json['distribution']);
    return MechanicReviewSummary(
      mechanicId: readString(json['mechanicId']),
      average: readDouble(json['average']),
      count: readInt(json['count']),
      distribution: {for (var stars = 1; stars <= 5; stars++) stars: readDouble(raw['$stars'])},
      reviews: readObjectList(json['reviews'])
          .map(MechanicReviewEntry.fromJson)
          .toList(growable: false),
    );
  }
}

/// A review's helpful count after marking or unmarking it.
class ReviewHelpfulState {
  final String reviewId;
  final int helpfulCount;
  final bool likedByMe;

  const ReviewHelpfulState({
    required this.reviewId,
    this.helpfulCount = 0,
    this.likedByMe = false,
  });

  Map<String, dynamic> toJson() => {
        'reviewId': reviewId,
        'helpfulCount': helpfulCount,
        'likedByMe': likedByMe,
      };

  factory ReviewHelpfulState.fromJson(Map<String, dynamic> json) => ReviewHelpfulState(
        reviewId: readString(json['reviewId']),
        helpfulCount: readInt(json['helpfulCount']),
        likedByMe: readBool(json['likedByMe']),
      );
}

/// What a client sends to create or edit their review of a mechanic.
class ReviewSubmission {
  /// 1 to 5 stars.
  final int rating;

  final String? comment;

  const ReviewSubmission({required this.rating, this.comment});

  Map<String, dynamic> toJson() => {
        'rating': rating,
        if (comment != null) 'comment': comment,
      };
}

/// How the leaderboard is ranked.
enum LeaderboardSort {
  rating('rating'),
  reviews('reviews');

  const LeaderboardSort(this.wireName);

  final String wireName;
}

/// One mechanic's place on the leaderboard.
class LeaderboardEntry {
  /// Place in the whole ranking for the chosen sort, before any search.
  final int rank;

  final String mechanicId;
  final String name;
  final String? photoUrl;
  final double rating;
  final int reviewCount;
  final int completedJobs;

  const LeaderboardEntry({
    required this.rank,
    required this.mechanicId,
    required this.name,
    this.photoUrl,
    this.rating = 0,
    this.reviewCount = 0,
    this.completedJobs = 0,
  });

  Map<String, dynamic> toJson() => {
        'rank': rank,
        'mechanicId': mechanicId,
        'name': name,
        'photoUrl': photoUrl,
        'rating': rating,
        'reviewCount': reviewCount,
        'completedJobs': completedJobs,
      };

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) => LeaderboardEntry(
        rank: readInt(json['rank']),
        mechanicId: readString(json['mechanicId']),
        name: readString(json['name']),
        photoUrl: readStringOrNull(json['photoUrl']),
        rating: readDouble(json['rating']),
        reviewCount: readInt(json['reviewCount']),
        completedJobs: readInt(json['completedJobs']),
      );
}
