import 'package:on_go_shared/on_go_shared.dart';

import 'local_appearance_service.dart';
import 'local_location_service.dart';
import 'local_points_policy_service.dart';
import 'local_auth_service.dart';
import 'local_revenue_service.dart';
import 'local_verification_service.dart';

export 'package:on_go_shared/on_go_shared.dart';

/// Every call this app makes that will one day leave the device.
///
/// The mobile app (Client + Mechanic) and the admin console website (Admin +
/// Moderator) are separate applications. Wherever one of them needs something
/// the other owns — a mechanic's account being verified, a payment being
/// booked as platform revenue, the Sign In background an admin uploaded — the
/// call goes through one of the interfaces here and nowhere else.
///
/// Today those interfaces are backed by local, on-device implementations, so
/// nothing about the Client and Mechanic experience changed when the console
/// moved out. When the backend exists, [configure] swaps in HTTP-backed
/// implementations at startup and not one screen changes: they already await
/// Futures and listen to Streams.
///
/// The console has the mirror image of this file in `on_go_console/lib/src/backend`.
class MobileBackend {
  MobileBackend._({
    required this.auth,
    required this.verification,
    required this.revenue,
    required this.appearance,
    required this.pointsPolicy,
    required this.location,
  });

  static MobileBackend _instance = MobileBackend._(
    auth: LocalAuthService(),
    verification: LocalVerificationService(),
    revenue: LocalRevenueService(),
    appearance: LocalAppearanceService(),
    pointsPolicy: LocalPointsPolicyService(),
    location: LocalLocationService(),
  );

  static MobileBackend get instance => _instance;

  /// Who is signed in on this device.
  final AuthApi auth;

  /// Mechanic account verification — filed here, decided in the console.
  final AccountVerificationApi verification;

  /// Completed client payments, reported for the console's income screens.
  final PlatformRevenueApi revenue;

  /// Branding the console publishes and this app paints.
  final PlatformAppearanceApi appearance;

  /// The points rules the console configures and this app awards by.
  final PointsPolicyApi pointsPolicy;

  /// Where the signed-in user's live location is reported, and — once the
  /// backend exists — where a mechanic's last known location is kept for
  /// nearby-job matching. Reading GPS is not this: that is `LocationService`.
  final LocationApi location;

  /// Replaces some or all of the implementations. Call it once, before
  /// `runApp`, when the API client arrives; each argument left null keeps the
  /// local implementation it already had.
  static void configure({
    AuthApi? auth,
    AccountVerificationApi? verification,
    PlatformRevenueApi? revenue,
    PlatformAppearanceApi? appearance,
    PointsPolicyApi? pointsPolicy,
    LocationApi? location,
  }) {
    _instance = MobileBackend._(
      auth: auth ?? _instance.auth,
      verification: verification ?? _instance.verification,
      revenue: revenue ?? _instance.revenue,
      appearance: appearance ?? _instance.appearance,
      pointsPolicy: pointsPolicy ?? _instance.pointsPolicy,
      location: location ?? _instance.location,
    );
  }
}
