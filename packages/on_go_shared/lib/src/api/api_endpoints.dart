/// The REST shape of the On Go API, in one place.
///
/// Paths only — no client, no transport. The routes match the deployed API's
/// OpenAPI document (`/docs/json`); `package:on_go_api` is what calls them. It
/// exists so the mobile app and the console cannot drift apart on what a route
/// is called.
///
/// Every path below has a counterpart method on one of the interfaces in this
/// directory; the doc on each constant names it. The location routes at the
/// bottom are the exception: they are this app's proposal and are not in the
/// API contract yet.
class ApiEndpoints {
  ApiEndpoints._();

  /// Version prefix. Bump this rather than changing a path in place.
  static const String version = 'v1';

  static const String _root = '/api/$version';

  // -------------------------------------------------------------- health ---

  /// GET — the process is up. Not rate-limited.
  static const String healthLive = '/health/live';

  /// GET — the database is reachable; 503 when it is not.
  static const String healthReady = '/health/ready';

  // ---------------------------------------------------------------- auth ---

  /// POST — `AuthApi.signIn`.
  static const String signIn = '$_root/auth/sign-in';

  /// POST — `AuthApi.register`.
  static const String register = '$_root/auth/register';

  /// POST — rotates the refresh token. Called by the session layer, never by
  /// a screen.
  static const String refresh = '$_root/auth/refresh';

  /// POST — `AuthApi.signOut`.
  static const String signOut = '$_root/auth/sign-out';

  /// GET — `AuthApi.fetchCurrentAccount`.
  static const String me = '$_root/auth/me';

  /// POST — `AuthApi.changePassword`.
  static const String changePassword = '$_root/auth/password';

  /// POST — `AuthApi.requestPasswordReset`.
  static const String resetPassword = '$_root/auth/password/reset';

  /// POST — `AuthApi.confirmPasswordReset`.
  static const String resetPasswordConfirm = '$_root/auth/password/reset/confirm';

  // ------------------------------------------------- account verification ---

  /// GET (list, `AccountVerificationApi.listRequests`) and
  /// POST (`AccountVerificationApi.submit`).
  static const String verificationRequests = '$_root/verification-requests';

  /// GET — `AccountVerificationApi.findRequest`.
  static String verificationRequest(String id) => '$verificationRequests/$id';

  /// POST — `AccountVerificationApi.decide`.
  static String verificationDecision(String id) => '$verificationRequests/$id/decision';

  /// GET — `AccountVerificationApi.listActivity`.
  static const String moderationActivity = '$_root/moderation/activity';

  // ------------------------------------------------------------ moderators ---

  /// GET (`ModeratorDirectoryApi.listModerators`) and
  /// POST (`ModeratorDirectoryApi.createModerator`).
  static const String moderators = '$_root/moderators';

  /// DELETE — `ModeratorDirectoryApi.removeModerator`.
  static String moderator(String id) => '$moderators/$id';

  /// PUT — `ModeratorDirectoryApi.updatePermissions`.
  static String moderatorPermissions(String id) => '$moderators/$id/permissions';

  /// PATCH — `ModeratorDirectoryApi.updateProfile`.
  static String moderatorProfile(String id) => '$moderators/$id/profile';

  /// GET — `ModeratorDirectoryApi.listAuditLog`.
  static const String auditLog = '$_root/audit-log';

  // --------------------------------------------------------------- revenue ---

  /// POST — `PlatformRevenueApi.reportCompletedPayment`.
  static const String payments = '$_root/payments';

  /// GET — `PlatformRevenueApi.fetchSummary`.
  static const String revenueSummary = '$_root/revenue/summary';

  // ------------------------------------------------------------ appearance ---

  /// GET (`PlatformAppearanceApi.fetch`), PUT
  /// (`PlatformAppearanceApi.publishBackground`) and DELETE
  /// (`PlatformAppearanceApi.clearBackground`).
  static const String appearance = '$_root/platform/appearance';

  // ---------------------------------------------------------------- points ---

  /// GET (`PointsPolicyApi.fetch`) and PUT (`PointsPolicyApi.update`).
  static const String pointsPolicy = '$_root/platform/points-policy';

  // -------------------------------------------------------------- location ---
  // Not in the API contract yet — proposed by this app, see `LocationApi`.

  /// POST — `LocationApi.reportLocation`.
  static const String locations = '$_root/locations';

  /// GET — `LocationApi.fetchLastKnown`.
  static String userLocation(String userId) => '$_root/users/$userId/location';

  /// GET — `LocationApi.findNearbyJobIds`. Takes `radiusKm` as a query
  /// parameter; the mechanic's position comes from their stored location.
  static String nearbyJobs(String mechanicId) => '$_root/mechanics/$mechanicId/nearby-jobs';

  // --------------------------------------------------------------- streams ---

  /// The live channel behind every `watch*` method (WebSocket). One socket
  /// carrying change events for whatever the caller may see, rather than a
  /// socket per screen. The access token goes in the first frame, never here.
  static const String events = '$_root/events';
}
