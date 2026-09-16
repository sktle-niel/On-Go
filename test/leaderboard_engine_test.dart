import 'package:flutter_test/flutter_test.dart';
import 'package:on_go_shared/on_go_shared.dart';

final _start = DateTime(2027, 1, 1);

Season _season({SeasonStatus status = SeasonStatus.active, DateTime? endedAt}) => Season(
      id: 's1',
      name: 'Season 1',
      startsAt: _start,
      endsAt: DateTime(2027, 5, 1),
      status: status,
      startedAt: status == SeasonStatus.scheduled ? null : _start,
      endedAt: endedAt,
    );

JobOutcome _done(
  String job,
  String mechanic, {
  DateTime? at,
  String client = 'client-a',
  // Null: no payout recorded — neither a small job nor any job value.
  double? payout = 1000,
  bool? onTime,
}) {
  final when = at ?? DateTime(2027, 2, 1, 10);
  return JobOutcome(
    id: JobOutcome.idFor(JobOutcomeKind.completed, job, mechanic, when),
    jobId: job,
    mechanicId: mechanic,
    kind: JobOutcomeKind.completed,
    at: when,
    clientId: client,
    payout: payout,
    arrivedOnTime: onTime,
  );
}

JobOutcome _dropped(String job, String mechanic, JobOutcomeKind kind, {DateTime? at}) {
  final when = at ?? DateTime(2027, 2, 2);
  return JobOutcome(id: JobOutcome.idFor(kind, job, mechanic, when), jobId: job, mechanicId: mechanic, kind: kind, at: when);
}

JobEvaluation _rated(String job, String mechanic, int stars, {DateTime? at, String client = 'client-a'}) {
  final when = at ?? DateTime(2027, 2, 1, 12);
  return JobEvaluation(
    jobId: job,
    clientId: client,
    mechanicId: mechanic,
    requiredAt: when,
    job: EvaluatedJobSummary(problem: 'Flat tire', location: 'Here', urgency: 'Normal', paidAt: when),
  ).submitted(EvaluationSubmission(rating: stars), at: when);
}

void main() {
  const engine = LeaderboardEngine(LeaderboardConfig.defaults);

  double total(List<ScoreLine> lines, String mechanic) =>
      lines.where((l) => l.mechanicId == mechanic).fold(0.0, (sum, l) => sum + l.points);

  group('scoring', () {
    test('a completed job: completion, on time, job value and the evaluation, each traced', () {
      final lines = engine.scoreLines(
        season: _season(),
        outcomes: [_done('j1', 'Ana', onTime: true, payout: 1500)],
        evaluations: [_rated('j1', 'Ana', 5)],
      );
      expect({for (final l in lines) l.source: l.points}, {
        ScoreSource.jobCompleted: 10,
        ScoreSource.onTimeArrival: 2,
        ScoreSource.jobValue: 1.5,
        ScoreSource.evaluation: 6,
      });
      expect(lines.firstWhere((l) => l.source == ScoreSource.evaluation).sourceId, 'evaluation_j1');
    });

    test('a small job earns a share; job value stops at its limit', () {
      final lines = engine.scoreLines(
        season: _season(),
        outcomes: [_done('small', 'Ana', payout: 200), _done('big', 'Ben', payout: 90000)],
        evaluations: const [],
      );
      expect(lines.firstWhere((l) => l.mechanicId == 'Ana' && l.source == ScoreSource.jobCompleted).points, 5);
      expect(lines.firstWhere((l) => l.mechanicId == 'Ben' && l.source == ScoreSource.jobValue).points, 3);
    });

    test('poor evaluations, cancellations and expiries cost points', () {
      final lines = engine.scoreLines(
        season: _season(),
        outcomes: [
          _done('j1', 'Ana', payout: null),
          _dropped('j2', 'Ana', JobOutcomeKind.cancelledByMechanic),
          _dropped('j3', 'Ana', JobOutcomeKind.expired),
        ],
        evaluations: [_rated('j1', 'Ana', 1)],
      );
      expect(total(lines, 'Ana'), 10 - 4 - 8 - 5);
    });

    test('jobs for one client in one day stop scoring past the limit — and are flagged', () {
      final outcomes = [
        for (var i = 0; i < 5; i++) _done('j$i', 'Ana', at: DateTime(2027, 2, 1, 8 + i * 2), payout: null),
      ];
      final lines = engine.scoreLines(season: _season(), outcomes: outcomes, evaluations: const []);
      expect(total(lines, 'Ana'), 20, reason: 'two of five score');

      final flags = engine.suspiciousActivity(season: _season(), outcomes: outcomes);
      expect(flags.map((f) => f.kind), contains(SuspiciousActivityKind.repeatClient));
    });

    test('many jobs within an hour are flagged for review, not removed', () {
      final outcomes = [
        for (var i = 0; i < 4; i++)
          _done('r$i', 'Ana', client: 'c$i', at: DateTime(2027, 2, 1, 9, i * 10), payout: null),
      ];
      final flags = engine.suspiciousActivity(season: _season(), outcomes: outcomes);
      expect(flags.single.kind, SuspiciousActivityKind.rapidJobs);
      expect(total(engine.scoreLines(season: _season(), outcomes: outcomes, evaluations: const []), 'Ana'), 40);
    });

    test('voiding an outcome or an evaluation removes exactly its points', () {
      final job = _done('j1', 'Ana', payout: null);
      final evaluation = _rated('j1', 'Ana', 5);
      expect(total(engine.scoreLines(season: _season(), outcomes: [job], evaluations: [evaluation]), 'Ana'), 16);
      expect(
        total(
          engine.scoreLines(
            season: _season(),
            outcomes: [job],
            evaluations: [evaluation.voided('Fraud', at: DateTime(2027, 3, 1))],
          ),
          'Ana',
        ),
        10,
      );
      expect(
        engine.scoreLines(
          season: _season(),
          outcomes: [job.voided('Refunded', at: DateTime(2027, 3, 1))],
          evaluations: [evaluation],
        ),
        isEmpty,
        reason: "an evaluation of a job that no longer counts earns nothing",
      );
    });

    test('an adjustment counts with its reason and actor', () {
      final lines = engine.scoreLines(
        season: _season(),
        outcomes: const [],
        evaluations: const [],
        adjustments: [
          ScoreAdjustment(
            id: 'a1',
            seasonId: 's1',
            mechanicId: 'Ana',
            points: -3,
            reason: 'Duplicate job',
            actor: 'Admin',
            createdAt: DateTime(2027, 2, 3),
          ),
        ],
      );
      expect(lines.single.points, -3);
      expect(lines.single.note, contains('Duplicate job'));
    });
  });

  group('season window', () {
    test('nothing before the start, nothing after it ended, nothing while scheduled', () {
      final before = _done('early', 'Ana', at: DateTime(2026, 12, 31), payout: null);
      final inside = _done('in', 'Ana', at: DateTime(2027, 2, 1), payout: null);
      final after = _done('late', 'Ana', at: DateTime(2027, 3, 2), payout: null);
      final outcomes = [before, inside, after];

      expect(total(engine.scoreLines(season: _season(), outcomes: outcomes, evaluations: const []), 'Ana'), 20,
          reason: 'nothing from before the start');
      expect(
        total(
          engine.scoreLines(
            season: _season(status: SeasonStatus.ended, endedAt: DateTime(2027, 3, 1)),
            outcomes: outcomes,
            evaluations: const [],
          ),
          'Ana',
        ),
        10,
        reason: 'only the job inside the window',
      );
      expect(
        engine.scoreLines(season: _season(status: SeasonStatus.scheduled), outcomes: outcomes, evaluations: const []),
        isEmpty,
      );
    });
  });

  group('standings', () {
    test('ties break on rating, then completed jobs, then fewer cancellations, then who got there first', () {
      final standings = engine.standings(
        season: _season(),
        outcomes: [
          // Ben and Cara: 10 for the job and 1 for a 3★ evaluation, at the
          // same moments. Dan and Eve: 10 each, Dan two hours sooner.
          _done('b1', 'Ben', payout: null),
          _done('c1', 'Cara', payout: null),
          _done('d1', 'Dan', payout: null, at: DateTime(2027, 2, 1, 9)),
          _done('e1', 'Eve', payout: null, at: DateTime(2027, 2, 1, 11)),
        ],
        evaluations: [
          _rated('b1', 'Ben', 3),
          _rated('c1', 'Cara', 3),
        ],
      );
      // Ben and Cara tie on everything but id; Dan and Eve tie but Dan was first.
      expect(standings.map((s) => s.mechanicId), ['Ben', 'Cara', 'Dan', 'Eve']);
      expect(standings.map((s) => s.placement), [1, 2, 3, 4]);
    });

    test('the same records always give the same order', () {
      final outcomes = [for (var i = 0; i < 8; i++) _done('j$i', 'M$i', client: 'c$i', payout: null)];
      final first = engine.standings(season: _season(), outcomes: outcomes, evaluations: const []);
      final second = engine.standings(season: _season(), outcomes: outcomes.reversed, evaluations: const []);
      expect(first.map((s) => s.mechanicId), second.map((s) => s.mechanicId));
    });

    test('a better rating wins a points tie', () {
      // Zed: 10 + 3★ (1) = 11. Abe: 10 + 1★ (−4) + an adjustment of +5 = 11.
      final standings = engine.standings(
        season: _season(),
        outcomes: [_done('a', 'Zed', payout: null), _done('b', 'Abe', payout: null, client: 'x')],
        evaluations: [_rated('a', 'Zed', 3), _rated('b', 'Abe', 1, client: 'x')],
        adjustments: [
          ScoreAdjustment(
            id: 'adj',
            seasonId: 's1',
            mechanicId: 'Abe',
            points: 5,
            reason: 'Disputed evaluation',
            actor: 'Admin',
            createdAt: DateTime(2027, 2, 1, 11),
          ),
        ],
      );
      expect(standings.map((s) => s.points), [11, 11]);
      expect(standings.first.mechanicId, 'Zed', reason: 'same points, better season rating');
    });
  });

  group('gems and multipliers', () {
    List<LeaderboardStanding> placed(int count) => engine.standings(
          season: _season(),
          outcomes: [
            for (var i = 0; i < count; i++)
              _done('j$i', 'M${i.toString().padLeft(3, '0')}', client: 'c$i', payout: null,
                  at: DateTime(2027, 2, 1).add(Duration(minutes: i * 90))),
          ],
          evaluations: const [],
        );

    test('a Gem shows the placement; outside the limit there is none', () {
      const narrow = LeaderboardEngine(LeaderboardConfig(gemMaxPlacement: 2));
      final standings = placed(3);
      expect(narrow.gemFor('M000', _season(), standings)?.label, '💎 #1 Gem');
      expect(narrow.gemFor('M002', _season(), standings), isNull);
    });

    test('placement tiers give the seasonal multiplier; x1 without a placement', () {
      expect(LeaderboardConfig.defaults.multiplierForPlacement(1), 1.5);
      expect(LeaderboardConfig.defaults.multiplierForPlacement(58), 1.1);
      expect(LeaderboardConfig.defaults.multiplierForPlacement(251), 1);
      expect(engine.seasonalMultiplierFor('nobody', placed(2)), 1);
    });

    test('stacked multipliers never pass the cap', () {
      const platinum = PointsMultiplier(rank: MechanicRank.platinum, rankMultiplier: 3);
      final platinumTopTen = platinum.withLeaderboard(1.5, cap: 4.5);
      expect(platinumTopTen.total, 4.5);
      expect(platinumTopTen.isCapped, isFalse);

      final withBadge = platinum
          .withBonus(const MultiplierBonus(source: 'gem', label: 'Gem', amount: 0.5))
          .withLeaderboard(1.5, cap: 4.5);
      expect(withBadge.uncapped, 5.25);
      expect(withBadge.total, 4.5);
      expect(withBadge.isCapped, isTrue);

      final record = PointTransaction.forJob(
        jobId: 'j1',
        mechanicId: 'Ana',
        basePoints: 20,
        multiplier: const PointsMultiplier(rank: MechanicRank.gold, rankMultiplier: 2).withLeaderboard(1.1, cap: 4.5),
        at: DateTime(2027, 2, 1),
      );
      expect(record.finalPoints, closeTo(44, 0.001));
      expect(record.rankMultiplier, 2);
      expect(record.leaderboardMultiplier, 1.1);
      expect(record.wasCapped, isFalse);
    });
  });

  group('settings', () {
    test('the defaults are valid and off', () {
      expect(LeaderboardConfig.defaults.isValid, isTrue);
      expect(LeaderboardConfig.defaults.enabled, isFalse);
    });

    test('unsafe values are refused with a reason', () {
      expect(LeaderboardConfig.defaults.copyWith(maxEffectiveMultiplier: 0.5).problem, isNotNull);
      expect(
        LeaderboardConfig.defaults
            .copyWith(scoring: const LeaderboardScoring(ratingPoints: [5, 4, 3, 2, 1]))
            .problem,
        isNotNull,
      );
      expect(
        LeaderboardConfig.defaults.copyWith(placementMultipliers: const [
          PlacementMultiplier(upToPlacement: 10, multiplier: 1.1),
          PlacementMultiplier(upToPlacement: 50, multiplier: 1.5),
        ]).problem,
        isNotNull,
      );
      expect(const LeaderboardScoring(cancellationPenalty: 3).problem, isNotNull);
    });

    test('survives a JSON round trip', () {
      final config = LeaderboardConfig.defaults.copyWith(enabled: true, gemMaxPlacement: 100);
      expect(LeaderboardConfig.fromJson(config.toJson()), config);
    });
  });
}
