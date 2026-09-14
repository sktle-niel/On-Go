import 'package:on_go_shared/on_go_shared.dart';

/// Which backend an app build talks to.
enum BackendMode {
  /// The On Go API at [ApiEnvironment.baseUrl].
  api,

  /// The on-device implementations the apps shipped with before the API
  /// existed. For offline demos and UI work; nothing leaves the device.
  local,
}

/// Where the On Go API is, and how long to wait for it.
///
/// The one place a base URL is written down. Every service builds its URLs
/// from this, so moving from staging to production is a build flag, not an
/// edit:
///
/// ```sh
/// flutter run --dart-define=ONGO_API_BASE_URL=https://api.example.com
/// flutter run --dart-define=ONGO_BACKEND=local   # no network at all
/// ```
class ApiEnvironment {
  const ApiEnvironment({
    required this.baseUrl,
    this.requestTimeout = const Duration(seconds: 20),
  });

  /// The staging deployment (Google Cloud Run, Singapore).
  static const String stagingBaseUrl =
      'https://ongo-api-618821603306.asia-southeast1.run.app';

  static const ApiEnvironment staging = ApiEnvironment(baseUrl: stagingBaseUrl);

  /// The environment this build was compiled for: `ONGO_API_BASE_URL`, or
  /// staging when it was not given.
  factory ApiEnvironment.fromDefines() => const ApiEnvironment(
        baseUrl: String.fromEnvironment('ONGO_API_BASE_URL', defaultValue: stagingBaseUrl),
      );

  /// `ONGO_BACKEND=local` for the on-device implementations; the API otherwise.
  static BackendMode backendModeFromDefines() =>
      const String.fromEnvironment('ONGO_BACKEND', defaultValue: 'api') == 'local'
          ? BackendMode.local
          : BackendMode.api;

  /// Scheme and host, with no trailing slash and no `/api/v1` — the paths in
  /// [ApiEndpoints] carry their own prefix.
  final String baseUrl;

  /// How long one request may take. The staging service scales to zero and its
  /// first answer after a quiet spell takes 2–5 s, so this stays well above 10 s.
  final Duration requestTimeout;

  /// [path] (from [ApiEndpoints]) on this server, with [query] when given.
  Uri uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    final prefix = base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path;
    return base.replace(
      path: '$prefix$path',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  /// The event socket: `wss://…/api/v1/events` (`ws://` against a plain-http
  /// local server).
  Uri get eventsUri {
    final http = uri(ApiEndpoints.events);
    return http.replace(scheme: http.scheme == 'http' ? 'ws' : 'wss');
  }
}
