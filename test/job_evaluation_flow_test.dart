import 'package:flutter_test/flutter_test.dart';
import 'package:on_go/data/app_session.dart';
import 'package:on_go/data/job_evaluation_store.dart';
import 'package:on_go/data/leaderboard_store.dart';
import 'package:on_go/data/mechanic_account_store.dart';
import 'package:on_go/data/mechanic_notification_store.dart';
import 'package:on_go/data/mechanic_performance_store.dart';
import 'package:on_go/data/mechanic_rank_store.dart';
import 'package:on_go/data/point_transaction_store.dart';
import 'package:on_go/data/problem_report_store.dart';
import 'package:on_go/data/quote_store.dart';
import 'package:on_go/data/review_store.dart';
import 'package:on_go_shared/on_go_shared.dart';

import 'performance_test_support.dart';

QuoteNotificationStore get _store => QuoteNotificationStore.instance;

JobEvaluationStore get _evaluations => JobEvaluationStore.instance;

String get _mechanic => QuoteNotificationStore.currentMechanicName;

/// One Urgent job taken from upload to payment, as the two apps drive it.
HelpRequest _payJob(String id, {String client = 'Client'}) {
  AppSession.instance.setRole(AppRole.client, viewerName: client);
  _store.submitRequest(HelpRequest(
    id: id,
    problem: 'Flat tire',
    location: 'Puerto Princesa City',
    urgency: 'Urgent',
    photoPaths: const [],
    createdAt: DateTime.now(),
    clientName: client,
  ));
  _store.mechanicSendQuote(id, mechanicName: _mechanic, price: '₱450', eta: const Duration(hours: 1), rating: 4.8);
  _store.clientAcceptQuote(_store.quotesForRequest(id).first.id);
  AppSession.instance.setRole(AppRole.mechanic, viewerName: _mechanic);
  _store.mechanicCompleteService(id);
  AppSession.instance.setRole(AppRole.client, viewerName: client);
  _store.clientConfirmPayment(id);
  return _store.requestFor(id)!;
}

JobEvaluation _submit(String jobId, int stars, {String client = 'Client', Set<EvaluationTag> tags = const {}}) =>
    _evaluations.submit(
      jobId: jobId,
      clientId: client,
      submission: EvaluationSubmission(rating: stars, tags: tags, feedback: 'Quick and tidy'),
    );

Matcher _refused(EvaluationRefusal reason) =>
    throwsA(isA<EvaluationException>().having((e) => e.reason, 'reason', reason));

void main() {
  setUp(() {
    _store.clear();
    resetPerformanceStores();
    MechanicNotificationStore.instance.clear();
    MechanicAccountStore.instance.enterDemoMode();
  });

  tearDown(resetPerformanceStores);

  group('evaluation required', () {
    test('a paid job opens one evaluation tied to the job, the client and the mechanic', () {
      _payJob('eval-1');

      final evaluation = _evaluations.forJob('eval-1')!;
      expect(evaluation.status, EvaluationStatus.required);
      expect(evaluation.clientId, 'Client');
      expect(evaluation.mechanicId, _mechanic);
      expect(_evaluations.pendingForClient('Client').map((e) => e.jobId), ['eval-1']);
      expect(_evaluations.requireFor(_store.requestFor('eval-1')!, null), isNull,
          reason: 'no quote, nothing opened');
      expect(_evaluations.all, hasLength(1));
    });

    test('an unpaid job has nothing to evaluate', () {
      AppSession.instance.setRole(AppRole.client, viewerName: 'Client');
      expect(
        () => _submit('never-paid', 5),
        _refused(EvaluationRefusal.notEligible),
      );
    });

    test('still pending after a restart', () async {
      _payJob('eval-restart');
      await _evaluations.debugRestart();
      expect(_evaluations.pendingForClient('Client').single.jobId, 'eval-restart');
    });
  });

  group('submitting', () {
    test('once, then locked', () {
      _payJob('eval-once');
      final submitted = _submit('eval-once', 5, tags: {EvaluationTag.professional});
      expect(submitted.status, EvaluationStatus.submitted);
      expect(submitted.rating, 5);
      expect(_evaluations.pendingForClient('Client'), isEmpty);

      expect(() => _submit('eval-once', 1), _refused(EvaluationRefusal.alreadySubmitted));
      expect(_evaluations.forJob('eval-once')!.rating, 5);
    });

    test('only by the client whose job it is, from the Client UI', () {
      _payJob('eval-owner');
      expect(() => _submit('eval-owner', 4, client: 'Someone else'), _refused(EvaluationRefusal.notYours));

      AppSession.instance.setRole(AppRole.mechanic, viewerName: _mechanic);
      expect(() => _submit('eval-owner', 5), _refused(EvaluationRefusal.wrongRole));
    });

    test('a rating outside 1–5 is refused', () {
      _payJob('eval-invalid');
      expect(() => _submit('eval-invalid', 0), _refused(EvaluationRefusal.invalid));
    });

    test('a voided evaluation can no longer be submitted', () {
      _payJob('eval-void');
      _evaluations.voidForJob('eval-void', 'Refunded');
      expect(() => _submit('eval-void', 5), _refused(EvaluationRefusal.noLongerEligible));
    });
  });

  group('job evaluations stay separate from profile reviews', () {
    test('evaluations make the job rating; profile reviews and rank are untouched by them', () {
      _payJob('r1');
      _payJob('r2');
      _submit('r1', 5);
      _submit('r2', 3);

      final rating = _evaluations.ratingFor(_mechanic);
      expect(rating.count, 2);
      expect(rating.average, 4);
      expect(ReviewStore.instance.ratingCountFor(_mechanic), 0, reason: 'a job evaluation is not a profile review');
      expect(MechanicRankStore.instance.standingFor(_mechanic).reviews, 0);
      expect(MechanicRankStore.instance.standingFor(_mechanic).completedJobs, 2);
    });

    test('a pending evaluation is not a rating', () {
      _payJob('pending-only');
      expect(_evaluations.ratingFor(_mechanic).count, 0);
      expect(ReviewStore.instance.reviewsFor(_mechanic), isEmpty);
    });

    test('mechanics see no client and no job', () {
      _payJob('anon');
      _submit('anon', 4, tags: {EvaluationTag.goodCommunication});

      final seen = _evaluations.anonymousForMechanic(_mechanic).single;
      expect(seen.rating, 4);
      expect(seen.id, isNot(contains('anon')), reason: 'no job id to map back to a client');
      // The notification says there is a rating, never whose.
      final rated = MechanicNotificationStore.instance
          .notificationsFor(_mechanic)
          .where((n) => n.kind == MechanicNotificationKind.rated)
          .single;
      expect(rated.clientName, isEmpty);
    });

    test('voiding removes the rating everywhere, keeping the record', () {
      _payJob('fraud');
      _submit('fraud', 5);
      _evaluations.voidForJob('fraud', 'Self-dealing');
      expect(_evaluations.ratingFor(_mechanic).count, 0);
      expect(_evaluations.forJob('fraud')!.voidReason, 'Self-dealing');
      expect(_evaluations.forJob('fraud')!.clientId, 'Client');
    });
  });

  group('performance', () {
    test('completion and on-time rates only show with data behind them', () {
      final before = MechanicPerformanceStore.instance.performanceFor(_mechanic);
      expect(before.completionRate, isNull);
      expect(before.onTimeRate, isNull);
      expect(before.satisfactionRate, isNull);

      final job = _payJob('perf-1');
      MechanicPerformanceStore.instance.recordDropped(job, _mechanic, JobOutcomeKind.cancelledByMechanic);

      final after = MechanicPerformanceStore.instance.performanceFor(_mechanic);
      expect(after.completedJobs, 1);
      expect(after.completionRate, 0.5);
    });
  });

  group('point transactions', () {
    test('every award records base × rank × seasonal = final', () {
      _payJob('tx-1');
      final tx = PointTransactionStore.instance.forMechanic(_mechanic).single;
      expect(tx.sourceId, 'tx-1');
      expect(tx.basePoints, 3);
      expect(tx.rank, MechanicRank.iron);
      expect(tx.leaderboardMultiplier, 1);
      expect(tx.finalPoints, 3);
      expect(tx.seasonId, isNull);
    });
  });

  group('leaderboard', () {
    Season running() {
      final start = DateTime.now().subtract(const Duration(days: 1));
      return Season(
        id: 'season-now',
        name: 'Season 1',
        startsAt: start,
        endsAt: start.add(const Duration(days: 120)),
        status: SeasonStatus.active,
        startedAt: start,
      );
    }

    test('disabled: no Gem and no seasonal multiplier — but the preview still places them', () {
      LeaderboardConfigStore.instance.debugSet(seasons: [running()]);
      _payJob('lb-off-1');

      final leaderboard = LeaderboardStore.instance;
      expect(leaderboard.enabled, isFalse);
      expect(leaderboard.standings().single.mechanicId, _mechanic, reason: 'data keeps being collected');
      expect(leaderboard.gemFor(_mechanic)?.placement, 1);
      expect(leaderboard.badgeFor(_mechanic).gem, isNull);
      expect(leaderboard.multiplierFor(_mechanic).leaderboardMultiplier, 1);

      _payJob('lb-off-2');
      expect(PointTransactionStore.instance.forMechanic(_mechanic).map((t) => t.finalPoints), everyElement(3));
    });

    test('enabled with a running season: the Gem shows in front of the rank and the multiplier applies', () {
      LeaderboardConfigStore.instance.debugSet(
        config: LeaderboardConfig.defaults.copyWith(enabled: true),
        seasons: [running()],
      );
      _payJob('lb-on-1');

      final badge = LeaderboardStore.instance.badgeFor(_mechanic);
      expect(badge.gem?.label, '💎 #1 Gem');
      expect(badge.rank, MechanicRank.iron, reason: 'the rank is kept');

      _payJob('lb-on-2');
      final second = PointTransactionStore.instance.forMechanic(_mechanic).firstWhere((t) => t.sourceId == 'lb-on-2');
      expect(second.leaderboardMultiplier, 1.5);
      expect(second.finalPoints, 4.5);
      expect(second.seasonId, 'season-now');
    });
  });

  group('report a problem', () {
    test('is separate from the evaluation, and one open report per job', () {
      _payJob('problem-1');
      final report = ProblemReportStore.instance.report(
        jobId: 'problem-1',
        clientId: 'Client',
        category: ProblemCategory.payment,
        description: 'Charged more than the quote said.',
      );
      expect(report.mechanicId, _mechanic);
      expect(_evaluations.forJob('problem-1')!.status, EvaluationStatus.required);

      expect(
        () => ProblemReportStore.instance.report(
          jobId: 'problem-1',
          clientId: 'Client',
          category: ProblemCategory.other,
          description: 'Another report on the same job.',
        ),
        throwsA(isA<ProblemReportException>()),
      );
      expect(
        () => ProblemReportStore.instance.report(
          jobId: 'problem-1',
          clientId: 'Not the client',
          category: ProblemCategory.other,
          description: 'Someone else reporting this job.',
        ),
        throwsA(isA<ProblemReportException>()),
      );
    });
  });
}
