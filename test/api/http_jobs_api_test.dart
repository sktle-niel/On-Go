import 'package:flutter_test/flutter_test.dart';
import 'package:on_go_api/on_go_api.dart';
import 'package:on_go_shared/on_go_shared.dart';

import 'api_test_support.dart';

/// `HttpServiceRequestApi` against a stand-in server.
///
/// What these pin is the wire: the path each call goes to, what it puts in the
/// body or the query, and that the answer is read back as the server's record
/// rather than anything this side computed. The rules themselves — the priority
/// fee, the ETA cap, the cancel lock, the money — are the server's, and are
/// tested there.
void main() {
  const requestId = '68d136b9-0000-4000-8000-0000000000aa';
  const quoteId = '68d136b9-0000-4000-8000-0000000000bb';

  /// A booked Normal job as the server answers it.
  Map<String, dynamic> requestJson({
    String status = 'pending',
    double surcharge = 0,
    String urgency = 'Normal',
    bool serviceCompleted = false,
    bool paymentCompleted = false,
    Map<String, Object?> extra = const {},
  }) =>
      {
        'id': requestId,
        'clientId': '68d136b9-0000-4000-8000-000000000001',
        'clientName': 'Juan Dela Cruz',
        'problem': 'Flat tyre',
        'description': 'Rear left, no spare.',
        'location': 'Katipunan Ave, Quezon City',
        'urgency': urgency,
        'surcharge': surcharge,
        'latitude': 14.6349,
        'longitude': 121.0730,
        'status': status,
        'createdAt': '2026-09-16T09:00:00.000Z',
        'navigating': false,
        'enRoute': false,
        'arrived': false,
        'workStarted': false,
        'serviceCompleted': serviceCompleted,
        'paymentCompleted': paymentCompleted,
        ...extra,
      };

  Map<String, dynamic> quoteJson({bool accepted = false}) => {
        'id': quoteId,
        'requestId': requestId,
        'mechanicId': '68d136b9-0000-4000-8000-000000000002',
        'mechanicName': 'Mang Kanor',
        'price': 850.0,
        'etaMinutes': 25,
        'rating': 4.5,
        'accepted': accepted,
        'createdAt': '2026-09-16T09:05:00.000Z',
      };

  /// Signs in so the client has an access token to send.
  Future<OnGoApi> signedIn(FakeApiServer server) async {
    server.on('POST', '/api/v1/auth/sign-in', (_) => apiJson(200, sessionBody()));
    final api = testApi(server);
    await api.auth.signIn(const SignInRequest(
      identifier: 'juan@example.com',
      password: 'correct horse',
      surface: AppSurface.mobile,
    ));
    return api;
  }

  group('booking and reading', () {
    test('booking posts the new request and reads back the server record', () async {
      final server = FakeApiServer();
      server.on('POST', '/api/v1/service-requests',
          (_) => apiJson(201, requestJson(urgency: 'Urgent', surcharge: 50)));
      final api = await signedIn(server);

      final booked = await api.serviceRequests.bookRequest(const NewServiceRequest(
        problem: 'Flat tyre',
        description: 'Rear left, no spare.',
        location: 'Katipunan Ave, Quezon City',
        urgency: JobUrgency.urgent,
        point: GeoPoint(14.6349, 121.0730),
      ));

      expect(booked.id, requestId);
      expect(booked.status, ServiceRequestStatus.pending);
      // The fee is the server's, read off the answer — never computed here.
      expect(booked.surcharge, 50);

      final sent = bodyOf(server.sentTo('POST', '/api/v1/service-requests').single);
      expect(sent['urgency'], 'Urgent');
      expect(sent['problem'], 'Flat tyre');
      // The client is the token holder; the body never names one.
      expect(sent.containsKey('clientId'), isFalse);
    });

    test('the open pool and my jobs are one route told apart by scope', () async {
      final server = FakeApiServer();
      server.on('GET', '/api/v1/service-requests', (_) => apiJson(200, [requestJson()]));
      final api = await signedIn(server);

      await api.serviceRequests.listOpenRequests(urgency: JobUrgency.emergency);
      await api.serviceRequests.listMyRequests();

      final sent = server.sentTo('GET', '/api/v1/service-requests');
      expect(sent.first.url.queryParameters, {'scope': 'open', 'urgency': 'Emergency'});
      // No urgency given: the parameter is left off rather than sent empty.
      expect(sent.last.url.queryParameters, {'scope': 'mine'});
    });

    test('a client refused the open pool gets the server refusal, not an empty list', () async {
      final server = FakeApiServer();
      server.on('GET', '/api/v1/service-requests',
          (_) => apiError(403, 'forbidden', 'You do not have access to this resource.'));
      final api = await signedIn(server);

      await expectLater(
        api.serviceRequests.listOpenRequests(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiErrorCodes.forbidden)),
      );
    });

    test('a job that is not the caller\'s reads as null, not as an error', () async {
      final server = FakeApiServer();
      server.on('GET', '/api/v1/service-requests/$requestId',
          (_) => apiError(404, 'not_found', 'Request not found.'));
      final api = await signedIn(server);

      expect(await api.serviceRequests.findRequest(requestId), isNull);
    });

    test('a failure that is not 404 still surfaces', () async {
      final server = FakeApiServer();
      server.on('GET', '/api/v1/service-requests/$requestId',
          (_) => apiError(500, 'internal_error', 'Something went wrong. Please try again.'));
      final api = await signedIn(server);

      await expectLater(api.serviceRequests.findRequest(requestId), throwsA(isA<ApiException>()));
    });
  });

  group('quotes and the match', () {
    test('a quote is submitted with its price and ETA', () async {
      final server = FakeApiServer();
      server.on('POST', '/api/v1/service-requests/$requestId/quotes', (_) => apiJson(201, quoteJson()));
      final api = await signedIn(server);

      final quote = await api.serviceRequests
          .submitQuote(requestId, const QuoteSubmission(price: 850, etaMinutes: 25));

      expect(quote.price, 850);
      expect(quote.etaMinutes, 25);
      expect(bodyOf(server.sentTo('POST', '/api/v1/service-requests/$requestId/quotes').single),
          {'price': 850.0, 'etaMinutes': 25});
    });

    test('an ETA past the completion window is refused by the server', () async {
      final server = FakeApiServer();
      server.on(
        'POST',
        '/api/v1/service-requests/$requestId/quotes',
        (_) => apiError(400, 'bad_request', 'An Emergency must be completed within its window.'),
      );
      final api = await signedIn(server);

      await expectLater(
        api.serviceRequests.submitQuote(requestId, const QuoteSubmission(price: 500, etaMinutes: 900)),
        throwsA(isA<ApiException>()),
      );
    });

    test('withdraw and reject go to their own routes', () async {
      final server = FakeApiServer();
      server.on('POST', '/api/v1/service-requests/$requestId/quotes/withdraw',
          (_) => apiJson(200, quoteJson()));
      server.on('POST', '/api/v1/service-requests/$requestId/quotes/$quoteId/reject',
          (_) => apiJson(200, quoteJson()));
      final api = await signedIn(server);

      await api.serviceRequests.withdrawQuote(requestId);
      await api.serviceRequests.rejectQuote(requestId, quoteId);

      expect(server.count('POST', '/api/v1/service-requests/$requestId/quotes/withdraw'), 1);
      expect(server.count('POST', '/api/v1/service-requests/$requestId/quotes/$quoteId/reject'), 1);
    });

    test('accepting a quote matches the job and stamps the deadline server-side', () async {
      final server = FakeApiServer();
      server.on(
        'POST',
        '/api/v1/service-requests/$requestId/quotes/$quoteId/accept',
        (_) => apiJson(
            200,
            requestJson(status: 'matched', urgency: 'Urgent', surcharge: 50, extra: {
              'matchedAt': '2026-09-16T09:10:00.000Z',
              'deadlineAt': '2026-09-19T09:10:00.000Z',
              'expectedArrivalAt': '2026-09-16T09:35:00.000Z',
              'mechanicId': '68d136b9-0000-4000-8000-000000000002',
              'mechanicName': 'Mang Kanor',
            })),
      );
      final api = await signedIn(server);

      final matched = await api.serviceRequests.acceptQuote(requestId, quoteId);

      expect(matched.status, ServiceRequestStatus.matched);
      expect(matched.mechanicName, 'Mang Kanor');
      // Both clocks come from the server, so the countdowns read its time.
      expect(matched.deadlineAt, isNotNull);
      expect(matched.expectedArrivalAt, isNotNull);
    });

    test('the accept that loses a race is a conflict, not a second match', () async {
      final server = FakeApiServer();
      server.on(
        'POST',
        '/api/v1/service-requests/$requestId/quotes/$quoteId/accept',
        (_) => apiError(409, 'conflict', 'This request has already been matched or closed.'),
      );
      final api = await signedIn(server);

      await expectLater(
        api.serviceRequests.acceptQuote(requestId, quoteId),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiErrorCodes.conflict)),
      );
    });

    test('a mechanic takes an emergency with an ETA', () async {
      final server = FakeApiServer();
      server.on('POST', '/api/v1/service-requests/$requestId/accept',
          (_) => apiJson(200, requestJson(status: 'matched', urgency: 'Emergency', surcharge: 100)));
      final api = await signedIn(server);

      await api.serviceRequests.acceptEmergency(requestId, etaMinutes: 40);

      expect(bodyOf(server.sentTo('POST', '/api/v1/service-requests/$requestId/accept').single),
          {'etaMinutes': 40});
    });
  });

  group('progress and payment', () {
    test('each progress step posts to its own path segment', () async {
      final server = FakeApiServer();
      for (final step in JobProgressStep.values) {
        server.on('POST', '/api/v1/service-requests/$requestId/${step.pathSegment}',
            (_) => apiJson(200, requestJson(status: 'matched')));
      }
      final api = await signedIn(server);

      for (final step in JobProgressStep.values) {
        await api.serviceRequests.advanceJob(requestId, step);
      }

      expect(server.count('POST', '/api/v1/service-requests/$requestId/navigating'), 1);
      expect(server.count('POST', '/api/v1/service-requests/$requestId/en-route'), 1);
      expect(server.count('POST', '/api/v1/service-requests/$requestId/arrived'), 1);
      expect(server.count('POST', '/api/v1/service-requests/$requestId/start-work'), 1);
      expect(server.count('POST', '/api/v1/service-requests/$requestId/complete-service'), 1);
    });

    test('a step out of order is the server\'s refusal to make', () async {
      final server = FakeApiServer();
      server.on('POST', '/api/v1/service-requests/$requestId/start-work',
          (_) => apiError(409, 'conflict', 'The mechanic has not arrived yet.'));
      final api = await signedIn(server);

      await expectLater(
        api.serviceRequests.advanceJob(requestId, JobProgressStep.startWork),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiErrorCodes.conflict)),
      );
    });

    test('paying closes the job and returns the figures the server settled', () async {
      final server = FakeApiServer();
      server.on(
        'POST',
        '/api/v1/service-requests/$requestId/pay',
        (_) => apiJson(
            200,
            requestJson(
              status: 'completed',
              urgency: 'Urgent',
              surcharge: 50,
              serviceCompleted: true,
              paymentCompleted: true,
              extra: {
                'completedAt': '2026-09-16T11:00:00.000Z',
                'paymentCompletedAt': '2026-09-16T11:00:00.000Z',
                'amountPaid': 850.0,
                'platformFeeCharged': 50.0,
                'feePaidWithPoints': 50.0,
                'pointsAwarded': 85.0,
                'clientPointsAwarded': 10.0,
              },
            )),
      );
      final api = await signedIn(server);

      final paid = await api.serviceRequests.payForJob(
        requestId,
        payment: const JobPaymentRequest(expectedAmount: 850, payFeeWithPoints: true),
      );

      expect(paid.status, ServiceRequestStatus.completed);
      expect(paid.paymentCompleted, isTrue);
      // Every figure is read off the answer; none is worked out on this side.
      expect(paid.amountPaid, 850);
      expect(paid.platformFeeCharged, 50);
      expect(paid.feePaidWithPoints, 50);
      expect(paid.pointsAwarded, 85);
      expect(paid.clientPointsAwarded, 10);

      final sent = bodyOf(server.sentTo('POST', '/api/v1/service-requests/$requestId/pay').single);
      expect(sent['expectedAmount'], 850);
      expect(sent['payFeeWithPoints'], true);
    });

    test('a price that changed under the client is refused, not charged', () async {
      final server = FakeApiServer();
      server.on('POST', '/api/v1/service-requests/$requestId/pay',
          (_) => apiError(409, 'conflict', 'The amount to pay has changed. Review it and pay again.'));
      final api = await signedIn(server);

      await expectLater(
        api.serviceRequests.payForJob(requestId, payment: const JobPaymentRequest(expectedAmount: 850)),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiErrorCodes.conflict)),
      );
    });

    test('an Emergency\'s agreed amount is a PUT', () async {
      final server = FakeApiServer();
      server.on('PUT', '/api/v1/service-requests/$requestId/agreed-amount',
          (_) => apiJson(200, requestJson(status: 'matched', urgency: 'Emergency', surcharge: 100)));
      final api = await signedIn(server);

      await api.serviceRequests.setAgreedAmount(requestId, 1200);

      expect(bodyOf(server.sentTo('PUT', '/api/v1/service-requests/$requestId/agreed-amount').single),
          {'amount': 1200.0});
    });
  });

  group('calling a job off', () {
    test('cancel sends a reason only when there is one', () async {
      final server = FakeApiServer();
      server.on('POST', '/api/v1/service-requests/$requestId/cancel',
          (_) => apiJson(200, requestJson(status: 'cancelled')));
      final api = await signedIn(server);

      await api.serviceRequests.cancelRequest(requestId);
      await api.serviceRequests.cancelRequest(requestId, reason: 'Sorted it myself');

      final sent = server.sentTo('POST', '/api/v1/service-requests/$requestId/cancel');
      expect(bodyOf(sent.first), isEmpty);
      expect(bodyOf(sent.last), {'reason': 'Sorted it myself'});
    });

    test('a cancel refused under the ETA lock carries when it opens', () async {
      final server = FakeApiServer();
      server.on(
        'POST',
        '/api/v1/service-requests/$requestId/cancel',
        (_) => apiJson(409, {
          'error': {
            'code': 'conflict',
            'message': 'The mechanic is still on their way.',
            'details': {'cancellableAt': '2026-09-16T09:35:00.000Z'},
            'requestId': 'req-test-0001',
          },
        }),
      );
      final api = await signedIn(server);

      try {
        await api.serviceRequests.cancelRequest(requestId);
        fail('the lock should have refused this');
      } on ApiException catch (error) {
        expect(error.code, ApiErrorCodes.conflict);
        // The screen needs the moment the lock opens to start its countdown.
        // It arrives as an object, not as field errors, so it rides on `info`.
        expect(error.info['cancellableAt'], '2026-09-16T09:35:00.000Z');
        expect(error.details, isEmpty);
      }
    });

    test('reopen and the mechanic\'s cancel are separate routes', () async {
      final server = FakeApiServer();
      server.on('POST', '/api/v1/service-requests/$requestId/reopen',
          (_) => apiJson(200, requestJson()));
      server.on('POST', '/api/v1/service-requests/$requestId/mechanic-cancel',
          (_) => apiJson(200, requestJson()));
      final api = await signedIn(server);

      await api.serviceRequests.reopenRequest(requestId);
      await api.serviceRequests.mechanicCancelJob(requestId, reason: 'Van broke down');

      expect(server.count('POST', '/api/v1/service-requests/$requestId/reopen'), 1);
      expect(
        bodyOf(server.sentTo('POST', '/api/v1/service-requests/$requestId/mechanic-cancel').single),
        {'reason': 'Van broke down'},
      );
    });
  });

  group('live changes', () {
    test('both request events reach one stream, and both quote events another', () async {
      final server = FakeApiServer();
      server.on('POST', '/api/v1/auth/sign-in', (_) => apiJson(200, sessionBody()));
      final connector = FakeConnector();
      final api = testApi(server, connector: connector.call);
      await api.auth.signIn(const SignInRequest(
        identifier: 'juan@example.com',
        password: 'correct horse',
        surface: AppSurface.mobile,
      ));

      final requests = <ServiceRequest>[];
      final quotes = <JobQuote>[];
      final onRequests = api.serviceRequests.watchRequests().listen(requests.add);
      final onQuotes = api.serviceRequests.watchQuotes().listen(quotes.add);

      await settle();
      final connection = connector.connections.single;
      connection.serverSends({'type': 'ready'});
      await settle();

      connection.serverSends({'type': 'event', 'name': 'service_request.created', 'data': requestJson()});
      connection.serverSends({
        'type': 'event',
        'name': 'service_request.updated',
        'data': requestJson(status: 'matched'),
      });
      connection.serverSends({'type': 'event', 'name': 'quote.submitted', 'data': quoteJson()});
      connection.serverSends({
        'type': 'event',
        'name': 'quote.updated',
        'data': quoteJson(accepted: true),
      });
      await settle();

      expect(requests.map((request) => request.status),
          [ServiceRequestStatus.pending, ServiceRequestStatus.matched]);
      expect(quotes.map((quote) => quote.accepted), [false, true]);

      await onRequests.cancel();
      await onQuotes.cancel();
      await api.close();
    });

    test('a frame that will not parse is dropped, not fatal to the stream', () async {
      final server = FakeApiServer();
      server.on('POST', '/api/v1/auth/sign-in', (_) => apiJson(200, sessionBody()));
      final connector = FakeConnector();
      final api = testApi(server, connector: connector.call);
      await api.auth.signIn(const SignInRequest(
        identifier: 'juan@example.com',
        password: 'correct horse',
        surface: AppSurface.mobile,
      ));

      final seen = <ServiceRequest>[];
      final watch = api.serviceRequests.watchRequests().listen(seen.add);

      await settle();
      final connection = connector.connections.single;
      connection.serverSends({'type': 'ready'});
      await settle();

      // An unreadable date throws inside fromJson — the one thing that can.
      // An urgency this build does not know would not: fromWire falls back to
      // Normal rather than failing, which is the contract's own choice.
      connection.serverSends({
        'type': 'event',
        'name': 'service_request.updated',
        'data': requestJson(extra: {'createdAt': 'the day before yesterday'}),
      });
      connection.serverSends({'type': 'event', 'name': 'service_request.updated', 'data': requestJson()});
      await settle();

      // The bad frame is gone; the stream carried on and delivered the next.
      expect(seen.map((request) => request.id), [requestId]);

      await watch.cancel();
      await api.close();
    });
  });
}
