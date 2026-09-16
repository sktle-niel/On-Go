import 'dart:math' as math;

import 'json.dart';
import 'points_policy.dart';

/// A mechanic's rank, lowest first. The order is the progression: a mechanic
/// climbs one rank at a time.
enum MechanicRank {
  iron('iron', 'Iron'),
  bronze('bronze', 'Bronze'),
  silver('silver', 'Silver'),
  gold('gold', 'Gold'),
  platinum('platinum', 'Platinum');

  const MechanicRank(this.wireName, this.label);

  final String wireName;
  final String label;

  /// The rank above this one, or null at the top.
  MechanicRank? get next => index + 1 < values.length ? values[index + 1] : null;

  /// The rank below this one, or null at the bottom.
  MechanicRank? get previous => index == 0 ? null : values[index - 1];

  static MechanicRank fromWire(String value) => MechanicRank.values.firstWhere(
        (rank) => rank.wireName == value,
        orElse: () => MechanicRank.iron,
      );
}

/// What a mechanic has done so far — the three figures rank is worked out
/// from.
class MechanicStanding {
  const MechanicStanding({this.completedJobs = 0, this.reviews = 0, this.averageRating = 0});

  final int completedJobs;
  final int reviews;

  /// 0 when there are no reviews.
  final double averageRating;
}

/// What a rank asks for. A mechanic reaches it by meeting all three.
class RankRequirement {
  const RankRequirement({this.completedJobs = 0, this.reviews = 0, this.averageRating = 0});

  /// Iron's: every mechanic starts there.
  static const RankRequirement none = RankRequirement();

  final int completedJobs;
  final int reviews;

  /// Out of [maxRating].
  final double averageRating;

  bool isMetBy(MechanicStanding standing) =>
      standing.completedJobs >= completedJobs &&
      standing.reviews >= reviews &&
      standing.averageRating >= averageRating;

  /// Whether this asks for at least as much as [lower] on every figure — what
  /// a higher rank must do, so ranks can only be climbed in order.
  bool covers(RankRequirement lower) =>
      completedJobs >= lower.completedJobs &&
      reviews >= lower.reviews &&
      averageRating >= lower.averageRating;

  Map<String, dynamic> toJson() => {
        'completedJobs': completedJobs,
        'reviews': reviews,
        'averageRating': averageRating,
      };

  factory RankRequirement.fromJson(Map<String, dynamic> json, RankRequirement fallback) => RankRequirement(
        completedJobs: json['completedJobs'] is num ? readInt(json['completedJobs']) : fallback.completedJobs,
        reviews: json['reviews'] is num ? readInt(json['reviews']) : fallback.reviews,
        averageRating: readDouble(json['averageRating'], fallback.averageRating),
      );

  @override
  bool operator ==(Object other) =>
      other is RankRequirement &&
      other.completedJobs == completedJobs &&
      other.reviews == reviews &&
      other.averageRating == averageRating;

  @override
  int get hashCode => Object.hash(completedJobs, reviews, averageRating);
}

/// One rank's settings: what it asks for, and the points multiplier it gives.
class RankTier {
  const RankTier({required this.requirement, required this.multiplier});

  final RankRequirement requirement;

  /// Applied to the points a mechanic earns on a paid job — x1 to
  /// [maxRankMultiplier].
  final double multiplier;

  RankTier copyWith({RankRequirement? requirement, double? multiplier}) => RankTier(
        requirement: requirement ?? this.requirement,
        multiplier: multiplier ?? this.multiplier,
      );

  Map<String, dynamic> toJson() => {
        'requirement': requirement.toJson(),
        'multiplier': multiplier,
      };

  factory RankTier.fromJson(Map<String, dynamic> json, RankTier fallback) => RankTier(
        requirement: json['requirement'] is Map
            ? RankRequirement.fromJson(readObject(json['requirement']), fallback.requirement)
            : fallback.requirement,
        multiplier: readDouble(json['multiplier'], fallback.multiplier),
      );

  @override
  bool operator ==(Object other) =>
      other is RankTier && other.requirement == requirement && other.multiplier == multiplier;

  @override
  int get hashCode => Object.hash(requirement, multiplier);
}

/// The lowest multiplier a rank can give.
const double minRankMultiplier = 1;

/// The highest — what the top rank can reach.
const double maxRankMultiplier = 3;

/// The top of the rating scale.
const double maxRating = 5;

/// Every rank's requirements and multiplier, set by the admin.
///
/// Nothing in the app carries its own thresholds: a mechanic's rank, their
/// progress towards the next one and the multiplier on their points are all
/// worked out from this. [defaults] is the starting point the admin edits.
class RankPolicy {
  const RankPolicy({
    this.iron = const RankTier(requirement: RankRequirement.none, multiplier: 1),
    this.bronze = const RankTier(
      requirement: RankRequirement(completedJobs: 10, reviews: 5, averageRating: 3.5),
      multiplier: 1.25,
    ),
    this.silver = const RankTier(
      requirement: RankRequirement(completedJobs: 30, reviews: 15, averageRating: 4.0),
      multiplier: 1.5,
    ),
    this.gold = const RankTier(
      requirement: RankRequirement(completedJobs: 75, reviews: 40, averageRating: 4.3),
      multiplier: 2,
    ),
    this.platinum = const RankTier(
      requirement: RankRequirement(completedJobs: 150, reviews: 80, averageRating: 4.6),
      multiplier: maxRankMultiplier,
    ),
  });

  static const RankPolicy defaults = RankPolicy();

  final RankTier iron;
  final RankTier bronze;
  final RankTier silver;
  final RankTier gold;
  final RankTier platinum;

  RankTier tierFor(MechanicRank rank) => switch (rank) {
        MechanicRank.iron => iron,
        MechanicRank.bronze => bronze,
        MechanicRank.silver => silver,
        MechanicRank.gold => gold,
        MechanicRank.platinum => platinum,
      };

  RankPolicy withTier(MechanicRank rank, RankTier tier) => RankPolicy(
        iron: rank == MechanicRank.iron ? tier : iron,
        bronze: rank == MechanicRank.bronze ? tier : bronze,
        silver: rank == MechanicRank.silver ? tier : silver,
        gold: rank == MechanicRank.gold ? tier : gold,
        platinum: rank == MechanicRank.platinum ? tier : platinum,
      );

  /// The highest rank [standing] has reached. Ranks are climbed in order: a
  /// rank counts only once every rank below it is met too.
  MechanicRank rankFor(MechanicStanding standing) {
    var reached = MechanicRank.iron;
    for (final rank in MechanicRank.values.skip(1)) {
      if (!tierFor(rank).requirement.isMetBy(standing)) break;
      reached = rank;
    }
    return reached;
  }

  /// Where [standing] is, and what the next rank asks for.
  RankProgress progressFor(MechanicStanding standing) {
    final rank = rankFor(standing);
    final next = rank.next;
    return RankProgress(
      rank: rank,
      standing: standing,
      next: next,
      nextRequirement: next == null ? null : tierFor(next).requirement,
    );
  }

  /// Why this policy cannot be used, worded for the admin — or null when it
  /// can.
  String? get problem {
    for (final rank in MechanicRank.values) {
      final tier = tierFor(rank);
      final requirement = tier.requirement;
      if (tier.multiplier < minRankMultiplier || tier.multiplier > maxRankMultiplier) {
        return '${rank.label}: the multiplier must be between '
            '${formatMultiplier(minRankMultiplier)} and ${formatMultiplier(maxRankMultiplier)}.';
      }
      if (requirement.completedJobs < 0 || requirement.reviews < 0) {
        return '${rank.label}: requirements cannot be negative.';
      }
      if (requirement.averageRating < 0 || requirement.averageRating > maxRating) {
        return '${rank.label}: the average rating must be between 0 and ${formatPoints(maxRating)}.';
      }

      final previous = rank.previous;
      if (previous == null) {
        if (requirement != RankRequirement.none) {
          return 'Iron is where every mechanic starts, so it has no requirements.';
        }
        continue;
      }
      final below = tierFor(previous);
      if (!requirement.covers(below.requirement)) {
        return '${rank.label} must require at least as much as ${previous.label}.';
      }
      if (tier.multiplier < below.multiplier) {
        return "${rank.label}'s multiplier cannot be lower than ${previous.label}'s.";
      }
    }
    return null;
  }

  bool get isValid => problem == null;

  Map<String, dynamic> toJson() => {
        for (final rank in MechanicRank.values) rank.wireName: tierFor(rank).toJson(),
      };

  factory RankPolicy.fromJson(Map<String, dynamic> json) {
    RankTier read(MechanicRank rank) =>
        RankTier.fromJson(readObject(json[rank.wireName]), defaults.tierFor(rank));
    return RankPolicy(
      iron: read(MechanicRank.iron),
      bronze: read(MechanicRank.bronze),
      silver: read(MechanicRank.silver),
      gold: read(MechanicRank.gold),
      platinum: read(MechanicRank.platinum),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RankPolicy &&
      other.iron == iron &&
      other.bronze == bronze &&
      other.silver == silver &&
      other.gold == gold &&
      other.platinum == platinum;

  @override
  int get hashCode => Object.hash(iron, bronze, silver, gold, platinum);
}

/// A mechanic's rank, and how far they are from the next.
class RankProgress {
  const RankProgress({
    required this.rank,
    required this.standing,
    this.next,
    this.nextRequirement,
  });

  final MechanicRank rank;
  final MechanicStanding standing;

  /// Null at the top rank.
  final MechanicRank? next;
  final RankRequirement? nextRequirement;

  bool get isTopRank => next == null;
}

/// An additive bonus on top of the rank multiplier, from something other than
/// rank or the seasonal leaderboard (whose placement multiplier is
/// [PointsMultiplier.leaderboardMultiplier]).
///
/// Nothing grants one yet; [MultiplierBonusProvider] is where one would plug in.
class MultiplierBonus {
  const MultiplierBonus({required this.source, required this.label, required this.amount});

  /// Where it comes from, stable across renames — e.g. `gem_badge:ruby`.
  final String source;

  /// How it reads to a person.
  final String label;

  /// Added to the multiplier: 0.5 makes x3 into x3.5.
  final double amount;
}

/// The multiplier on a mechanic's reward points, and what it is made of:
///
/// (rank multiplier + additive bonuses) × seasonal leaderboard multiplier,
/// never more than [cap].
///
/// The rank multiplier is long-term and the leaderboard multiplier seasonal;
/// neither replaces the other. Base 20 × rank x2 × seasonal x1.1 = 44. The cap
/// is what keeps bonus systems added later from stacking without limit.
class PointsMultiplier {
  const PointsMultiplier({
    required this.rank,
    required this.rankMultiplier,
    this.bonuses = const [],
    this.leaderboardMultiplier = 1,
    this.cap,
  });

  /// No rank advantage and no bonus: x1.
  static const PointsMultiplier none = PointsMultiplier(rank: MechanicRank.iron, rankMultiplier: 1);

  final MechanicRank rank;
  final double rankMultiplier;
  final List<MultiplierBonus> bonuses;

  /// The seasonal multiplier from leaderboard placement; x1 without one.
  final double leaderboardMultiplier;

  /// The most the combination may multiply by, if one is configured.
  final double? cap;

  double get bonusTotal => bonuses.fold(0, (sum, bonus) => sum + bonus.amount);

  /// Everything multiplied together, before the cap.
  double get uncapped => (rankMultiplier + bonusTotal) * leaderboardMultiplier;

  /// What is applied: [uncapped], held to [cap].
  double get total {
    final limit = cap;
    return limit == null ? uncapped : math.min(uncapped, limit);
  }

  bool get isCapped => cap != null && uncapped > cap!;

  PointsMultiplier withBonus(MultiplierBonus bonus) => PointsMultiplier(
        rank: rank,
        rankMultiplier: rankMultiplier,
        bonuses: [...bonuses, bonus],
        leaderboardMultiplier: leaderboardMultiplier,
        cap: cap,
      );

  /// The same, with a seasonal multiplier and a cap.
  PointsMultiplier withLeaderboard(double multiplier, {double? cap}) => PointsMultiplier(
        rank: rank,
        rankMultiplier: rankMultiplier,
        bonuses: bonuses,
        leaderboardMultiplier: multiplier,
        cap: cap ?? this.cap,
      );

  /// [basePoints] — what the job's urgency awards — multiplied.
  double apply(double basePoints) => basePoints * total;
}

/// A multiplier as it reads on screen: `x1`, `x1.25`, `x3.5`.
String formatMultiplier(double multiplier) => 'x${formatPoints(multiplier)}';
