import 'package:http/http.dart' as http;
import 'package:on_go_shared/on_go_shared.dart';

import 'api_client.dart';
import 'api_environment.dart';
import 'api_session.dart';
import 'auth_session_payload.dart';
import 'event_socket.dart';
import 'http_auth_api.dart';
import 'http_jobs_api.dart';
import 'http_pending_apis.dart';
import 'http_platform_apis.dart';
import 'refresh_token_store.dart';

/// Which of the API's unfinished domains a build calls.
///
/// The server answers these routes `501 not_implemented` until their backend
/// step lands, so they are off by default and each app keeps the
/// implementation it already had. Turn one on — when the integration guide
/// says the step is live — with a build flag, not a code change:
///
/// ```sh
/// flutter run --dart-define=ONGO_API_VERIFICATION=true
/// ```
class ApiFeatures {
  const ApiFeatures({this.verification = false, this.moderators = false});

  factory ApiFeatures.fromDefines() => const ApiFeatures(
        verification: bool.fromEnvironment('ONGO_API_VERIFICATION'),
        moderators: bool.fromEnvironment('ONGO_API_MODERATORS'),
      );

  /// Account verification requests and the moderation activity feed (Step 5).
  final bool verification;

  /// The moderator directory and audit log (Step 6).
  final bool moderators;
}

/// One app's connection to the On Go API: the session, the HTTP client, the
/// event socket, and every contract implemented over them.
///
/// Built once at startup and handed to the app's backend seam
/// (`MobileBackend.configure` / `ConsoleBackend.configure`).
class OnGoApi {
  OnGoApi._({
    required this.environment,
    required this.session,
    required this.client,
    required this.events,
    required this.features,
  })  : auth = HttpAuthApi(client: client, session: session),
        pointsPolicy = HttpPointsPolicyApi(client, events: events),
        appearance = HttpPlatformAppearanceApi(client, events: events),
        revenue = HttpPlatformRevenueApi(client, events: events),
        verification = HttpAccountVerificationApi(client, events: events),
        moderators = HttpModeratorDirectoryApi(client, events: events),
        serviceRequests = HttpServiceRequestApi(client, events: events);

  factory OnGoApi({
    required ApiEnvironment environment,
    required AppSurface surface,
    RefreshTokenStore? refreshTokens,
    http.Client? httpClient,
    EventConnector? eventConnector,
    ApiErrorLogger? logger,
    ApiFeatures features = const ApiFeatures(),
  }) {
    final session = ApiSession(surface: surface, refreshTokens: refreshTokens);
    final client = ApiClient(
      environment: environment,
      session: session,
      httpClient: httpClient,
      logger: logger,
    );
    session.attachRefresher((refreshToken) async => AuthSessionPayload.fromJson(
          await client.post(
            ApiEndpoints.refresh,
            // The console's token is the cookie the browser attaches.
            body: refreshToken == null ? const <String, Object?>{} : {'refreshToken': refreshToken},
          ),
        ));
    final events = EventSocket(
      environment: environment,
      session: session,
      connector: eventConnector,
    )..followSession();

    return OnGoApi._(
      environment: environment,
      session: session,
      client: client,
      events: events,
      features: features,
    );
  }

  final ApiEnvironment environment;
  final ApiSession session;
  final ApiClient client;
  final EventSocket events;
  final ApiFeatures features;

  final HttpAuthApi auth;
  final HttpPointsPolicyApi pointsPolicy;
  final HttpPlatformAppearanceApi appearance;
  final HttpPlatformRevenueApi revenue;

  /// The jobs domain: booking, quotes, the match, progress and payment. Live,
  /// and behind no feature flag — the server has served it since Step 10.
  final HttpServiceRequestApi serviceRequests;

  /// Only use when [ApiFeatures.verification] is on.
  final HttpAccountVerificationApi verification;

  /// Only use when [ApiFeatures.moderators] is on.
  final HttpModeratorDirectoryApi moderators;

  Future<void> close() async {
    await events.dispose();
    client.close();
    await session.close();
  }
}
