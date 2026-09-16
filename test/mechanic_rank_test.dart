import 'package:flutter_test/flutter_test.dart';
import 'package:on_go/data/app_session.dart';
import 'package:on_go/data/mechanic_account_store.dart';
import 'package:on_go/data/mechanic_notification_store.dart';
import 'package:on_go/data/mechanic_rank_store.dart';
import 'package:on_go/data/points_policy_store.dart';
import 'package:on_go/data/points_wallet_store.dart';
import 'package:on_go/data/quote_store.dart';
import 'package:on_go/data/rank_policy_store.dart';
import 'package:on_go_shared/on_go_shared.dart';

import 'performance_test_support.dart';

QuoteNotificationStore get _store => QuoteNotificationStore.instance;

String get _mechanic => QuoteNotificationStore.currentMechanicName;

/// One Urgent job taken from upload to payment, as the two apps drive it.
HelpRequest _payUrgentJob(String id) {
  AppSession.instance.setRole(AppRole.client, viewerName: 'Client');
  _store.submitRequest(HelpRequest(
    id: id,
    problem: 'Flat tire',
    location: 'Puerto Princesa City',
    urgency: 'Urgent',
    photoPaths: const [],
    createdAt: DateTime.now(),
    clientName: 'Client',
  ));
  _store.mechanicSendQuote(id, mechanicName: _mechanic, price: '₱450', eta: const Duration(hours: 1), rating: 4.8);
  _store.clientAcceptQuote(_store.quotesForRequest(id).first.id);
  AppSession.instance.setRole(AppRole.mechanic, viewerName: _mechanic);
  _store.mechanicCompleteService(id);
  AppSession.instance.setRole(AppRole.client, viewerName: 'Client');
  _store.clientConfirmPayment(id);
  return _store.requestFor(id)!;
}

class _FakeBadges implements MultiplierBonusProvider {
  _FakeBadges(this.amount);
  final double amount;

  @override
  List<MultiplierBonus> bonusesFor(String mechanicName) =>
      [MultiplierBonus(source: 'test:badge', label: 'Test badge', amount: amount)];
}

void main() {
  group('rank policy', () {
    const policy = RankPolicy.defaults;

    test('five ranks in order, with Platinum reaching x3', () {
      expect(MechanicRank.values.map((r) => r.label), ['Iron', 'Bronze', 'Silver', 'Gold', 'Platinum']);
      expect([for (final r in MechanicRank.values) policy.tierFor(r).multiplier], [1, 1.25, 1.5, 2, 3]);
      expect(policy.isValid, isTrue);
    });

    test('a rank needs all three of jobs, reviews and average rating', () {
      expect(policy.rankFor(const MechanicStanding()), MechanicRank.iron);
      expect(policy.rankFor(const MechanicStanding(completedJobs: 10, reviews: 5, averageRating: 3.5)),
          MechanicRank.bronze);
      expect(policy.rankFor(const MechanicStanding(completedJobs: 500, reviews: 500, averageRating: 3.4)),
          MechanicRank.iron, reason: 'plenty of work, rating too low for Bronze');
      expect(policy.rankFor(const MechanicStanding(completedJobs: 80, reviews: 45, averageRating: 4.9)),
          MechanicRank.gold);
      expect(policy.rankFor(const MechanicStanding(completedJobs: 150, reviews: 80, averageRating: 4.6)),
          MechanicRank.platinum);
    });

    test('progress names the next rank and what it needs; none past the top', () {
      final progress = policy.progressFor(const MechanicStanding(completedJobs: 12, reviews: 6, averageRating: 3.9));
      expect(progress.rank, MechanicRank.bronze);
      expect(progress.next, MechanicRank.silver);
      expect(progress.nextRequirement!.completedJobs, 30);

      expect(policy.progressFor(const MechanicStanding(completedJobs: 999, reviews: 999, averageRating: 5)).isTopRank,
          isTrue);
    });

    test('settings that would break the ladder are refused', () {
      RankTier tier(MechanicRank r) => policy.tierFor(r);
      expect(policy.withTier(MechanicRank.platinum, tier(MechanicRank.platinum).copyWith(multiplier: 3.5)).problem,
          contains('between x1 and x3'));
      expect(policy.withTier(MechanicRank.silver, tier(MechanicRank.silver).copyWith(multiplier: 1.1)).problem,
          contains("Silver's multiplier cannot be lower than Bronze's"));
      expect(
          policy
              .withTier(MechanicRank.gold,
                  tier(MechanicRank.gold).copyWith(requirement: const RankRequirement(completedJobs: 20, reviews: 40, averageRating: 4.3)))
              .problem,
          contains('Gold must require at least as much as Silver'));
      expect(
          policy
              .withTier(MechanicRank.iron, tier(MechanicRank.iron).copyWith(requirement: const RankRequirement(completedJobs: 1)))
              .problem,
          contains('Iron is where every mechanic starts'));
      expect(
          policy
              .withTier(MechanicRank.bronze,
                  tier(MechanicRank.bronze).copyWith(requirement: const RankRequirement(completedJobs: 10, reviews: 5, averageRating: 6)))
              .problem,
          contains('between 0 and 5'));
    });

    test('survives a round trip', () {
      final edited = policy.withTier(
        MechanicRank.gold,
        const RankTier(requirement: RankRequirement(completedJobs: 60, reviews: 40, averageRating: 4.2), multiplier: 2.5),
      );
      expect(RankPolicy.fromJson(edited.toJson()), edited);
    });
  });

  group('points multiplier', () {
    test('a bonus is added to the rank multiplier, never replacing it', () {
      const platinum = PointsMultiplier(rank: MechanicRank.platinum, rankMultiplier: 3);
      final withGem = platinum.withBonus(const MultiplierBonus(source: 'gem_badge:test', label: 'Gem', amount: 0.5));

      expect(platinum.total, 3);
      expect(withGem.rankMultiplier, 3);
      expect(withGem.total, 3.5);
      expect(withGem.apply(5), 17.5);
      expect(formatMultiplier(withGem.total), 'x3.5');
    });
  });

  group('a mechanic\'s rank scales the points they earn', () {
    setUp(() {
      _store.clear();
      resetPerformanceStores();
      MechanicNotificationStore.instance.clear();
      MechanicAccountStore.instance.enterDemoMode();
      MechanicRankStore.instance.debugClearBonusProviders();
      // Bronze after a single job, so the test does not need ten.
      RankPolicyStore.instance.debugSet(RankPolicy.defaults.withTier(
        MechanicRank.bronze,
        const RankTier(requirement: RankRequirement(completedJobs: 1), multiplier: 1.5),
      ));
    });

    tearDown(() {
      RankPolicyStore.instance.debugSet(RankPolicy.defaults);
      PointsPolicyStore.instance.debugSet(PointsPolicy.defaults);
      MechanicRankStore.instance.debugClearBonusProviders();
    });

    test('Iron earns the base points; after ranking up, the multiplier applies — the client is unchanged', () {
      final wallet = PointsWalletStore.instance;
      final clientBefore = wallet.balanceFor('Client');
      final mechanicBefore = wallet.balanceFor(_mechanic);

      expect(MechanicRankStore.instance.rankFor(_mechanic), MechanicRank.iron);
      final first = _payUrgentJob('rank-1');
      expect(first.pointsAwarded, 3, reason: 'Iron x1: the rank is what stood before this job');
      expect(first.pointsMultiplier, 1);

      expect(MechanicRankStore.instance.rankFor(_mechanic), MechanicRank.bronze);
      final second = _payUrgentJob('rank-2');
      expect(second.pointsAwarded, 4.5, reason: 'Bronze x1.5 on 3 pts');
      expect(second.pointsMultiplier, 1.5);

      expect(wallet.balanceFor(_mechanic) - mechanicBefore, 7.5);
      expect(wallet.balanceFor('Client') - clientBefore, 6, reason: 'clients are not ranked');
    });

    test('a registered bonus is added on top of the rank multiplier', () {
      _payUrgentJob('rank-1');
      MechanicRankStore.instance.addBonusProvider(_FakeBadges(0.5));

      final multiplier = MechanicRankStore.instance.multiplierFor(_mechanic);
      expect(multiplier.rank, MechanicRank.bronze);
      expect(multiplier.rankMultiplier, 1.5);
      expect(multiplier.total, 2);

      expect(_payUrgentJob('rank-2').pointsAwarded, 6);
    });

    test('progress reads the jobs and reviews the mechanic actually has', () {
      final progress = MechanicRankStore.instance.progressFor(_mechanic);
      expect(progress.standing.completedJobs, 0);
      expect(progress.next, MechanicRank.bronze);

      _payUrgentJob('rank-1');
      expect(MechanicRankStore.instance.standingFor(_mechanic).completedJobs, 1);
    });
  });
}
