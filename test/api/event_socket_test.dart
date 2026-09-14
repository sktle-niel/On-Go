import 'package:flutter_test/flutter_test.dart';
import 'package:on_go_api/on_go_api.dart';
import 'package:on_go_shared/on_go_shared.dart';

import 'api_test_support.dart';

void main() {
  late ApiSession session;
  late FakeConnector connector;
  late List<Duration> waits;
  late EventSocket socket;
  late int refreshes;

  setUp(() async {
    refreshes = 0;
    session = ApiSession(surface: AppSurface.mobile, refreshTokens: InMemoryRefreshTokenStore())
      ..attachRefresher((_) async {
        refreshes++;
        return AuthSessionPayload.fromJson(sessionBody(access: 'access-${refreshes + 1}', refresh: 'r$refreshes'));
      });
    await session.adopt(AuthSessionPayload.fromJson(sessionBody()), newSession: true);
    connector = FakeConnector();
    waits = [];
    socket = EventSocket(
      environment: testEnvironment,
      session: session,
      connector: connector.call,
      wait: (delay) async => waits.add(delay),
    );
  });

  tearDown(() => socket.dispose());

  test('authenticates in the first frame; the token is never in the URL', () async {
    socket.start();
    await settle();

    final connection = connector.connections.single;
    expect(connector.uris.single.toString(), 'wss://api.test/api/v1/events');
    expect(connection.sent.first, {'type': 'auth', 'token': 'access-1'});
  });

  test('ready announces the connection, and events reach only their own listeners', () async {
    final connected = <void>[];
    final policyEvents = <ApiEvent>[];
    socket.connected.listen(connected.add);
    socket.on(ApiEventNames.pointsPolicyUpdated).listen(policyEvents.add);
    socket.start();
    await settle();

    connector.connections.single
      ..serverSends({'type': 'ready', 'user': {'accountId': 'x', 'displayName': 'Juan', 'email': 'j@x', 'role': 'client'}})
      ..serverSends({'type': 'event', 'name': 'moderator.updated', 'data': {'id': 'm1'}})
      ..serverSends({'type': 'pong'})
      ..serverSends({'type': 'event', 'name': 'points_policy.updated', 'data': {'clientNormal': 2}, 'at': '2026-09-14T04:38:28.123Z'});
    await settle();

    expect(connected, hasLength(1));
    expect(socket.status, EventSocketStatus.connected);
    expect(policyEvents.single.data, {'clientNormal': 2});
    expect(policyEvents.single.at, DateTime.utc(2026, 9, 14, 4, 38, 28, 123));
  });

  test('every close reconnects with backoff, and a successful connection resets it', () async {
    socket.start();
    await settle();

    for (var i = 0; i < 3; i++) {
      connector.connections.last.serverCloses(1006);
      await settle();
    }
    expect(waits, const [Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4)]);
    expect(connector.connections, hasLength(4));

    connector.connections.last
      ..serverSends({'type': 'ready', 'user': {}})
      ..serverCloses(1000);
    await settle();

    expect(waits.last, const Duration(seconds: 1));
    expect(connector.connections.last.sent.first['token'], 'access-1', reason: 're-authenticates each time');
  });

  test('backoff tops out at 30 seconds', () {
    expect(socket.backoffFor(4), const Duration(seconds: 16));
    expect(socket.backoffFor(5), const Duration(seconds: 30));
    expect(socket.backoffFor(40), const Duration(seconds: 30));
  });

  test('token_expired: refresh, then reconnect with the new token', () async {
    socket.start();
    await settle();

    connector.connections.single
      ..serverSends({'type': 'error', 'code': 'token_expired', 'message': 'expired'})
      ..serverCloses(EventSocket.authCloseCode);
    await settle();

    expect(refreshes, 1);
    expect(connector.connections, hasLength(2));
    expect(connector.connections.last.sent.first, {'type': 'auth', 'token': 'access-2'});
    expect(waits, isEmpty, reason: 'a refreshed token reconnects straight away');
  });

  test('token_invalid: the session ends and the socket stops', () async {
    final ended = session.changes.firstWhere((change) => change.kind == SessionChangeKind.ended);
    socket.start();
    await settle();

    connector.connections.single
      ..serverSends({'type': 'error', 'code': 'token_invalid', 'message': 'Signed out elsewhere.'})
      ..serverCloses(EventSocket.authCloseCode);
    await settle();

    final change = await ended;
    expect(change.reason, SessionEndReason.invalid);
    expect(change.message, 'Signed out elsewhere.');
    expect(socket.status, EventSocketStatus.stopped);
    expect(connector.connections, hasLength(1));
    expect(refreshes, 0);
  });

  test('a refusal of a token this app has already replaced just reconnects', () async {
    socket.start();
    await settle();
    session.replaceAccessToken('after-password-change', 600);

    connector.connections.single
      ..serverSends({'type': 'error', 'code': 'token_invalid', 'message': 'old token'})
      ..serverCloses(EventSocket.authCloseCode);
    await settle();

    expect(session.isSignedIn, isTrue);
    expect(connector.connections.last.sent.first['token'], 'after-password-change');
  });

  test('follows the session: starts on sign-in, stops on sign-out', () async {
    await session.end(SessionEndReason.signedOut);
    socket.followSession();
    await settle();
    expect(connector.connections, isEmpty);

    await session.adopt(AuthSessionPayload.fromJson(sessionBody()), newSession: true);
    await settle();
    expect(connector.connections, hasLength(1));

    await session.end(SessionEndReason.signedOut);
    await settle();
    expect(connector.connections.single.closedByClient, isTrue);
    expect(socket.status, EventSocketStatus.stopped);
    expect(connector.connections, hasLength(1));
  });
}
