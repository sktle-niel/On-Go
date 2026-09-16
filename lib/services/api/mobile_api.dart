import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:on_go_api/on_go_api.dart';

import '../backend/mobile_backend.dart';
import 'appearance_sync.dart';

export 'package:on_go_api/on_go_api.dart'
    show ApiEnvironment, ApiFeatures, BackendMode, SessionChange, SessionChangeKind, SessionEndReason;

/// The mobile session's refresh token, in the Keychain (iOS) or the
/// Keystore-backed store (Android). The access token is never written
/// anywhere; it lives in [ApiSession] memory.
class SecureRefreshTokenStore implements RefreshTokenStore {
  SecureRefreshTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'ongo_refresh_token';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// Connects this app to the On Go API.
///
/// Everything network-shaped is built here, once, and handed to
/// [MobileBackend] — screens keep calling the same interfaces they always
/// have. What moves to the API is what the API serves today:
///
/// | Contract | Backed by |
/// |---|---|
/// | [AuthApi] | the API (`/auth/*`) |
/// | [PointsPolicyApi] | the API, live over the event socket |
/// | [PlatformAppearanceApi] | the API (read); writes are console-only |
/// | [PlatformRevenueApi] | the API (`POST /payments`) |
/// | [AccountVerificationApi] | local until Step 5 (`ONGO_API_VERIFICATION`) |
/// | [ServiceRequestApi] | the API (`/service-requests/*`) |
/// | [LocationApi] | local — not in the API contract |
///
/// Jobs, quotes, ETA, chat and reviews are not in the contract at all and stay
/// in their stores on the device.
class MobileApi {
  MobileApi._();

  static OnGoApi? _api;
  static AppearanceSync? _appearanceSync;

  /// The live connection, or null in a local build.
  static OnGoApi? get connection => _api;

  /// Installs the API unless the build asked for `ONGO_BACKEND=local`.
  /// Returns whether a stored session may be waiting to be restored.
  static Future<bool> installFromDefines() async {
    if (ApiEnvironment.backendModeFromDefines() == BackendMode.local) return false;
    final api = install();
    return api.session.hasStoredSession();
  }

  static OnGoApi install({
    ApiEnvironment? environment,
    RefreshTokenStore? refreshTokens,
    http.Client? httpClient,
    EventConnector? eventConnector,
    ApiFeatures? features,
  }) {
    final api = OnGoApi(
      environment: environment ?? ApiEnvironment.fromDefines(),
      surface: AppSurface.mobile,
      refreshTokens: refreshTokens ?? SecureRefreshTokenStore(),
      httpClient: httpClient,
      eventConnector: eventConnector,
      logger: _log,
      features: features ?? ApiFeatures.fromDefines(),
    );
    _api = api;
    MobileBackend.configure(
      usesApi: true,
      auth: api.auth,
      pointsPolicy: api.pointsPolicy,
      appearance: api.appearance,
      revenue: api.revenue,
      verification: api.features.verification ? api.verification : null,
      serviceRequests: api.serviceRequests,
    );
    return api;
  }

  /// Starts painting the Sign In background the console publishes. Call after
  /// `AuthBackgroundController.load`, so the cached photo is known first.
  static void startAppearanceSync() {
    final api = _api;
    if (api == null || _appearanceSync != null) return;
    _appearanceSync = AppearanceSync(api: api.appearance)..start();
  }

  /// Session starts and ends. Empty in a local build.
  static Stream<SessionChange> get sessionChanges =>
      _api?.session.changes ?? const Stream<SessionChange>.empty();

  static void _log(String method, String path, ApiException error) {
    // The requestId in here is what links a report to the server log.
    debugPrint('On Go API $method $path failed: $error');
  }

  @visibleForTesting
  static Future<void> debugReset() async {
    _appearanceSync?.stop();
    _appearanceSync = null;
    final api = _api;
    _api = null;
    MobileBackend.debugReset();
    await api?.close();
  }
}

/// Why the user is back at Sign In when they did not sign out.
String sessionEndedMessage(SessionChange change) => switch (change.reason) {
      SessionEndReason.accountInactive => change.message ?? 'This account is no longer active.',
      SessionEndReason.invalid => 'You were signed out. Please sign in again.',
      _ => 'Your session has ended. Please sign in again.',
    };

/// Shown when a stored session could not be checked at launch. The session is
/// kept, so the next launch with a connection picks it up.
const String restoreUnreachableMessage =
    "Couldn't reach On Go to restore your session. Check your connection and try again.";
