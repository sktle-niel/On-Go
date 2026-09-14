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

  SignInRequest request(String email) =>
      SignInRequest(identifier: email, password: 'correct horse', surface: AppSurface.mobile);

  group('sign-in', () {
    test('a client signs in: access token in memory, refresh token in the store', () async {
      server.on('POST', ApiEndpoints.signIn, (_) => apiJson(200, sessionBody(role: 'client')));

      final result = await api.auth.signIn(request('  juan@example.com '));

      expect(result.isSuccess, isTrue);
      expect(result.user!.role, UserRole.client);
      expect(result.user!.displayName, 'Juan Dela Cruz');
      expect(result.permissions.canApprove, isFalse);
      expect(bodyOf(server.requests.single), {
        'identifier': 'juan@example.com',
        'password': 'correct horse',
        'surface': 'mobile',
      });
      expect(api.session.accessToken, 'access-1');
      expect(store.token, 'refresh-1');
    });

    test('a mechanic signs in', () async {
      server.on('POST', ApiEndpoints.signIn,
          (_) => apiJson(200, sessionBody(role: 'mechanic', email: 'mech@example.com')));

      final result = await api.auth.signIn(request('mech@example.com'));

      expect(result.user!.role, UserRole.mechanic);
      expect(result.user!.email, 'mech@example.com');
      expect(api.session.isSignedIn, isTrue);
    });

    test('wrong credentials are an answer, with the server message, and open nothing', () async {
      server.on('POST', ApiEndpoints.signIn,
          (_) => apiError(401, 'invalid_credentials', 'Incorrect email or password.'));

      final result = await api.auth.signIn(request('juan@example.com'));

      expect(result.failure, SignInFailure.wrongPassword);
      expect(result.message, 'Incorrect email or password.');
      expect(api.session.isSignedIn, isFalse);
      expect(store.token, isNull);
    });

    test('a console account on the phone gets the server message verbatim', () async {
      server.on('POST', ApiEndpoints.signIn, (_) => apiError(
            403,
            'wrong_surface',
            'This account signs in on the On Go console.',
          ));

      final result = await api.auth.signIn(request('admin@example.com'));

      expect(result.failure, SignInFailure.wrongSurface);
      expect(result.message, 'This account signs in on the On Go console.');
    });

    test('a locked account and an inactive one are their own failures', () async {
      server.on('POST', ApiEndpoints.signIn,
          (_) => apiError(423, 'account_locked', 'Try again in 15 minutes.'));
      expect((await api.auth.signIn(request('a@example.com'))).failure, SignInFailure.accountLocked);

      server.on('POST', ApiEndpoints.signIn,
          (_) => apiError(403, 'account_inactive', 'This account has been suspended.'));
      expect((await api.auth.signIn(request('a@example.com'))).failure, SignInFailure.accountInactive);
    });

    test('rate limiting is thrown, not retried', () async {
      server.on('POST', ApiEndpoints.signIn,
          (_) => apiError(429, 'rate_limited', 'Try again in 2 minutes.'));

      await expectLater(
        api.auth.signIn(request('a@example.com')),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'rate_limited')
            .having((e) => e.message, 'message', 'Try again in 2 minutes.')),
      );
      expect(server.count('POST', ApiEndpoints.signIn), 1);
    });

    test('the console signs in as the console', () async {
      final console = testApi(server, surface: AppSurface.console);
      addTearDown(console.close);
      server.on('POST', ApiEndpoints.signIn,
          (_) => apiJson(200, sessionBody(role: 'admin', refresh: null, allPermissions: true)));

      final result = await console.auth.signIn(
        const SignInRequest(identifier: 'admin@example.com', password: 'pw', surface: AppSurface.console),
      );

      expect(bodyOf(server.requests.single)['surface'], 'console');
      expect(result.permissions.canChangeBackground, isTrue);
      expect(console.session.refreshTokens, isNull, reason: 'the cookie is the browser\'s');
    });
  });

  group('registration', () {
    test('creates the account and signs it in; empty optional fields are not sent', () async {
      server.on('POST', ApiEndpoints.register, (_) => apiJson(201, sessionBody(role: 'mechanic')));

      final account = await api.auth.register(const RegisterRequest(
        email: 'mech@example.com',
        password: 'long enough password',
        firstName: 'Juan',
        lastName: '',
        phone: '+63 917 000 0000',
        role: UserRole.mechanic,
      ));

      expect(bodyOf(server.requests.single), {
        'email': 'mech@example.com',
        'password': 'long enough password',
        'firstName': 'Juan',
        'phone': '+63 917 000 0000',
        'role': 'mechanic',
      });
      expect(account.user.role, UserRole.mechanic);
      expect(store.token, 'refresh-1');
    });

    test('a taken email and refused fields come back with what to show', () async {
      server.on('POST', ApiEndpoints.register,
          (_) => apiError(409, 'conflict', 'That email is already registered.'));
      await expectLater(
        api.auth.register(const RegisterRequest(
            email: 'a@example.com', password: 'password123', firstName: 'A', role: UserRole.client)),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'conflict')),
      );

      server.on('POST', ApiEndpoints.register, (_) => apiError(400, 'validation_failed', 'Invalid.',
          details: [
            {'path': '/password', 'message': 'must not contain the email name'},
          ]));
      await expectLater(
        api.auth.register(const RegisterRequest(
            email: 'juan@example.com', password: 'juan12345', firstName: 'Juan', role: UserRole.client)),
        throwsA(isA<ApiException>()
            .having((e) => e.fieldErrors, 'fieldErrors', {'password': 'must not contain the email name'})),
      );
      expect(api.session.isSignedIn, isFalse);
    });
  });

  group('session restoration', () {
    test('a stored refresh token reopens the session and is rotated', () async {
      store.token = 'stored-refresh';
      server.on('POST', ApiEndpoints.refresh,
          (_) => apiJson(200, sessionBody(role: 'mechanic', access: 'access-9', refresh: 'rotated')));

      final account = await api.auth.restoreSession();

      expect(account!.user.role, UserRole.mechanic);
      expect(bodyOf(server.requests.single), {'refreshToken': 'stored-refresh'});
      expect(server.requests.single.headers['Authorization'], isNull);
      expect(store.token, 'rotated');
      expect(api.session.accessToken, 'access-9');
    });

    test('nothing stored: no request, no session', () async {
      expect(await api.auth.restoreSession(), isNull);
      expect(server.requests, isEmpty);
    });

    test('a session that is over is forgotten quietly', () async {
      store.token = 'revoked';
      server.on('POST', ApiEndpoints.refresh,
          (_) => apiError(401, 'token_invalid', 'This session has been signed out.'));
      final changes = <SessionChange>[];
      api.session.changes.listen(changes.add);

      expect(await api.auth.restoreSession(), isNull);
      await settle();

      expect(store.token, isNull);
      expect(changes, isEmpty, reason: 'no "session ended" notice for a launch that was never signed in');
    });

    test('no network keeps the stored token for next time', () async {
      store.token = 'stored-refresh';
      server.on('POST', ApiEndpoints.refresh, (_) => throw http.ClientException('offline'));

      await expectLater(
        api.auth.restoreSession(),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.unreachable)),
      );
      expect(store.token, 'stored-refresh');
    });

    test('the console restores with an empty body; the cookie is the token', () async {
      final console = testApi(server, surface: AppSurface.console);
      addTearDown(console.close);
      server.on('POST', ApiEndpoints.refresh,
          (_) => apiJson(200, sessionBody(role: 'admin', refresh: null, allPermissions: true)));

      final account = await console.auth.restoreSession();

      expect(bodyOf(server.requests.single), isEmpty);
      expect(account!.permissions.canApprove, isTrue);
    });

    test('/auth/me loads the account and its permissions', () async {
      await api.session.adopt(AuthSessionPayload.fromJson(sessionBody()), newSession: true);
      server.on('GET', ApiEndpoints.me, (_) => apiJson(200, {
            'user': {'accountId': 'x', 'displayName': 'Maria', 'email': 'm@example.com', 'role': 'moderator'},
            'permissions': {'canApprove': true, 'canReject': false, 'canEscalate': false, 'canChangeBackground': true},
          }));

      final account = await api.auth.fetchCurrentAccount();

      expect(account.user.role, UserRole.moderator);
      expect(account.permissions.canApprove, isTrue);
      expect(account.permissions.canReject, isFalse);
      expect(api.session.account!.permissions.canChangeBackground, isTrue);
    });
  });

  group('passwords', () {
    setUp(() => api.session.adopt(AuthSessionPayload.fromJson(sessionBody()), newSession: true));

    test('a change sends no account id and uses the new access token afterwards', () async {
      server
        ..on('POST', ApiEndpoints.changePassword,
            (_) => apiJson(200, {'accessToken': 'after-change', 'tokenType': 'Bearer', 'expiresIn': 600}))
        ..on('GET', ApiEndpoints.me, (_) => apiJson(200, sessionBody()));

      expect(await api.auth.changePassword(currentPassword: 'old pass', newPassword: 'new password 1'), isTrue);
      await api.auth.fetchCurrentAccount();

      expect(bodyOf(server.sentTo('POST', ApiEndpoints.changePassword).single),
          {'currentPassword': 'old pass', 'newPassword': 'new password 1'});
      expect(server.sentTo('GET', ApiEndpoints.me).single.headers['Authorization'], 'Bearer after-change');
      expect(store.token, 'refresh-1', reason: 'the caller\'s own refresh token stays valid');
    });

    test('a wrong current password is false and leaves the session alone', () async {
      server.on('POST', ApiEndpoints.changePassword,
          (_) => apiError(401, 'invalid_credentials', 'The current password is incorrect.'));

      expect(await api.auth.changePassword(currentPassword: 'nope', newPassword: 'new password 1'), isFalse);
      expect(api.session.isSignedIn, isTrue);
      expect(server.count('POST', ApiEndpoints.refresh), 0);
    });

    test('reset: request a code, then confirm with it', () async {
      server
        ..on('POST', ApiEndpoints.resetPassword, (_) => apiJson(202, {
              'status': 'accepted',
              'message': 'If that email has an account, a code is on its way.',
            }))
        ..on('POST', ApiEndpoints.resetPasswordConfirm, (_) => noContent());

      final reply = await api.auth.requestPasswordReset(' juan@example.com ');
      await api.auth.confirmPasswordReset(email: 'juan@example.com', code: '123456', newPassword: 'brand new pass');

      expect(reply.message, 'If that email has an account, a code is on its way.');
      expect(bodyOf(server.sentTo('POST', ApiEndpoints.resetPassword).single), {'email': 'juan@example.com'});
      expect(bodyOf(server.sentTo('POST', ApiEndpoints.resetPasswordConfirm).single),
          {'email': 'juan@example.com', 'code': '123456', 'newPassword': 'brand new pass'});
    });

    test('a bad reset code is its own code', () async {
      server.on('POST', ApiEndpoints.resetPasswordConfirm,
          (_) => apiError(400, 'invalid_reset_code', 'That code is wrong or has expired.'));

      await expectLater(
        api.auth.confirmPasswordReset(email: 'a@example.com', code: '000000', newPassword: 'brand new pass'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiErrorCodes.invalidResetCode)),
      );
    });
  });

  group('sign-out', () {
    test('sends both tokens and clears local state', () async {
      await api.session.adopt(AuthSessionPayload.fromJson(sessionBody()), newSession: true);
      server.on('POST', ApiEndpoints.signOut, (_) => noContent());

      await api.auth.signOut();

      final sent = server.sentTo('POST', ApiEndpoints.signOut).single;
      expect(sent.headers['Authorization'], 'Bearer access-1');
      expect(bodyOf(sent), {'refreshToken': 'refresh-1'});
      expect(api.session.isSignedIn, isFalse);
      expect(store.token, isNull);
    });

    test('never fails on the user, even with no network', () async {
      await api.session.adopt(AuthSessionPayload.fromJson(sessionBody()), newSession: true);
      server.on('POST', ApiEndpoints.signOut, (_) => throw http.ClientException('offline'));
      final ended = api.session.changes.firstWhere((c) => c.kind == SessionChangeKind.ended);

      await api.auth.signOut();

      expect((await ended).reason, SessionEndReason.signedOut);
      expect(api.session.isSignedIn, isFalse);
      expect(store.token, isNull);
    });
  });
}
