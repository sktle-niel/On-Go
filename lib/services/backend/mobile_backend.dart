import 'package:on_go_shared/on_go_shared.dart';

import 'local_appearance_service.dart';
import 'local_location_service.dart';
import 'local_points_policy_service.dart';
import 'local_auth_service.dart';
import 'local_revenue_service.dart';
import 'local_verification_service.dart';

export 'package:on_go_shared/on_go_shared.dart';

/// Every call this app makes that leaves the device.
///
/// The mobile app (Client + Mechanic) and the admin console website (Admin +
/// Moderator) are separate applications. Wherever one of them needs something
/// the other owns — a mechanic's account being verified, a payment being
/// booked as platform revenue, the Sign In background an admin uploaded — the
/// call goes through one of the interfaces here and nowhere else.
///
/// The defaults are local, on-device implementations. `MobileApi.install`
/// swaps in the On Go API's at startup for whatever the API serves today, and
/// not one screen changes: they already await Futures and listen to Streams.
/// The ones the API does not serve yet keep their local implementation.
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
    required this.usesApi,
  });

  factory MobileBackend._local() => MobileBackend._(
        auth: LocalAuthService(),
        verification: LocalVerificationService(),
        revenue: LocalRevenueService(),
        appearance: LocalAppearanceService(),
        pointsPolicy: LocalPointsPolicyService(),
        location: LocalLocationService(),
        usesApi: false,
      );

  static MobileBackend _instance = MobileBackend._local();

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

  /// Whether accounts live on the On Go API. When true the server owns
  /// passwords, registration and resets, and the screens call [auth] for
  /// them; when false the local account stores do, as they always have.
  final bool usesApi;

  /// Replaces some or all of the implementations. Call it once, before
  /// `runApp`; each argument left null keeps the implementation it already had.
  static void configure({
    AuthApi? auth,
    AccountVerificationApi? verification,
    PlatformRevenueApi? revenue,
    PlatformAppearanceApi? appearance,
    PointsPolicyApi? pointsPolicy,
    LocationApi? location,
    bool? usesApi,
  }) {
    _instance = MobileBackend._(
      auth: auth ?? _instance.auth,
      verification: verification ?? _instance.verification,
      revenue: revenue ?? _instance.revenue,
      appearance: appearance ?? _instance.appearance,
      pointsPolicy: pointsPolicy ?? _instance.pointsPolicy,
      location: location ?? _instance.location,
      usesApi: usesApi ?? _instance.usesApi,
    );
  }

  /// Back to the local implementations. For tests.
  static void debugReset() => _instance = MobileBackend._local();
}
