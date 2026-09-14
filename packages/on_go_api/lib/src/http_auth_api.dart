import 'package:on_go_shared/on_go_shared.dart';

import 'api_client.dart';
import 'api_session.dart';
import 'auth_session_payload.dart';

/// [AuthApi] over `/api/v1/auth`.
class HttpAuthApi implements AuthApi {
  HttpAuthApi({required ApiClient client, required ApiSession session})
      : _client = client,
        _session = session;

  final ApiClient _client;
  final ApiSession _session;

  @override
  Future<SignInResult> signIn(SignInRequest request) async {
    try {
      final json = await _client.post(
        ApiEndpoints.signIn,
        body: SignInRequest(
          identifier: request.identifier.trim(),
          password: request.password,
          surface: request.surface,
        ).toJson(),
      );
      final payload = AuthSessionPayload.fromJson(json);
      await _session.adopt(payload, newSession: true);
      return SignInResult.success(payload.account);
    } on ApiException catch (error) {
      final failure = switch (error.code) {
        ApiErrorCodes.invalidCredentials => SignInFailure.wrongPassword,
        ApiErrorCodes.wrongSurface => SignInFailure.wrongSurface,
        ApiErrorCodes.accountInactive => SignInFailure.accountInactive,
        ApiErrorCodes.accountLocked => SignInFailure.accountLocked,
        _ => null,
      };
      if (failure == null) rethrow;
      return SignInResult.failed(failure, message: error.message);
    }
  }

  @override
  Future<AuthenticatedAccount> register(RegisterRequest request) async {
    final payload = AuthSessionPayload.fromJson(
      await _client.post(ApiEndpoints.register, body: request.toJson()),
    );
    await _session.adopt(payload, newSession: true);
    return payload.account;
  }

  @override
  Future<AuthenticatedAccount?> restoreSession() async {
    if (!await _session.hasStoredSession()) return null;
    // A refused refresh ends the session and answers false; no network throws,
    // and the stored token is kept for the next try.
    final restored = await _session.refresh();
    return restored ? _session.account : null;
  }

  @override
  Future<AuthenticatedAccount> fetchCurrentAccount() async {
    final account = AuthenticatedAccount.fromJson(
      responseObject(await _client.get(ApiEndpoints.me, authenticated: true)),
    );
    _session.updateAccount(account);
    return account;
  }

  @override
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final json = responseObject(await _client.post(
        ApiEndpoints.changePassword,
        body: {'currentPassword': currentPassword, 'newPassword': newPassword},
        authenticated: true,
      ));
      // Every token issued before the change is dead, this one's included.
      final accessToken = json['accessToken'];
      final expiresIn = json['expiresIn'];
      if (accessToken is String && accessToken.isNotEmpty) {
        _session.replaceAccessToken(accessToken, expiresIn is num ? expiresIn.toInt() : 600);
      }
      return true;
    } on ApiException catch (error) {
      if (error.code == ApiErrorCodes.invalidCredentials) return false;
      rethrow;
    }
  }

  @override
  Future<PasswordResetRequested> requestPasswordReset(String email) async =>
      PasswordResetRequested.fromJson(responseObject(
        await _client.post(ApiEndpoints.resetPassword, body: {'email': email.trim()}),
      ));

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _client.post(
      ApiEndpoints.resetPasswordConfirm,
      body: {'email': email.trim(), 'code': code.trim(), 'newPassword': newPassword},
    );
  }

  @override
  Future<void> signOut() async {
    final accessToken = _session.accessToken;
    String? refreshToken;
    try {
      refreshToken = await _session.refreshTokens?.read();
    } catch (_) {
      // Sign out with whatever else there is.
    }

    // Local state first: signing out never waits on the network.
    await _session.end(SessionEndReason.signedOut);

    if (accessToken == null && refreshToken == null && _session.surface == AppSurface.mobile) return;
    try {
      await _client.post(
        ApiEndpoints.signOut,
        body: refreshToken == null ? null : {'refreshToken': refreshToken},
        bearerToken: accessToken,
      );
    } on ApiException {
      // Always succeeds from the user's side; the server revokes what it can.
    }
  }
}
