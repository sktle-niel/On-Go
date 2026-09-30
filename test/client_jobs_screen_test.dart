import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_go/data/quote_store.dart';
import 'package:on_go/screens/auth/client_ui/jobs/client_jobs_screen.dart';
import 'package:on_go/services/backend/mobile_backend.dart';

import 'responsive_layout_test.dart' show app;
import 'service_request_test_support.dart';

/// The client's Jobs tab, driven through `MobileBackend.serviceRequests` by a
/// scripted backend that answers the way the server does. What these pin is
/// that the tab shows the backend's jobs and sends the client's changes to it,
/// rather than reading the phone's own job store.

const _phone = Size(390, 844);

void main() {
  late ScriptedServiceRequests jobs;

  setUp(() {
    // The phone's own job store stays empty: anything on screen came from the
    // scripted backend.
    QuoteNotificationStore.instance.clear();
    jobs = ScriptedServiceRequests();
    MobileBackend.configure(usesApi: true, serviceRequests: jobs);
  });

  tearDown(() async {
    MobileBackend.debugReset();
    await jobs.close();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(_phone, const ClientJobsScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets("a server job waits for quotes on the first tab, with the backend's figures", (tester) async {
    jobs.mine = [
      scriptedRequest(id: '04f60f8f-pending', description: 'Rear left'),
      // Closed jobs are history, not this tab's.
      scriptedRequest(id: 'paid', problem: 'Battery', status: ServiceRequestStatus.completed),
      scriptedRequest(id: 'called-off', problem: 'Chain', status: ServiceRequestStatus.cancelled),
    ];
    jobs.quotes = {
      '04f60f8f-pending': [
        scriptedQuote('q1', '04f60f8f-pending'),
        scriptedQuote('q2', '04f60f8f-pending'),
        // Taken off the table: not counted.
        scriptedQuote('q3', '04f60f8f-pending', withdrawnAt: DateTime.now().toUtc()),
      ],
    };

    await pump(tester);

    expect(find.text('2 QUOTES IN'), findsOneWidget);
    expect(find.text('Flat tire'), findsOneWidget);
    // The server keeps the details apart from the problem; the card shows both.
    expect(find.text('Rear left'), findsOneWidget);
    expect(find.text('PRIORITY FEE ₱50'), findsOneWidget);
    expect(find.text('Battery'), findsNothing);
    expect(find.text('Chain'), findsNothing);
  });

  testWidgets("a server job's new quotes are counted by their ids, and ones already shown are not",
      (tester) async {
    jobs.mine = [scriptedRequest(id: 'pending')];
    jobs.quotes = {
      'pending': [scriptedQuote('seen', 'pending'), scriptedQuote('fresh', 'pending')],
    };
    // The quotes screen marks what it put on screen, by the backend's ids.
    QuoteNotificationStore.instance.markQuotesSeen(['seen']);

    await pump(tester);

    expect(find.text('View quotes (1 new)'), findsOneWidget);
  });

  testWidgets('a matched job shows its mechanic and price, and explains the ETA lock before any refusal',
      (tester) async {
    final now = DateTime.now().toUtc();
    jobs.mine = [
      scriptedRequest(
        id: 'matched',
        urgency: JobUrgency.normal,
        status: ServiceRequestStatus.matched,
        surcharge: 0,
        matchedAt: now.subtract(const Duration(minutes: 5)),
        expectedArrivalAt: now.add(const Duration(minutes: 25)),
        mechanicName: 'Mike Sample',
      ),
    ];
    jobs.quotes = {
      'matched': [scriptedQuote('accepted', 'matched', accepted: true)],
    };

    await pump(tester);
    await tester.tap(find.text('Booked'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Mike Sample'), findsOneWidget);
    expect(find.text('ETA 30 mins  ·  4.5 ★'), findsOneWidget);
    expect(find.text('₱500'), findsOneWidget);
    expect(find.textContaining('Cancelling unlocks in'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text("You can't cancel yet"), findsOneWidget);
    expect(jobs.cancelled, isEmpty, reason: 'nothing is sent that the backend would refuse');
    expect(jobs.reopened, isEmpty);
  });

  testWidgets('cancelling a booking goes to the backend, and the list is read again', (tester) async {
    jobs.mine = [scriptedRequest(id: 'pending')];

    await pump(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Cancel booking'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(jobs.cancelled, ['pending']);
    expect(find.text('Booking cancelled.'), findsOneWidget);
    expect(find.text('Nothing booked yet'), findsOneWidget);
  });

  testWidgets("a refused cancel is told in the backend's own words", (tester) async {
    jobs.mine = [scriptedRequest(id: 'pending')];
    jobs.cancelWith = (_) => Future.error(const ApiException(
          ApiErrorKind.rejected,
          'A mechanic already took this job.',
          code: ApiErrorCodes.conflict,
        ));

    await pump(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Cancel booking'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('A mechanic already took this job.'), findsOneWidget);
    expect(find.text('Flat tire'), findsOneWidget, reason: 'the job is still there');
  });

  testWidgets('an event from the backend repaints the list', (tester) async {
    await pump(tester);
    expect(find.text('Nothing booked yet'), findsOneWidget);

    final booked = scriptedRequest(id: 'new-booking', problem: 'Battery');
    jobs.mine = [booked];
    jobs.requestEvents.add(booked);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Battery'), findsOneWidget);
  });

  testWidgets('a failed read says so, and trying again reads the list', (tester) async {
    jobs.listFails = const ApiException(ApiErrorKind.unreachable, "Couldn't reach On Go.");

    await pump(tester);
    expect(find.text("Couldn't load your jobs"), findsOneWidget);
    expect(find.text("Couldn't reach On Go."), findsOneWidget);

    jobs.listFails = null;
    jobs.mine = [scriptedRequest(id: 'pending')];
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Flat tire'), findsOneWidget);
  });

  testWidgets('turning to the tab reads the jobs again', (tester) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The shell keeps the tab alive and flips `visible`, as this does.
    var visible = false;
    late StateSetter setShell;
    await tester.pumpWidget(app(
      _phone,
      StatefulBuilder(builder: (context, setState) {
        setShell = setState;
        return ClientJobsScreen(visible: visible);
      }),
    ));
    await tester.pump();
    final before = jobs.reads;

    setShell(() => visible = true);
    await tester.pump();

    expect(jobs.reads, before + 1);
  });
}
