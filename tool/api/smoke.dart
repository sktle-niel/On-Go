// Read-only checks against a live On Go API: no credentials, no accounts,
// nothing written. Confirms the parts of the contract that can be seen without
// signing in — public reads, the error envelope, and the event socket's
// authentication handshake.
//
//   dart run tool/api/smoke.dart [base URL]
//
// Defaults to staging. Exits 1 if any check fails.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:on_go_api/on_go_api.dart';
import 'package:on_go_shared/on_go_shared.dart';

Future<void> main(List<String> args) async {
  final environment = ApiEnvironment(
    baseUrl: args.isNotEmpty ? args.first : ApiEnvironment.stagingBaseUrl,
  );
  // No session: every check here is one an anonymous caller can make.
  final client = ApiClient(
    environment: environment,
    session: ApiSession(surface: AppSurface.console),
    httpClient: http.Client(),
  );
  stdout.writeln('On Go API smoke checks against ${environment.baseUrl}\n');

  var failures = 0;
  Future<void> check(String name, Future<String> Function() run) async {
    final stopwatch = Stopwatch()..start();
    try {
      final detail = await run();
      stdout.writeln('PASS  $name  (${stopwatch.elapsedMilliseconds} ms)\n      $detail');
    } catch (error) {
      failures++;
      stdout.writeln('FAIL  $name  (${stopwatch.elapsedMilliseconds} ms)\n      $error');
    }
  }

  Future<String> expectError(Future<Object?> call, int status) async {
    try {
      await call;
    } on ApiException catch (error) {
      if (error.statusCode != status || error.code == null || error.requestId == null) rethrow;
      return 'code=${error.code} kind=${error.kind.name} requestId=${error.requestId} message="${error.message}"';
    }
    throw StateError('expected HTTP $status');
  }

  await check('GET /health/ready', () async => jsonEncode(await client.get(ApiEndpoints.healthReady)));

  await check('GET /api/v1/platform/points-policy (public)', () async {
    final policy = PointsPolicy.fromJson(responseObject(await client.get(ApiEndpoints.pointsPolicy)));
    return jsonEncode(policy.toJson());
  });

  await check('GET /api/v1/platform/appearance (public)', () async {
    final appearance = PlatformAppearance.fromJson(responseObject(await client.get(ApiEndpoints.appearance)));
    return 'authBackgroundUrl=${appearance.authBackgroundUrl} updatedAt=${appearance.updatedAt}';
  });

  await check('GET /api/v1/auth/me without a token → 401 envelope',
      () => expectError(client.get(ApiEndpoints.me), 401));

  await check('GET /api/v1/revenue/summary without a token → 401 envelope',
      () => expectError(client.get(ApiEndpoints.revenueSummary), 401));

  await check('WebSocket /api/v1/events: a bad token → error frame, close 4401', () async {
    final connection = await connectEventWebSocket(environment.eventsUri).timeout(const Duration(seconds: 20));
    connection.send(jsonEncode({'type': 'auth', 'token': 'not-a-real-token'}));
    final frames = <String>[];
    await for (final frame in connection.messages.timeout(const Duration(seconds: 20))) {
      frames.add(frame);
    }
    if (connection.closeCode != EventSocket.authCloseCode) {
      throw StateError('closed with ${connection.closeCode}; frames: $frames');
    }
    return 'frames=$frames close=${connection.closeCode}';
  });

  client.close();
  stdout.writeln('\n${failures == 0 ? 'All checks passed.' : '$failures check(s) failed.'}');
  exitCode = failures == 0 ? 0 : 1;
}
