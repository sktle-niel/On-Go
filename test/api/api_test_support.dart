import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:on_go_api/on_go_api.dart';
import 'package:on_go_shared/on_go_shared.dart';

/// A stand-in for the On Go API: routes by method and path, records every
/// request. Responses follow the shapes in the integration guide.
class FakeApiServer {
  final List<http.Request> requests = [];
  final Map<String, FutureOr<http.Response> Function(http.Request request)> _routes = {};

  void on(String method, String path, FutureOr<http.Response> Function(http.Request request) handler) =>
      _routes['$method $path'] = handler;

  int count(String method, String path) =>
      requests.where((request) => request.method == method && request.url.path == path).length;

  List<http.Request> sentTo(String method, String path) =>
      requests.where((request) => request.method == method && request.url.path == path).toList();

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    final handler = _routes['${request.method} ${request.url.path}'];
    if (handler == null) return apiError(404, 'not_found', 'No such route.');
    return handler(request);
  });
}

const ApiEnvironment testEnvironment = ApiEnvironment(
  baseUrl: 'https://api.test',
  requestTimeout: Duration(seconds: 5),
);

http.Response apiJson(int status, Object? body) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

http.Response apiError(
  int status,
  String code,
  String message, {
  List<Map<String, String>>? details,
  String requestId = 'req-test-0001',
}) =>
    apiJson(status, {
      'error': {
        'code': code,
        'message': message,
        'details': ?details,
        'requestId': requestId,
      },
    });

http.Response noContent([int status = 204]) => http.Response('', status);

Map<String, dynamic> bodyOf(http.Request request) =>
    Map<String, dynamic>.from(jsonDecode(request.body) as Map);

/// An `AuthSession` body.
Map<String, dynamic> sessionBody({
  String access = 'access-1',
  String? refresh = 'refresh-1',
  String role = 'client',
  String email = 'juan@example.com',
  String name = 'Juan Dela Cruz',
  bool allPermissions = false,
}) =>
    {
      'user': {
        'accountId': '68d136b9-0000-4000-8000-000000000001',
        'displayName': name,
        'email': email,
        'role': role,
      },
      'permissions': {
        'canApprove': allPermissions,
        'canReject': allPermissions,
        'canEscalate': allPermissions,
        'canChangeBackground': allPermissions,
      },
      'accessToken': access,
      'tokenType': 'Bearer',
      'expiresIn': 600,
      'refreshToken': ?refresh,
    };

/// A connector that never connects, for tests that are not about the socket.
Future<EventConnection> neverConnect(Uri uri) => Completer<EventConnection>().future;

OnGoApi testApi(
  FakeApiServer server, {
  AppSurface surface = AppSurface.mobile,
  RefreshTokenStore? store,
  EventConnector? connector,
}) =>
    OnGoApi(
      environment: testEnvironment,
      surface: surface,
      refreshTokens: surface == AppSurface.mobile ? (store ?? InMemoryRefreshTokenStore()) : null,
      httpClient: server.client,
      eventConnector: connector ?? neverConnect,
    );

/// Lets queued microtasks and zero-length timers run.
Future<void> settle() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// One side of an event socket, driven by the test as the server.
class FakeConnection implements EventConnection {
  final StreamController<String> _incoming = StreamController<String>();
  final List<Map<String, dynamic>> sent = [];
  int? _closeCode;
  bool closedByClient = false;

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String text) => sent.add(Map<String, dynamic>.from(jsonDecode(text) as Map));

  @override
  Future<void> close([int? code]) async {
    closedByClient = true;
    _closeCode ??= code;
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  @override
  int? get closeCode => _closeCode;

  void serverSends(Map<String, Object?> frame) => _incoming.add(jsonEncode(frame));

  void serverCloses(int code) {
    _closeCode = code;
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }
}

class FakeConnector {
  final List<Uri> uris = [];
  final List<FakeConnection> connections = [];

  Future<EventConnection> call(Uri uri) async {
    uris.add(uri);
    final connection = FakeConnection();
    connections.add(connection);
    return connection;
  }
}
