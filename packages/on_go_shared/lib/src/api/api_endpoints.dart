/// The agreed REST shape of the future backend, in one place.
///
/// This is a specification, not an implementation: no client, no transport, no
/// server. It exists so the mobile app and the console cannot drift apart on
/// what a route is called before either of them can call it, and so the
/// eventual server has one list to implement against.
///
/// Every path below has a counterpart method on one of the interfaces in this
/// directory; the doc on each constant names it.
class ApiEndpoints {
  ApiEndpoints._();

  /// Version prefix. Bump this rather than changing a path in place.
  static const String version = 'v1';

  static const String _root = '/api/$version';

  // ---------------------------------------------------------------- auth ---

  /// POST — `AuthApi.signIn`.
  static const String signIn = '$_root/auth/sign-in';

  /// POST — `AuthApi.signOut`.
  static const String signOut = '$_root/auth/sign-out';

  /// POST — `AuthApi.changePassword`.
  static const String changePassword = '$_root/auth/password';

  /// POST — `AuthApi.resetPassword`.
  static const String resetPassword = '$_root/auth/password/reset';

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
  static const String pointsPolicy = '/platform/points-policy';

  // -------------------------------------------------------------- location ---

  /// POST — `LocationApi.reportLocation`.
  static const String locations = '$_root/locations';

  /// GET — `LocationApi.fetchLastKnown`.
  static String userLocation(String userId) => '$_root/users/$userId/location';

  /// GET — `LocationApi.findNearbyJobIds`. Takes `radiusKm` as a query
  /// parameter; the mechanic's position comes from their stored location.
  static String nearbyJobs(String mechanicId) => '$_root/mechanics/$mechanicId/nearby-jobs';

  // --------------------------------------------------------------- streams ---

  /// The live channel behind every `watch*` method. One socket carrying
  /// change events for whatever the caller is subscribed to, rather than a
  /// socket per screen.
  static const String events = '$_root/events';
}
