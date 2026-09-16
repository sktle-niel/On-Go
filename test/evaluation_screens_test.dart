import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_go/data/app_session.dart';
import 'package:on_go/data/job_evaluation_store.dart';
import 'package:on_go/data/mechanic_account_store.dart';
import 'package:on_go/data/mechanic_notification_store.dart';
import 'package:on_go/data/quote_store.dart';
import 'package:on_go/screens/auth/client_ui/history/service_history_screen.dart';
import 'package:on_go/screens/auth/client_ui/profile/mechanic_profile_view_screen.dart';
import 'package:on_go/widgets/evaluation_widgets.dart';
import 'package:on_go/widgets/leaderboard_widgets.dart';
import 'package:on_go_shared/on_go_shared.dart';

import 'performance_test_support.dart';
import 'responsive_layout_test.dart' show app;

const Size _phone = Size(390, 844);

QuoteNotificationStore get _store => QuoteNotificationStore.instance;

String get _mechanic => QuoteNotificationStore.currentMechanicName;

void _payJob(String id) {
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
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app(_phone, child));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    _store.clear();
    resetPerformanceStores();
    MechanicNotificationStore.instance.clear();
    MechanicAccountStore.instance.enterDemoMode();
  });

  tearDown(resetPerformanceStores);

  testWidgets('the banner shows while an evaluation is pending, and never blocks', (tester) async {
    await _pump(tester, const PendingEvaluationBanner());
    expect(find.text('Evaluation Required'), findsNothing);

    _payJob('banner-1');
    await tester.pump();
    expect(find.text('Evaluation Required'), findsOneWidget);

    JobEvaluationStore.instance.submit(
      jobId: 'banner-1',
      clientId: 'Client',
      submission: const EvaluationSubmission(rating: 5),
    );
    await tester.pump();
    expect(find.text('Evaluation Required'), findsNothing);
  });

  testWidgets('history marks a job Evaluation Required, then Evaluated', (tester) async {
    _payJob('history-1');
    await _pump(tester, const ServiceHistoryScreen());
    expect(find.text('⚠ Evaluation Required'), findsOneWidget);

    JobEvaluationStore.instance.submit(
      jobId: 'history-1',
      clientId: 'Client',
      submission: const EvaluationSubmission(rating: 4),
    );
    await tester.pump();
    expect(find.text('✓ Evaluated'), findsOneWidget);
    expect(find.text('⚠ Evaluation Required'), findsNothing);
  });

  testWidgets('the evaluation sheet submits once', (tester) async {
    _payJob('sheet-1');
    await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => evaluateJob(context, 'sheet-1'),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('How was your service?'), findsOneWidget);

    tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.star_border).last).onPressed!();
    await tester.pump();
    final submit = find.widgetWithText(ElevatedButton, 'Submit evaluation');
    tester.widget<ElevatedButton>(submit).onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final evaluation = JobEvaluationStore.instance.forJob('sheet-1')!;
    expect(evaluation.status, EvaluationStatus.submitted);
    expect(evaluation.rating, 5);
  });

  testWidgets("a mechanic's profile shows measured performance, not a made-up Experience", (tester) async {
    _payJob('profile-1');
    await _pump(tester, MechanicProfileViewScreen(name: _mechanic));
    expect(find.text('Performance'), findsOneWidget);
    expect(find.text('9yr'), findsNothing);
    expect(find.text('Experience'), findsNothing);
    // The profile review and the job evaluation are two separate actions.
    expect(find.text('Write a review'), findsOneWidget);
    expect(find.text('Evaluate your job'), findsOneWidget);
  });

  testWidgets('the leaderboard stays hidden until an admin turns it on', (tester) async {
    await _pump(tester, SeasonLeaderboardView(onOpenMechanic: (_) {}));
    expect(find.text("The leaderboard isn't active yet"), findsOneWidget);
  });
}
