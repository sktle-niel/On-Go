import 'package:flutter_test/flutter_test.dart';
import 'package:on_go/data/app_session.dart';
import 'package:on_go/data/quote_store.dart';
import 'package:on_go/services/backend/local_service_request_service.dart';
import 'package:on_go_shared/on_go_shared.dart';

/// `LocalServiceRequestService` — the on-device store behind `ServiceRequestApi`.
///
/// The point of this adapter is that a screen can be written once. So what
/// these pin is the part a screen actually depends on: that a refusal arrives
/// as an `ApiException` with the same `code` the server sends, and that the
/// record read back carries the same fields. If the two sides disagree on
/// either, a screen has to branch on which backend it is talking to, and the
/// adapter has failed at its one job.
void main() {
  late LocalServiceRequestService jobs;

  setUp(() {
    // The store guards by role against AppSession, the way the home screens set
    // it when they mount. Without it every client call is a StateError, which
    // the adapter would rightly report as forbidden.
    AppSession.instance.setRole(AppRole.client, viewerName: 'Client');
    // The store is a singleton; each test books into a clean one by cancelling
    // whatever the last one left behind.
    final store = QuoteNotificationStore.instance;
    for (final request in [...store.myPendingRequests, ...store.myActiveJobs]) {
      store.clientDeleteRequest(request.id);
    }
    jobs = LocalServiceRequestService();
  });

  const booking = NewServiceRequest(
    problem: 'Flat tyre',
    location: 'Katipunan Ave, Quezon City',
    urgency: JobUrgency.urgent,
    point: GeoPoint(14.6349, 121.0730),
  );

  group('booking', () {
    test('a booking comes back as a pending request with the urgency\'s fee', () async {
      final booked = await jobs.bookRequest(booking);

      expect(booked.status, ServiceRequestStatus.pending);
      expect(booked.urgency, JobUrgency.urgent);
      // The same table the server applies: 0 / 50 / 100.
      expect(booked.surcharge, 50);
      expect(booked.latitude, 14.6349);
      expect(booked.mechanicId, isNull);
    });

    test('the fee follows each urgency', () async {
      expect((await jobs.bookRequest(const NewServiceRequest(
        problem: 'x',
        location: 'y',
        urgency: JobUrgency.normal,
      ))).surcharge, 0);

      final normal = (await jobs.listMyRequests()).first;
      await jobs.cancelRequest(normal.id);

      expect((await jobs.bookRequest(const NewServiceRequest(
        problem: 'x',
        location: 'y',
        urgency: JobUrgency.emergency,
      ))).surcharge, 100);
    });

    test('a second live booking is a conflict, the same as the server\'s', () async {
      await jobs.bookRequest(booking);

      await expectLater(
        jobs.bookRequest(booking),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiErrorCodes.conflict)),
      );
    });

    test('a booking can be found by id, and anything else reads as null', () async {
      final booked = await jobs.bookRequest(booking);

      expect((await jobs.findRequest(booked.id))?.id, booked.id);
      // Not there is null, never an exception — the same as the API client,
      // which turns the server's 404 into null for exactly this reason.
      expect(await jobs.findRequest('no-such-job'), isNull);
    });

    test('my jobs list the booking; the open pool is the mechanic\'s view', () async {
      final booked = await jobs.bookRequest(booking);

      expect((await jobs.listMyRequests()).map((r) => r.id), contains(booked.id));
      expect((await jobs.listOpenRequests()).map((r) => r.id), contains(booked.id));
      // The urgency filter is the same parameter the API sends as a query.
      expect(await jobs.listOpenRequests(urgency: JobUrgency.normal), isEmpty);
      expect((await jobs.listOpenRequests(urgency: JobUrgency.urgent)).map((r) => r.id),
          contains(booked.id));
    });
  });

  group('refusals carry the server\'s codes', () {
    test('a job that is not there is not_found, not a crash', () async {
      await expectLater(
        jobs.cancelRequest('no-such-job'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiErrorCodes.notFound)),
      );
      await expectLater(
        jobs.advanceJob('no-such-job', JobProgressStep.arrived),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiErrorCodes.notFound)),
      );
    });

    test('paying a job whose service is not finished is a conflict', () async {
      final booked = await jobs.bookRequest(booking);

      await expectLater(
        jobs.payForJob(booked.id),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiErrorCodes.conflict)),
      );
    });

    test('a progress step out of order is refused, as the server refuses it', () async {
      final booked = await jobs.bookRequest(booking);

      // Work before arrival, and completing before work: both gated.
      await expectLater(
        jobs.advanceJob(booked.id, JobProgressStep.startWork),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiErrorCodes.conflict)),
      );
      await expectLater(
        jobs.advanceJob(booked.id, JobProgressStep.completeService),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiErrorCodes.conflict)),
      );
    });

    test('an ETA past the completion window is refused with the store\'s own words', () async {
      final booked = await jobs.bookRequest(booking);

      try {
        // An Urgent job allows three days; a week is not a promise it can keep.
        await jobs.submitQuote(booked.id, const QuoteSubmission(price: 500, etaMinutes: 60 * 24 * 7));
        fail('the completion window should have refused this');
      } on ApiException catch (error) {
        expect(error.code, ApiErrorCodes.badRequest);
        // The message names the urgency and the window, so a mechanic can act
        // on it rather than guess.
        expect(error.message, contains('Urgent'));
      }
    });

    test('a quote that is not there is not_found', () async {
      final booked = await jobs.bookRequest(booking);

      await expectLater(
        jobs.acceptQuote(booked.id, 'no-such-quote'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiErrorCodes.notFound)),
      );
      await expectLater(
        jobs.rejectQuote(booked.id, 'no-such-quote'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiErrorCodes.notFound)),
      );
      await expectLater(
        jobs.withdrawQuote(booked.id),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiErrorCodes.notFound)),
      );
    });
  });

  group("the store's role guard", () {
    test('a caller in the wrong shell is forbidden, as the server would answer', () async {
      final booked = await jobs.bookRequest(booking);
      // The mechanic shell cannot call a client's cancel. On the server this is
      // a 403; the store throws a StateError, and the adapter's job is to make
      // those the same thing to a screen.
      AppSession.instance.setRole(AppRole.mechanic, viewerName: 'Mang Kanor');

      await expectLater(
        jobs.cancelRequest(booked.id),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', ApiErrorCodes.forbidden)
            .having((e) => e.kind, 'kind', ApiErrorKind.forbidden)),
      );

      AppSession.instance.setRole(AppRole.client, viewerName: 'Client');
    });
  });

  group('cancelling', () {
    test('a pending job cancels, and the answer says so even though the record is gone', () async {
      final booked = await jobs.bookRequest(booking);

      final cancelled = await jobs.cancelRequest(booked.id);

      // The store has no cancelled state — the record leaves — so the adapter
      // answers the job as it was, marked cancelled, rather than nothing.
      expect(cancelled.status, ServiceRequestStatus.cancelled);
      expect(cancelled.id, booked.id);
      expect(await jobs.findRequest(booked.id), isNull);
      // And the client can book again.
      await jobs.bookRequest(booking);
    });
  });

  group('live', () {
    test('a booking reaches a listener on watchRequests', () async {
      final seen = <List<String>>[];
      final watch = jobs.watchRequests().listen((request) => seen.add([request.id]));
      await Future<void>.delayed(Duration.zero);

      final booked = await jobs.bookRequest(booking);
      // The store notifies synchronously; the adapter reads back on the next
      // microtask, so give it one.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(seen.expand((ids) => ids), contains(booked.id));
      await watch.cancel();
    });
  });
}
