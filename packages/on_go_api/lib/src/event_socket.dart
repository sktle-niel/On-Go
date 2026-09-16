import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:on_go_shared/on_go_shared.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_environment.dart';
import 'api_session.dart';

/// The event names the API defines.
abstract final class ApiEventNames {
  /// Live today. Data: the four [PointsPolicy] numbers.
  static const String pointsPolicyUpdated = 'points_policy.updated';

  // Planned — the names are final, but the server does not send these yet.
  // Subscribing is harmless: nothing arrives until the backend step lands.

  /// Step 5. Data: an [AccountVerificationRequest].
  static const String verificationRequestUpdated = 'verification_request.updated';

  /// Step 6. Data: a [ModeratorAccount].
  static const String moderatorUpdated = 'moderator.updated';

  /// Step 7. Data: a [PlatformAppearance].
  static const String platformAppearanceUpdated = 'platform_appearance.updated';

  /// Step 10. Data: a [ServiceRequest]. `created` goes to every mechanic when
  /// a job enters the pool; `updated` goes to the job's two parties.
  static const String serviceRequestCreated = 'service_request.created';
  static const String serviceRequestUpdated = 'service_request.updated';

  /// Step 10. Data: a [JobQuote].
  static const String quoteSubmitted = 'quote.submitted';
  static const String quoteUpdated = 'quote.updated';

  /// Step 10. Data: `{requestId, urgency, platformFee, paidAt}`. Admins only.
  static const String paymentCompleted = 'payment.completed';

  /// Step 10. Data: a review. Goes to the mechanic who was rated.
  static const String reviewSubmitted = 'review.submitted';

  /// Step 10 slice 8. Data: a chat message. Goes to the job's two parties.
  static const String chatMessageCreated = 'chat_message.created';
}

/// One `{ "type": "event" }` frame.
class ApiEvent {
  const ApiEvent({required this.name, this.data = const {}, this.at});

  final String name;
  final Map<String, dynamic> data;
  final DateTime? at;
}

/// A text-frame connection. An interface so tests can stand in for a socket.
abstract interface class EventConnection {
  Stream<String> get messages;

  void send(String text);

  Future<void> close([int? code]);

  int? get closeCode;
}

typedef EventConnector = Future<EventConnection> Function(Uri uri);

/// Opens a real WebSocket.
Future<EventConnection> connectEventWebSocket(Uri uri) async {
  final channel = WebSocketChannel.connect(uri);
  await channel.ready;
  return _ChannelConnection(channel);
}

class _ChannelConnection implements EventConnection {
  _ChannelConnection(this._channel);

  final WebSocketChannel _channel;

  @override
  Stream<String> get messages => _channel.stream.where((message) => message is String).cast<String>();

  @override
  void send(String text) => _channel.sink.add(text);

  @override
  Future<void> close([int? code]) async => _channel.sink.close(code);

  @override
  int? get closeCode => _channel.closeCode;
}

enum EventSocketStatus { stopped, connecting, connected, waitingToReconnect }

/// The one event socket per signed-in app.
///
/// Connects to `/api/v1/events`, authenticates with the access token in the
/// first frame, and hands every event to whoever listens for its name. Every
/// close — the platform closes connections after an hour — is followed by a
/// reconnect with backoff (1 s, 2 s, 4 s … 30 s).
///
/// Events sent while disconnected are not queued by the server. [connected]
/// fires on every successful authentication, first or not, and is the signal
/// to re-fetch whatever a screen shows.
class EventSocket {
  EventSocket({
    required ApiEnvironment environment,
    required ApiSession session,
    EventConnector? connector,
    Future<void> Function(Duration delay)? wait,
    this.maxBackoff = const Duration(seconds: 30),
  })  : _environment = environment,
        _session = session,
        _connector = connector ?? connectEventWebSocket,
        _customWait = wait;

  /// The close code the server uses for an authentication failure.
  static const int authCloseCode = 4401;

  static const Set<String> _authCodes = {
    ApiErrorCodes.tokenExpired,
    ApiErrorCodes.tokenInvalid,
    ApiErrorCodes.accountInactive,
    ApiErrorCodes.unauthorized,
    ApiErrorCodes.wrongSurface,
  };

  final ApiEnvironment _environment;
  final ApiSession _session;
  final EventConnector _connector;
  final Future<void> Function(Duration delay)? _customWait;
  final Duration maxBackoff;

  final StreamController<ApiEvent> _events = StreamController<ApiEvent>.broadcast();
  final StreamController<void> _connected = StreamController<void>.broadcast();
  final StreamController<EventSocketStatus> _statusChanges =
      StreamController<EventSocketStatus>.broadcast();

  EventSocketStatus _status = EventSocketStatus.stopped;
  bool _running = false;
  int _generation = 0;
  EventConnection? _connection;
  Timer? _timer;
  Completer<void>? _sleeper;
  StreamSubscription<SessionChange>? _sessionWatch;

  Stream<ApiEvent> get events => _events.stream;

  /// Events named [name].
  Stream<ApiEvent> on(String name) => _events.stream.where((event) => event.name == name);

  /// Fires each time the socket is authenticated.
  Stream<void> get connected => _connected.stream;

  EventSocketStatus get status => _status;

  Stream<EventSocketStatus> get statusChanges => _statusChanges.stream;

  /// Runs while a session is open: starts on sign-in, re-authenticates when
  /// the token is replaced, stops on sign-out.
  void followSession() {
    _sessionWatch ??= _session.changes.listen((change) {
      switch (change.kind) {
        case SessionChangeKind.started:
        case SessionChangeKind.tokenReplaced:
          restart();
        case SessionChangeKind.ended:
          stop();
        case SessionChangeKind.refreshed:
        case SessionChangeKind.accountChanged:
        case SessionChangeKind.forbidden:
          break;
      }
    });
    if (_session.isSignedIn) start();
  }

  void start() {
    if (_running) return;
    _running = true;
    final generation = ++_generation;
    unawaited(_run(generation));
  }

  void restart() {
    stop();
    start();
  }

  void stop() {
    _running = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
    final sleeper = _sleeper;
    _sleeper = null;
    if (sleeper != null && !sleeper.isCompleted) sleeper.complete();
    final connection = _connection;
    _connection = null;
    if (connection != null) unawaited(connection.close(1000).catchError((Object _) {}));
    _setStatus(EventSocketStatus.stopped);
  }

  /// The wait before reconnect attempt [failures] (0-based).
  Duration backoffFor(int failures) {
    final seconds = math.pow(2, math.min(failures, 16)).toInt();
    final delay = Duration(seconds: seconds);
    return delay > maxBackoff ? maxBackoff : delay;
  }

  Future<void> _run(int generation) async {
    var failures = 0;
    var justRefreshed = false;

    while (generation == _generation) {
      final outcome = await _connectOnce(generation);
      if (generation != _generation) return;
      if (outcome.noSession) {
        stop();
        return;
      }
      if (outcome.reachedReady) failures = 0;

      final authFailure = outcome.closeCode == authCloseCode || _authCodes.contains(outcome.errorCode);
      if (authFailure) {
        final current = _session.accessToken;
        if (current == null) {
          stop();
          return;
        }
        if (current != outcome.token) {
          // Refused a token this app no longer holds; the current one is fine.
          justRefreshed = false;
          continue;
        }
        if (outcome.errorCode == ApiErrorCodes.tokenExpired) {
          if (!justRefreshed) {
            try {
              if (!await _session.refresh()) {
                stop();
                return;
              }
              if (generation != _generation) return;
              justRefreshed = true;
              continue;
            } on ApiException {
              // Could not reach the server to refresh; back off and try again.
            }
          }
        } else {
          await _session.end(ApiSession.reasonFor(outcome.errorCode), message: outcome.errorMessage);
          stop();
          return;
        }
      }

      justRefreshed = false;
      final delay = backoffFor(failures++);
      _setStatus(EventSocketStatus.waitingToReconnect);
      await _sleep(delay);
    }
  }

  Future<_Outcome> _connectOnce(int generation) async {
    _setStatus(EventSocketStatus.connecting);
    if (_session.accessToken == null) return const _Outcome.noSession();

    if (_session.accessTokenNearExpiry) {
      try {
        if (!await _session.refresh()) return const _Outcome.noSession();
      } on ApiException {
        return const _Outcome.failed();
      }
      if (generation != _generation) return const _Outcome.failed();
    }

    final token = _session.accessToken;
    if (token == null) return const _Outcome.noSession();

    final EventConnection connection;
    try {
      connection = await _connector(_environment.eventsUri);
    } catch (_) {
      return _Outcome.failed(token: token);
    }
    if (generation != _generation) {
      unawaited(connection.close(1000).catchError((Object _) {}));
      return _Outcome.failed(token: token);
    }
    _connection = connection;

    var ready = false;
    String? errorCode;
    String? errorMessage;
    try {
      // The token goes in the first frame, never in the URL.
      connection.send(jsonEncode({'type': 'auth', 'token': token}));
      await for (final text in connection.messages) {
        if (generation != _generation) break;
        final frame = _decode(text);
        if (frame == null) continue;
        switch (frame['type']) {
          case 'ready':
            ready = true;
            _setStatus(EventSocketStatus.connected);
            if (!_connected.isClosed) _connected.add(null);
          case 'event':
            final name = frame['name'];
            final data = frame['data'];
            final at = frame['at'];
            if (name is String && name.isNotEmpty && !_events.isClosed) {
              _events.add(ApiEvent(
                name: name,
                data: data is Map ? Map<String, dynamic>.from(data) : const {},
                at: at is String ? DateTime.tryParse(at) : null,
              ));
            }
          case 'error':
            final code = frame['code'];
            final message = frame['message'];
            errorCode = code is String ? code : null;
            errorMessage = message is String ? message : null;
        }
      }
    } catch (_) {
      // A dropped connection ends the same way a close does.
    }

    if (identical(_connection, connection)) _connection = null;
    return _Outcome(
      token: token,
      reachedReady: ready,
      closeCode: connection.closeCode,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  static Map<String, dynamic>? _decode(String text) {
    try {
      final decoded = jsonDecode(text);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> _sleep(Duration delay) async {
    final custom = _customWait;
    if (custom != null) return custom(delay);
    final sleeper = Completer<void>();
    _sleeper = sleeper;
    _timer = Timer(delay, () {
      if (!sleeper.isCompleted) sleeper.complete();
    });
    await sleeper.future;
  }

  void _setStatus(EventSocketStatus status) {
    if (_status == status) return;
    _status = status;
    if (!_statusChanges.isClosed) _statusChanges.add(status);
  }

  Future<void> dispose() async {
    stop();
    await _sessionWatch?.cancel();
    _sessionWatch = null;
    await _events.close();
    await _connected.close();
    await _statusChanges.close();
  }
}

class _Outcome {
  const _Outcome({
    required this.token,
    this.reachedReady = false,
    this.closeCode,
    this.errorCode,
    this.errorMessage,
  }) : noSession = false;

  const _Outcome.failed({this.token})
      : reachedReady = false,
        closeCode = null,
        errorCode = null,
        errorMessage = null,
        noSession = false;

  const _Outcome.noSession()
      : token = null,
        reachedReady = false,
        closeCode = null,
        errorCode = null,
        errorMessage = null,
        noSession = true;

  final String? token;
  final bool reachedReady;
  final int? closeCode;
  final String? errorCode;
  final String? errorMessage;
  final bool noSession;
}
