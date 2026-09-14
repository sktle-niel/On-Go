import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:on_go_api/on_go_api.dart';
import 'package:on_go_shared/on_go_shared.dart';

import 'api_test_support.dart';

void main() {
  late FakeApiServer server;
  late ApiSession session;
  late ApiClient client;

  setUp(() {
    server = FakeApiServer();
    session = ApiSession(surface: AppSurface.mobile, refreshTokens: InMemoryRefreshTokenStore());
    client = ApiClient(environment: testEnvironment, session: session, httpClient: server.client);
  });

  Future<void> signIn() =>
      session.adopt(AuthSessionPayload.fromJson(sessionBody()), newSession: true);

  group('points policy', () {
    const stored = {'clientNormal': 1, 'clientUrgent': 3, 'clientEmergency': 5, 'mechanicPerPeso': 0.05};

    test('is read before sign-in, from the prefixed route, with no token', () async {
      server.on('GET', '/api/v1/platform/points-policy', (_) => apiJson(200, stored));

      final policy = await HttpPointsPolicyApi(client).fetch();

      expect(policy, PointsPolicy.defaults);
      expect(server.requests.single.headers['Authorization'], isNull);
    });

    test('watch: the fetched rules, then points_policy.updated from the socket', () async {
      server.on('GET', ApiEndpoints.pointsPolicy, (_) => apiJson(200, stored));
      final connector = FakeConnector();
      final socket = EventSocket(
        environment: testEnvironment,
        session: session,
        connector: connector.call,
        wait: (_) async {},
      );
      addTearDown(socket.dispose);
      await signIn();
      socket.start();

      final seen = <PointsPolicy>[];
      final subscription = HttpPointsPolicyApi(client, events: socket).watch().listen(seen.add);
      addTearDown(subscription.cancel);
      await settle();

      connector.connections.single
        ..serverSends({'type': 'ready', 'user': {}})
        ..serverSends({
          'type': 'event',
          'name': 'points_policy.updated',
          'data': {'clientNormal': 2, 'clientUrgent': 4, 'clientEmergency': 8, 'mechanicPerPeso': 0.1},
          'at': '2026-09-14T04:38:28.123Z',
        });
      await settle();

      expect(seen.first, PointsPolicy.defaults);
      expect(seen.last, const PointsPolicy(clientNormal: 2, clientUrgent: 4, clientEmergency: 8, mechanicPerPeso: 0.1));
    });

    test('update is an authenticated PUT; a non-admin is forbidden', () async {
      await signIn();
      server.on('PUT', ApiEndpoints.pointsPolicy, (request) => apiJson(200, bodyOf(request)));
      const edited = PointsPolicy(clientNormal: 0.5);

      expect(await HttpPointsPolicyApi(client).update(edited), edited);
      final put = server.sentTo('PUT', ApiEndpoints.pointsPolicy).single;
      expect(put.headers['Authorization'], 'Bearer access-1');
      expect(bodyOf(put), edited.toJson());

      server.on('PUT', ApiEndpoints.pointsPolicy, (_) => apiError(403, 'forbidden', 'Admins only.'));
      await expectLater(
        HttpPointsPolicyApi(client).update(edited),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.forbidden)),
      );
    });
  });

  group('payments', () {
    final payment = CompletedPaymentReport(
      requestId: 'job-2026-0001',
      platformFee: 150,
      paidAt: DateTime.utc(2026, 9, 14, 8, 12),
      urgency: RevenueUrgency.urgent,
    );

    test('reports the contract fields and accepts 204', () async {
      await signIn();
      server.on('POST', ApiEndpoints.payments, (_) => noContent());

      await HttpPlatformRevenueApi(client).reportCompletedPayment(payment);

      final sent = server.requests.single;
      expect(sent.headers['Authorization'], 'Bearer access-1');
      expect(bodyOf(sent), {
        'requestId': 'job-2026-0001',
        'platformFee': 150.0,
        'paidAt': '2026-09-14T08:12:00.000Z',
        'urgency': 'urgent',
      });
    });

    test('is re-sent after a network failure — the server books it once', () async {
      await signIn();
      var attempts = 0;
      server.on('POST', ApiEndpoints.payments, (_) {
        if (++attempts == 1) throw http.ClientException('offline');
        return noContent();
      });
      final waits = <Duration>[];

      await HttpPlatformRevenueApi(client, wait: (delay) async => waits.add(delay)).reportCompletedPayment(payment);

      expect(attempts, 2);
      expect(waits, [const Duration(seconds: 2)]);
    });

    test('a refusal is not retried', () async {
      await signIn();
      server.on('POST', ApiEndpoints.payments, (_) => apiError(403, 'forbidden', 'Mobile roles only.'));

      await expectLater(
        HttpPlatformRevenueApi(client, wait: (_) async {}).reportCompletedPayment(payment),
        throwsA(isA<ApiException>()),
      );
      expect(server.count('POST', ApiEndpoints.payments), 1);
    });
  });

  test('revenue summary reads months by urgency', () async {
    await signIn();
    server.on('GET', ApiEndpoints.revenueSummary, (_) => apiJson(200, {
          'months': [
            {
              'month': 'Sep',
              'year': 2026,
              'revenue': 450,
              'transactions': 3,
              'byUrgency': {
                'normal': {'revenue': 0, 'transactions': 1},
                'urgent': {'revenue': 150, 'transactions': 1},
                'emergency': {'revenue': 300, 'transactions': 1},
              },
            },
          ],
          'priorityFeeRevenue': 450,
          'priorityFeeCount': 2,
        }));

    final summary = await HttpPlatformRevenueApi(client).fetchSummary();

    final september = summary.months.single;
    expect(september.periodLabel, 'Sep 2026');
    expect(september.transactionsFor(RevenueUrgency.normal), 1);
    expect(september.revenueFor(RevenueUrgency.emergency), 300);
    expect(summary.priorityFeeCount, 2);
    expect(summary.transactionsForYearBy(RevenueUrgency.urgent, 2026), 1);
  });

  group('appearance', () {
    test('read is public and live', () async {
      server.on('GET', ApiEndpoints.appearance, (_) => apiJson(200, {'authBackgroundUrl': null, 'updatedAt': null}));

      final appearance = await HttpPlatformAppearanceApi(client).fetch();

      expect(appearance.hasBackground, isFalse);
      expect(server.requests.single.headers['Authorization'], isNull);
    });

    test('publishing is sent as the contract says, and a 501 is reported as unfinished', () async {
      await signIn();
      server.on('PUT', ApiEndpoints.appearance,
          (_) => apiError(501, 'not_implemented', 'Background uploads are being implemented.'));

      await expectLater(
        HttpPlatformAppearanceApi(client).publishBackground(bytes: [1, 2, 3], fileName: 'bg.png'),
        throwsA(isA<ApiException>().having((e) => e.isNotImplemented, 'isNotImplemented', true)),
      );

      final put = server.requests.single;
      expect(put.headers['content-type'], startsWith('multipart/form-data'));
      expect(put.body, contains('name="file"; filename="bg.png"'));
      expect(put.body, contains('content-type: image/png'));
    });
  });

  group('unfinished domains', () {
    test('verification requests fail as not implemented and invent nothing', () async {
      await signIn();
      server.on('GET', ApiEndpoints.verificationRequests,
          (_) => apiError(501, 'not_implemented', 'Verification requests are being implemented.'));
      final api = HttpAccountVerificationApi(client);

      await expectLater(
        api.listRequests(status: ApprovalStatus.pending),
        throwsA(isA<ApiException>().having((e) => e.isNotImplemented, 'isNotImplemented', true)),
      );
      expect(server.requests.single.url.queryParameters, {'status': 'pending'});

      await expectLater(
        api.watchRequests(),
        emitsError(isA<ApiException>().having((e) => e.isNotImplemented, 'isNotImplemented', true)),
      );
    });

    test('a verification request that is not yours reads as missing', () async {
      await signIn();
      server.on('GET', ApiEndpoints.verificationRequest('abc'), (_) => apiError(404, 'not_found', 'Not found.'));

      expect(await HttpAccountVerificationApi(client).findRequest('abc'), isNull);
    });
  });

  group('RemoteValue', () {
    test('listeners share a fetch, and a reconnect re-fetches', () async {
      var now = DateTime(2026, 9, 14, 12);
      var fetches = 0;
      final connector = FakeConnector();
      final socket = EventSocket(
        environment: testEnvironment,
        session: session,
        connector: connector.call,
        wait: (_) async {},
      );
      addTearDown(socket.dispose);
      await signIn();

      final value = RemoteValue<int>(
        fetch: () async => ++fetches,
        events: socket,
        clock: () => now,
      );
      final a = value.watch().listen((_) {});
      final b = value.watch().listen((_) {});
      addTearDown(a.cancel);
      addTearDown(b.cancel);
      await settle();
      expect(fetches, 1);

      socket.start();
      await settle();
      now = now.add(const Duration(seconds: 5));
      connector.connections.single.serverSends({'type': 'ready', 'user': {}});
      await settle();

      expect(fetches, 2, reason: 'events during a disconnection are not queued');
    });

    test('a failed fetch keeps the last value and reports the error', () async {
      var fail = false;
      final value = RemoteValue<int>(fetch: () async {
        if (fail) throw const ApiException(ApiErrorKind.unreachable, unreachableMessage);
        return 7;
      });
      final events = <Object>[];
      final subscription = value.watch().listen(events.add, onError: events.add);
      addTearDown(subscription.cancel);
      await settle();

      fail = true;
      await expectLater(value.refresh(), throwsA(isA<ApiException>()));
      await settle();

      expect(events.first, 7);
      expect(events.last, isA<ApiException>());
      expect(value.value, 7);
    });
  });
}
