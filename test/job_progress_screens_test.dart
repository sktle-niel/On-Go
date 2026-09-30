import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_go/data/quote_store.dart';
import 'package:on_go/screens/auth/client_ui/active/active_request_screen.dart';
import 'package:on_go/screens/auth/mechanic_ui/jobs/mechanic_active_job_screen.dart';
import 'package:on_go/services/backend/mobile_backend.dart';

import 'performance_test_support.dart';
import 'responsive_layout_test.dart' show app;
import 'service_request_test_support.dart';

/// A matched job as each side follows it, through `MobileBackend.serviceRequests`
/// against a scripted backend that answers the way the server does. The
/// mechanic's steps are sent to the backend and the screen shows what it
/// answered; the client's screen follows the same record. The phone's own job
/// store stays empty throughout, so nothing on screen can have come from it.

const _phone = Size(390, 844);

void main() {
  late ScriptedServiceRequests jobs;

  setUp(() {
    QuoteNotificationStore.instance.clear();
    resetPerformanceStores();
    jobs = ScriptedServiceRequests();
    MobileBackend.configure(usesApi: true, serviceRequests: jobs);
  });

  tearDown(() async {
    MobileBackend.debugReset();
    await jobs.close();
    resetPerformanceStores();
  });

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(_phone, screen));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Taps the button labelled [label]. A step's name is also a line in the
  /// status list, so the text alone is not enough to find it.
  Future<void> tap(WidgetTester tester, String label) async {
    final target = find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// A Normal job matched a few minutes ago, with no coordinates, so arrival
  /// is confirmed by hand rather than detected from location.
  void matchedJob({bool arrived = false, ServiceRequestStatus status = ServiceRequestStatus.matched}) {
    final now = DateTime.now().toUtc();
    jobs.mine = [
      scriptedRequest(
        id: 'job-1',
        urgency: JobUrgency.normal,
        status: status,
        surcharge: 0,
        matchedAt: now.subtract(const Duration(minutes: 5)),
        expectedArrivalAt: now.add(const Duration(minutes: 25)),
        mechanicName: 'Mike Sample',
        arrived: arrived,
        enRoute: arrived,
        navigating: arrived,
      ),
    ];
    jobs.quotes = {
      'job-1': [scriptedQuote('accepted', 'job-1', accepted: true)],
    };
  }

  group("the mechanic's active job", () {
    testWidgets('each step goes to the backend, in order, and the screen follows its answers', (tester) async {
      matchedJob();
      await pump(tester, const MechanicActiveJobScreen(requestId: 'job-1'));

      expect(find.text('Carla Sample'), findsOneWidget);
      expect(find.text('₱500'), findsOneWidget, reason: "the accepted quote's price");

      await tap(tester, 'Navigate');
      // No coordinates on the job, so there is nothing to detect arrival from.
      await tap(tester, 'Confirm Arrival');
      await tap(tester, 'Start Work');
      await tap(tester, 'Service Complete');

      expect(jobs.advanced, [
        JobProgressStep.navigating,
        // Arriving reports En Route first when the trip never registered one.
        JobProgressStep.enRoute,
        JobProgressStep.arrived,
        JobProgressStep.startWork,
        JobProgressStep.completeService,
      ]);
      expect(find.text('Waiting for Client Payment'), findsOneWidget);
      expect(find.text('Have the client scan this to pay ₱500'), findsOneWidget);
    });

    testWidgets("a refused step is told in the backend's words, and nothing moves", (tester) async {
      matchedJob(arrived: true);
      jobs.advanceFails = const ApiException(
        ApiErrorKind.rejected,
        'This job is no longer matched to you.',
        code: ApiErrorCodes.conflict,
      );
      await pump(tester, const MechanicActiveJobScreen(requestId: 'job-1'));

      await tap(tester, 'Start Work');

      expect(find.text('This job is no longer matched to you.'), findsOneWidget);
      expect(find.text('Start Work'), findsOneWidget, reason: 'the job is as the backend left it');
    });

    testWidgets("an Emergency's agreed price is recorded on the backend, then its code is shown", (tester) async {
      jobs.mine = [
        scriptedRequest(
          id: 'emergency-1',
          urgency: JobUrgency.emergency,
          status: ServiceRequestStatus.matched,
          surcharge: 100,
          matchedAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
          mechanicName: 'Mike Sample',
          navigating: true,
          enRoute: true,
          arrived: true,
          workStarted: true,
          serviceCompleted: true,
        ),
      ];
      // An Emergency's accept record: accepted, with no real price.
      jobs.quotes = {
        'emergency-1': [scriptedQuote('accept', 'emergency-1', accepted: true, price: 0, etaMinutes: 15)],
      };
      await pump(tester, const MechanicActiveJobScreen(requestId: 'emergency-1'));

      await tap(tester, 'Set Payment Amount');
      await tester.enterText(find.byType(TextField), '750');
      await tap(tester, 'Confirm');

      expect(jobs.agreedAmounts, [750]);
      expect(find.text('Agreed price: ₱750'), findsOneWidget);
    });

    testWidgets("a job that is not this mechanic's any more says so", (tester) async {
      await pump(tester, const MechanicActiveJobScreen(requestId: 'gone'));

      expect(find.text('This job is no longer active.'), findsOneWidget);
    });
  });

  group("the client's job details", () {
    testWidgets('a server job shows its mechanic and the countdown to the promised arrival, and follows each step',
        (tester) async {
      matchedJob();
      await pump(tester, const ActiveRequestScreen(requestId: 'job-1'));

      expect(find.text('Mike Sample'), findsOneWidget);
      expect(find.text('Mechanic is preparing'), findsOneWidget);
      expect(find.textContaining('Mike Sample should arrive in'), findsOneWidget);
      // A Normal job has no completion window: the promise is the arrival.
      expect(find.text("Completed within the mechanic's quoted ETA"), findsOneWidget);

      final arrived = scriptedRequest(
        id: 'job-1',
        urgency: JobUrgency.normal,
        status: ServiceRequestStatus.matched,
        surcharge: 0,
        matchedAt: jobs.mine.single.matchedAt,
        expectedArrivalAt: jobs.mine.single.expectedArrivalAt,
        mechanicName: 'Mike Sample',
        navigating: true,
        enRoute: true,
        arrived: true,
      );
      jobs.publish(arrived);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Mechanic has arrived'), findsOneWidget);
      expect(find.textContaining('should arrive in'), findsNothing, reason: 'arriving stops the countdown');
    });

    testWidgets('a paid job shows its receipt from the backend', (tester) async {
      jobs.mine = [
        scriptedRequest(
          id: 'paid',
          status: ServiceRequestStatus.completed,
          matchedAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
          deadlineAt: DateTime.now().toUtc().add(const Duration(days: 2)),
          mechanicName: 'Mike Sample',
          navigating: true,
          enRoute: true,
          arrived: true,
          workStarted: true,
          serviceCompleted: true,
          paymentCompleted: true,
          amountPaid: 500,
          platformFeeCharged: 50,
        ),
      ];
      jobs.quotes = {
        'paid': [scriptedQuote('accepted', 'paid', accepted: true)],
      };
      await pump(tester, const ActiveRequestScreen(requestId: 'paid'));

      expect(find.text('Payment complete — ₱500 sent to Mike Sample.'), findsOneWidget);
      expect(find.textContaining('₱50 Urgent additional charge'), findsOneWidget);
    });

    testWidgets("paying a server job says it isn't connected yet, before any scanning", (tester) async {
      jobs.mine = [
        scriptedRequest(
          id: 'finished',
          status: ServiceRequestStatus.matched,
          matchedAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
          mechanicName: 'Mike Sample',
          navigating: true,
          enRoute: true,
          arrived: true,
          workStarted: true,
          serviceCompleted: true,
        ),
      ];
      jobs.quotes = {
        'finished': [scriptedQuote('accepted', 'finished', accepted: true)],
      };
      await pump(tester, const ActiveRequestScreen(requestId: 'finished'));

      await tap(tester, 'Send Payment');

      expect(find.text("Paying for this job in the app isn't connected yet."), findsOneWidget);
      expect(find.text('Scan QR Code'), findsNothing);
    });

    testWidgets('a job back in the pool has nothing to follow', (tester) async {
      matchedJob(status: ServiceRequestStatus.pending);
      await pump(tester, const ActiveRequestScreen(requestId: 'job-1'));

      expect(find.text('This job is no longer active.'), findsOneWidget);
    });

    testWidgets('a failed read says so, and trying again reads the job', (tester) async {
      matchedJob();
      jobs.findFails = const ApiException(ApiErrorKind.unreachable, "Couldn't reach On Go.");
      await pump(tester, const ActiveRequestScreen(requestId: 'job-1'));

      expect(find.text("Couldn't load this job"), findsOneWidget);

      jobs.findFails = null;
      await tap(tester, 'Try again');

      expect(find.text('Mike Sample'), findsOneWidget);
    });
  });
}
