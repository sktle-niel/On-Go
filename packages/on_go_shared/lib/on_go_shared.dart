/// Everything the On Go mobile app and the On Go admin console agree on.
///
/// The product ships as two front ends:
///
/// * **Mobile app** (`/lib`, Flutter, Android + iOS) — Client and Mechanic.
/// * **Console website** (the `on_go_console` repository, Flutter web) —
///   Admin and Moderator.
///
/// They are separate applications that will meet at a backend. This package is
/// that meeting point, written down ahead of the backend: the DTOs that will
/// cross the wire, and the interfaces each side codes against. Nothing here
/// knows about HTTP, Flutter, or a database, so both apps — and the eventual
/// server — can depend on it.
///
/// Adding an operation? Put the DTO in `src/models`, the method on the right
/// interface in `src/api`, and its route in [ApiEndpoints]. Then implement it
/// locally on each side. That order keeps the two apps from drifting.
library;

export 'src/api/account_verification_api.dart';
export 'src/api/api_endpoints.dart';
export 'src/api/api_exception.dart';
export 'src/api/auth_api.dart';
export 'src/api/leaderboard_apis.dart';
export 'src/api/location_api.dart';
export 'src/api/moderator_directory_api.dart';
export 'src/api/platform_appearance_api.dart';
export 'src/api/platform_revenue_api.dart';
export 'src/api/points_policy_api.dart';
export 'src/api/rank_policy_api.dart';
export 'src/api/urgency_policy_api.dart';
export 'src/models/account_verification_request.dart';
export 'src/models/auth.dart';
export 'src/models/credential_document.dart';
export 'src/models/enums.dart';
export 'src/models/geo_location.dart';
export 'src/models/job_evaluation.dart';
export 'src/models/leaderboard.dart';
export 'src/models/mechanic_performance.dart';
export 'src/models/point_transaction.dart';
export 'src/models/mechanic_rank.dart';
export 'src/models/place.dart';
export 'src/models/moderator_account.dart';
export 'src/models/platform_appearance.dart';
export 'src/models/platform_revenue.dart';
export 'src/models/points_policy.dart';
export 'src/models/urgency_policy.dart';
