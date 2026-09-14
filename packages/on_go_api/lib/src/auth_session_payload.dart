import 'package:on_go_shared/on_go_shared.dart';

/// The `AuthSession` body sign-in, register and refresh return:
/// `{ user, permissions, accessToken, tokenType, expiresIn, refreshToken? }`.
///
/// Internal to this package on purpose. Screens get the
/// [AuthenticatedAccount]; the tokens stop at [ApiSession].
class AuthSessionPayload {
  const AuthSessionPayload({
    required this.account,
    required this.accessToken,
    required this.expiresIn,
    this.refreshToken,
  });

  final AuthenticatedAccount account;
  final String accessToken;

  /// Seconds the access token lives (600 today).
  final int expiresIn;

  /// Present on the mobile surface only; the console's arrives as a cookie.
  final String? refreshToken;

  factory AuthSessionPayload.fromJson(Object? json) {
    if (json is! Map) throw _unexpected;
    final map = Map<String, dynamic>.from(json);
    final accessToken = map['accessToken'];
    if (accessToken is! String || accessToken.isEmpty || map['user'] is! Map) {
      throw _unexpected;
    }
    final expiresIn = map['expiresIn'];
    final refreshToken = map['refreshToken'];
    return AuthSessionPayload(
      account: AuthenticatedAccount.fromJson(map),
      accessToken: accessToken,
      expiresIn: expiresIn is num ? expiresIn.toInt() : 600,
      refreshToken: refreshToken is String && refreshToken.isNotEmpty ? refreshToken : null,
    );
  }

  static const ApiException _unexpected = ApiException(
    ApiErrorKind.unknown,
    'The On Go server sent a sign-in response this app could not read.',
  );
}
