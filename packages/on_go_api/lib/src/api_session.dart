import 'dart:async';

import 'package:on_go_shared/on_go_shared.dart';

import 'auth_session_payload.dart';
import 'refresh_token_store.dart';

/// Why a session stopped.
enum SessionEndReason {
  /// The user signed out on this device.
  signedOut,

  /// The refresh token expired (idle or absolute), or there was none to use.
  expired,

  /// `token_invalid`: signed out elsewhere, or a refresh token was reused.
  invalid,

  /// `account_inactive`: the account was suspended or deleted.
  accountInactive,
}

enum SessionChangeKind {
  /// A sign-in, a registration or a restored session.
  started,

  /// The access token was rotated by a refresh.
  refreshed,

  /// The access token was swapped outside a refresh (a password change
  /// retires every earlier token). Anything authenticated with the old one —
  /// the event socket — has to re-authenticate.
  tokenReplaced,

  /// The account or its permissions were re-read.
  accountChanged,

  /// A call was refused with `403 forbidden`. Permissions may have changed.
  forbidden,

  ended,
}

class SessionChange {
  const SessionChange(this.kind, {this.reason, this.message});

  final SessionChangeKind kind;

  /// Set when [kind] is [SessionChangeKind.ended].
  final SessionEndReason? reason;

  /// The server's words, when the end came from an error it sent.
  final String? message;
}

/// Exchanges a refresh token (null on the console, whose token is a cookie)
/// for a new session.
typedef SessionRefresher = Future<AuthSessionPayload> Function(String? refreshToken);

/// The tokens behind one signed-in app, and the rules for keeping them.
///
/// * The access token lives in memory only.
/// * On mobile the refresh token lives in [refreshTokens], written before it
///   is ever used. On the console there is no store: the browser holds it as
///   an httpOnly cookie.
/// * [refresh] is serialized. Two refreshes with one token look like token
///   theft to the server and sign the user out everywhere, so however many
///   requests find their token expired at once, one refresh runs and the rest
///   wait for it.
class ApiSession {
  ApiSession({
    required this.surface,
    this.refreshTokens,
    DateTime Function()? clock,
  })  : assert(
          surface == AppSurface.console || refreshTokens != null,
          'A mobile session needs somewhere to keep its refresh token.',
        ),
        _clock = clock ?? DateTime.now;

  final AppSurface surface;

  /// Null on the console.
  final RefreshTokenStore? refreshTokens;

  final DateTime Function() _clock;
  SessionRefresher? _refresher;

  String? _accessToken;
  DateTime? _accessExpiresAt;
  AuthenticatedAccount? _account;
  Future<bool>? _refreshing;

  /// Bumped whenever the session ends, so a refresh that was already on the
  /// wire when the user signed out cannot bring the session back.
  int _epoch = 0;

  final StreamController<SessionChange> _changes = StreamController<SessionChange>.broadcast();

  /// How close to its expiry a token is treated as expired, so it is not
  /// sent only to die in transit.
  static const Duration expiryMargin = Duration(seconds: 15);

  void attachRefresher(SessionRefresher refresher) => _refresher = refresher;

  Stream<SessionChange> get changes => _changes.stream;

  String? get accessToken => _accessToken;

  bool get isSignedIn => _accessToken != null;

  AuthenticatedAccount? get account => _account;

  bool get accessTokenNearExpiry {
    final expiresAt = _accessExpiresAt;
    return expiresAt != null && !_clock().isBefore(expiresAt.subtract(expiryMargin));
  }

  /// Whether there may be a session to restore. Always true on the console,
  /// where only the browser knows whether the cookie is still there.
  Future<bool> hasStoredSession() async {
    final store = refreshTokens;
    if (store == null) return true;
    try {
      return await store.read() != null;
    } catch (_) {
      return false;
    }
  }

  /// Takes over the tokens and account in [payload]. [newSession] for a
  /// sign-in or registration rather than a rotation.
  Future<void> adopt(AuthSessionPayload payload, {bool newSession = false}) async {
    final wasSignedIn = isSignedIn;
    final refreshToken = payload.refreshToken;
    final store = refreshTokens;
    if (store != null && refreshToken != null) await store.write(refreshToken);

    _accessToken = payload.accessToken;
    _accessExpiresAt = _clock().add(Duration(seconds: payload.expiresIn));
    _account = payload.account;
    _emit(SessionChange(
      newSession || !wasSignedIn ? SessionChangeKind.started : SessionChangeKind.refreshed,
    ));
  }

  /// Swaps in an access token issued outside a refresh — `POST /auth/password`
  /// returns one. The refresh token is unchanged.
  void replaceAccessToken(String accessToken, int expiresIn) {
    _accessToken = accessToken;
    _accessExpiresAt = _clock().add(Duration(seconds: expiresIn));
    _emit(const SessionChange(SessionChangeKind.tokenReplaced));
  }

  void updateAccount(AuthenticatedAccount account) {
    _account = account;
    _emit(const SessionChange(SessionChangeKind.accountChanged));
  }

  void reportForbidden() => _emit(const SessionChange(SessionChangeKind.forbidden));

  /// Rotates the refresh token for a new access token. True when it worked;
  /// false when the session is over (and has been ended). Throws
  /// [ApiException] when the server could not be asked, leaving the session
  /// as it was.
  Future<bool> refresh() {
    final pending = _refreshing;
    if (pending != null) return pending;
    final future = _runRefresh();
    _refreshing = future;
    future.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_refreshing, future)) _refreshing = null;
    });
    return future;
  }

  Future<bool> _runRefresh() async {
    final refresher = _refresher;
    if (refresher == null) {
      throw StateError('ApiSession.refresh called before a refresher was attached.');
    }
    final epoch = _epoch;

    String? token;
    final store = refreshTokens;
    if (store != null) {
      token = await store.read();
      if (token == null) {
        await end(SessionEndReason.expired);
        return false;
      }
    }

    final AuthSessionPayload payload;
    try {
      payload = await refresher(token);
    } on ApiException catch (error) {
      if (!_endsSession(error)) rethrow;
      if (epoch == _epoch) await end(reasonFor(error.code), message: error.message);
      return false;
    }

    if (epoch != _epoch) return false;
    await adopt(payload);
    return true;
  }

  /// A refresh refused outright (400, 401, 403) means there is no session
  /// left. Anything else — no network, a 5xx, rate limiting — says nothing
  /// about the session.
  static bool _endsSession(ApiException error) {
    final status = error.statusCode;
    return status == 400 || status == 401 || status == 403;
  }

  static SessionEndReason reasonFor(String? code) => switch (code) {
        ApiErrorCodes.accountInactive => SessionEndReason.accountInactive,
        ApiErrorCodes.tokenInvalid => SessionEndReason.invalid,
        _ => SessionEndReason.expired,
      };

  /// Forgets the tokens here and in storage. Announced only when there was a
  /// session to end, so a failed restore at launch is silent.
  Future<void> end(SessionEndReason reason, {String? message}) async {
    _epoch++;
    final hadSession = _accessToken != null || _account != null;
    _accessToken = null;
    _accessExpiresAt = null;
    _account = null;
    try {
      await refreshTokens?.clear();
    } catch (_) {
      // Nothing better to do; the token is useless without its session anyway.
    }
    if (hadSession) _emit(SessionChange(SessionChangeKind.ended, reason: reason, message: message));
  }

  void _emit(SessionChange change) {
    if (!_changes.isClosed) _changes.add(change);
  }

  Future<void> close() => _changes.close();
}
