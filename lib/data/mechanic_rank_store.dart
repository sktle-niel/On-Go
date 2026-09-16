import 'package:flutter/foundation.dart';

import '../services/backend/mobile_backend.dart';
import 'mechanic_performance_store.dart';
import 'rank_policy_store.dart';
import 'review_store.dart';

/// Something that adds to a mechanic's points multiplier on top of their rank.
///
/// A store implements this and is registered with
/// [MechanicRankStore.addBonusProvider]; its bonuses are added to the rank
/// multiplier rather than replacing it. Nothing implements it yet. (The
/// seasonal Gem multiplier is not one of these — it multiplies, see
/// `LeaderboardStore.multiplierFor`.)
abstract interface class MultiplierBonusProvider {
  List<MultiplierBonus> bonusesFor(String mechanicName);
}

/// A mechanic's rank and the points multiplier it gives them — long-term
/// progression that never resets.
///
/// Worked out on demand from what they have actually done: completed jobs
/// recorded in [MechanicPerformanceStore], and the reviews clients left on
/// their profile in [ReviewStore] — count and average — against the admin's
/// [RankPolicyStore]. Nothing is stored, so a rank can never disagree with the
/// records it comes from.
///
/// Rank is not leaderboard placement: job evaluations and seasonal scores play
/// no part in it.
class MechanicRankStore {
  MechanicRankStore._internal();
  static final MechanicRankStore instance = MechanicRankStore._internal();

  final List<MultiplierBonusProvider> _bonusProviders = [];

  /// Fires whenever a rank may have changed: a job completed, a profile review
  /// written, the admin's ranks updated.
  late final Listenable changes = Listenable.merge([
    MechanicPerformanceStore.instance,
    ReviewStore.instance,
    RankPolicyStore.instance,
  ]);

  void addBonusProvider(MultiplierBonusProvider provider) {
    if (!_bonusProviders.contains(provider)) _bonusProviders.add(provider);
  }

  void removeBonusProvider(MultiplierBonusProvider provider) => _bonusProviders.remove(provider);

  MechanicStanding standingFor(String mechanicName) {
    final reviews = ReviewStore.instance;
    return MechanicStanding(
      completedJobs: MechanicPerformanceStore.instance.performanceFor(mechanicName).completedJobs,
      reviews: reviews.ratingCountFor(mechanicName),
      averageRating: reviews.averageRatingFor(mechanicName),
    );
  }

  MechanicRank rankFor(String mechanicName) =>
      RankPolicyStore.instance.current.rankFor(standingFor(mechanicName));

  RankProgress progressFor(String mechanicName) =>
      RankPolicyStore.instance.current.progressFor(standingFor(mechanicName));

  /// The mechanic's rank multiplier, plus every bonus a registered provider
  /// grants them. The seasonal multiplier and cap are added by
  /// `LeaderboardStore.multiplierFor`, which is what pays out.
  PointsMultiplier multiplierFor(String mechanicName) {
    final policy = RankPolicyStore.instance.current;
    final rank = policy.rankFor(standingFor(mechanicName));
    var multiplier = PointsMultiplier(rank: rank, rankMultiplier: policy.tierFor(rank).multiplier);
    for (final provider in _bonusProviders) {
      for (final bonus in provider.bonusesFor(mechanicName)) {
        multiplier = multiplier.withBonus(bonus);
      }
    }
    return multiplier;
  }

  @visibleForTesting
  void debugClearBonusProviders() => _bonusProviders.clear();
}
