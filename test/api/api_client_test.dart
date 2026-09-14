import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:on_go_api/on_go_api.dart';
import 'package:on_go_shared/on_go_shared.dart';

import 'api_test_support.dart';

void main() {
  late FakeApiServer server;
  late InMemoryRefreshTokenStore store;
  late OnGoApi api;

  setUp(() {
    server = FakeApiServer();
    store = InMemoryRefreshTokenStore();
    api = testApi(server, store: store);
  });

  tearDown(() => api.close());

  Future<void> signIn({String access = 'access-1', String refresh = 'refresh-1'}) =>
      api.session.adopt(AuthSessionPayload.fromJson(sessionBody(access: access, refresh: refresh)), newSession: true);

  group('environment', () {
    test('builds URLs from one base URL, and the socket URL from it', () {
      const staging = ApiEnvironment.staging;
      expect(staging.uri(ApiEndpoints.pointsPolicy).toString(),
          'https://ongo-api-618821603306.asia-southeast1.run.app/api/v1/platform/points-policy');
      expect(staging.eventsUri.toString(),
          'wss://ongo-api-618821603306.asia-southeast1.run.app/api/v1/events');
      expect(const ApiEnvironment(baseUrl: 'http://localhost:8080/').eventsUri.toString(),
          'ws://localhost:8080/api/v1/events');
      expect(staging.requestTimeout, greaterThanOrEqualTo(const Duration(seconds: 10)),
          reason: 'staging cold starts take 2–5 s');
    });

    test('points policy lives under the version prefix like every route', () {
      expect(ApiEndpoints.pointsPolicy, '/api/v1/platform/points-policy');
    });
  });

  group('error envelope', () {
    test('code, message, details and requestId are all kept', () async {
      server.on('POST', ApiEndpoints.register, (_) => apiError(
            400,
            'validation_failed',
            'Some fields are not valid.',
            details: [
              {'path': '/email', 'message': 'must match format "email"'},
            ],
            requestId: '7018eaa3-d4f2-46d9-9a76-2fb97472f428',
          ));

      final error = await api.client.post(ApiEndpoints.register, body: {}).then<ApiException?>(
        (_) => null,
        onError: (Object e) => e as ApiException,
      );

      expect(error!.kind, ApiErrorKind.rejected);
      expect(error.code, ApiErrorCodes.validationFailed);
      expect(error.message, 'Some fields are not valid.');
      expect(error.statusCode, 400);
      expect(error.requestId, '7018eaa3-d4f2-46d9-9a76-2fb97472f428');
      expect(error.fieldErrors, {'email': 'must match format "email"'});
    });

    test('every documented status maps to its kind', () {
      const cases = <(int, String, ApiErrorKind)>[
        (400, 'bad_request', ApiErrorKind.rejected),
        (400, 'invalid_reset_code', ApiErrorKind.rejected),
        (401, 'unauthorized', ApiErrorKind.unauthenticated),
        (401, 'invalid_credentials', ApiErrorKind.unauthenticated),
        (403, 'forbidden', ApiErrorKind.forbidden),
        (403, 'account_inactive', ApiErrorKind.forbidden),
        (403, 'wrong_surface', ApiErrorKind.forbidden),
        (404, 'not_found', ApiErrorKind.notFound),
        (409, 'conflict', ApiErrorKind.rejected),
        (413, 'payload_too_large', ApiErrorKind.rejected),
        (423, 'account_locked', ApiErrorKind.rejected),
        (429, 'rate_limited', ApiErrorKind.rejected),
        (500, 'internal_error', ApiErrorKind.unknown),
        (501, 'not_implemented', ApiErrorKind.unsupported),
        (503, 'service_unavailable', ApiErrorKind.unknown),
      ];
      for (final (status, code, kind) in cases) {
        final error = apiExceptionFromResponse(
          status,
          '{"error":{"code":"$code","message":"m","requestId":"r"}}',
        );
        expect(error.kind, kind, reason: '$status $code');
        expect(error.code, code);
      }
    });

    test('501 not_implemented is an unfinished feature, not a crash', () async {
      server.on('GET', ApiEndpoints.auditLog,
          (_) => apiError(501, 'not_implemented', 'The audit log is being implemented.'));
      await signIn();

      await expectLater(
        api.moderators.listAuditLog(),
        throwsA(isA<ApiException>()
            .having((e) => e.isNotImplemented, 'isNotImplemented', true)
            .having((e) => e.kind, 'kind', ApiErrorKind.unsupported)
            .having((e) => e.message, 'message', 'The audit log is being implemented.')),
      );
      expect(api.session.isSignedIn, isTrue, reason: 'a 501 says nothing about the session');
    });

    test('a body that is not the envelope still becomes an ApiException', () async {
      server.on('GET', ApiEndpoints.pointsPolicy, (_) => http.Response('<html>Bad gateway</html>', 502));

      await expectLater(
        api.pointsPolicy.fetch(),
        throwsA(isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.unknown)
            .having((e) => e.statusCode, 'statusCode', 502)),
      );
    });
  });

  group('when the API is unavailable', () {
    test('no network is unreachable', () async {
      server.on('GET', ApiEndpoints.pointsPolicy, (_) => throw http.ClientException('Failed host lookup'));

      await expectLater(
        api.pointsPolicy.fetch(),
        throwsA(isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.unreachable)
            .having((e) => e.message, 'message', unreachableMessage)),
      );
    });

    test('no answer in time is unreachable', () async {
      final slow = FakeApiServer()
        ..on('GET', ApiEndpoints.pointsPolicy, (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return apiJson(200, PointsPolicy.defaults.toJson());
        });
      final client = ApiClient(
        environment: const ApiEnvironment(baseUrl: 'https://api.test', requestTimeout: Duration(milliseconds: 50)),
        session: ApiSession(surface: AppSurface.console),
        httpClient: slow.client,
      );

      await expectLater(
        client.get(ApiEndpoints.pointsPolicy),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.unreachable)),
      );
    });
  });

  group('tokens', () {
    test('the access token goes in the Authorization header and never the URL', () async {
      server.on('GET', ApiEndpoints.me, (_) => apiJson(200, sessionBody()));
      await signIn();

      await api.auth.fetchCurrentAccount();

      final request = server.sentTo('GET', ApiEndpoints.me).single;
      expect(request.headers['Authorization'], 'Bearer access-1');
      expect(request.url.toString(), isNot(contains('access-1')));
      expect(request.url.query, isEmpty);
    });

    test('an authenticated call with no session fails without a request', () async {
      await expectLater(
        api.auth.fetchCurrentAccount(),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.unauthenticated)),
      );
      expect(server.requests, isEmpty);
    });

    test('token_expired refreshes once, stores the new refresh token, then retries once', () async {
      String? storedWhenRetried;
      server
        ..on('GET', ApiEndpoints.me, (request) {
          if (request.headers['Authorization'] == 'Bearer access-2') {
            storedWhenRetried = store.token;
            return apiJson(200, sessionBody());
          }
          return apiError(401, 'token_expired', 'The access token has expired.');
        })
        ..on('POST', ApiEndpoints.refresh, (_) => apiJson(200, sessionBody(access: 'access-2', refresh: 'refresh-2')));
      await signIn();

      await api.auth.fetchCurrentAccount();

      expect(server.count('GET', ApiEndpoints.me), 2);
      expect(server.count('POST', ApiEndpoints.refresh), 1);
      expect(bodyOf(server.sentTo('POST', ApiEndpoints.refresh).single), {'refreshToken': 'refresh-1'});
      expect(storedWhenRetried, 'refresh-2', reason: 'persisted before the new token is used');
      expect(api.session.accessToken, 'access-2');
    });

    test('requests that expire together share one refresh', () async {
      server
        ..on('GET', ApiEndpoints.me, (request) => request.headers['Authorization'] == 'Bearer access-2'
            ? apiJson(200, sessionBody())
            : apiError(401, 'token_expired', 'The access token has expired.'))
        ..on('POST', ApiEndpoints.refresh, (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return apiJson(200, sessionBody(access: 'access-2', refresh: 'refresh-2'));
        });
      await signIn();

      await Future.wait([
        api.auth.fetchCurrentAccount(),
        api.auth.fetchCurrentAccount(),
        api.auth.fetchCurrentAccount(),
      ]);

      expect(server.count('POST', ApiEndpoints.refresh), 1,
          reason: 'two refreshes with one token read as theft and sign the user out');
      expect(server.count('GET', ApiEndpoints.me), 6);
    });

    test('a retry that is still refused is returned, never looped', () async {
      server
        ..on('GET', ApiEndpoints.me, (_) => apiError(401, 'token_expired', 'The access token has expired.'))
        ..on('POST', ApiEndpoints.refresh, (_) => apiJson(200, sessionBody(access: 'access-2', refresh: 'refresh-2')));
      await signIn();

      await expectLater(api.auth.fetchCurrentAccount(), throwsA(isA<ApiException>()));
      expect(server.count('GET', ApiEndpoints.me), 2);
      expect(server.count('POST', ApiEndpoints.refresh), 1);
    });

    test('a refresh refused with token_invalid ends the session and clears the stored token', () async {
      server
        ..on('GET', ApiEndpoints.me, (_) => apiError(401, 'token_expired', 'The access token has expired.'))
        ..on('POST', ApiEndpoints.refresh,
            (_) => apiError(401, 'token_invalid', 'This session has been signed out.'));
      await signIn();
      final changes = <SessionChange>[];
      api.session.changes.listen(changes.add);

      await expectLater(
        api.auth.fetchCurrentAccount(),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.unauthenticated)),
      );
      await settle();

      expect(api.session.isSignedIn, isFalse);
      expect(store.token, isNull);
      expect(changes.last.kind, SessionChangeKind.ended);
      expect(changes.last.reason, SessionEndReason.invalid);
    });

    test('a refresh that says token_expired asks the user to sign in again', () async {
      server
        ..on('GET', ApiEndpoints.me, (_) => apiError(401, 'token_expired', 'The access token has expired.'))
        ..on('POST', ApiEndpoints.refresh, (_) => apiError(401, 'token_expired', 'Please sign in again.'));
      await signIn();
      final ended = api.session.changes.firstWhere((c) => c.kind == SessionChangeKind.ended);

      await expectLater(api.auth.fetchCurrentAccount(), throwsA(isA<ApiException>()));

      expect((await ended).reason, SessionEndReason.expired);
      expect(server.count('POST', ApiEndpoints.refresh), 1);
    });

    test('account_inactive on any call ends the session with the server message', () async {
      server.on('POST', ApiEndpoints.payments,
          (_) => apiError(403, 'account_inactive', 'This account has been suspended.'));
      await signIn();
      final ended = api.session.changes.firstWhere((c) => c.kind == SessionChangeKind.ended);

      await expectLater(
        api.revenue.reportCompletedPayment(
          CompletedPaymentReport(requestId: 'job-1', platformFee: 0, paidAt: DateTime.utc(2026, 9, 14)),
        ),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'account_inactive')),
      );

      final change = await ended;
      expect(change.reason, SessionEndReason.accountInactive);
      expect(change.message, 'This account has been suspended.');
      expect(store.token, isNull);
    });

    test('forbidden is reported, so permissions can be re-read', () async {
      server.on('GET', ApiEndpoints.revenueSummary, (_) => apiError(403, 'forbidden', 'Admins only.'));
      await signIn();
      final forbidden = api.session.changes.firstWhere((c) => c.kind == SessionChangeKind.forbidden);

      await expectLater(api.revenue.fetchSummary(), throwsA(isA<ApiException>()));

      await forbidden;
      expect(api.session.isSignedIn, isTrue);
    });

    test('a refresh with no network keeps the session for the next try', () async {
      server
        ..on('GET', ApiEndpoints.me, (_) => apiError(401, 'token_expired', 'The access token has expired.'))
        ..on('POST', ApiEndpoints.refresh, (_) => throw http.ClientException('offline'));
      await signIn();

      await expectLater(
        api.auth.fetchCurrentAccount(),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.unreachable)),
      );
      expect(store.token, 'refresh-1');
      expect(api.session.isSignedIn, isTrue);
    });
  });
}
