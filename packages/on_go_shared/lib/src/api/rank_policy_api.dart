import '../models/mechanic_rank.dart';

/// The mechanic ranks' requirements and points multipliers: set in the
/// console, obeyed by the mobile app — the same shape as [PointsPolicyApi].
///
/// NOT IN THE API CONTRACT YET. No route stores these settings, so both apps
/// back this interface with a local implementation and there is no entry for
/// it in [ApiEndpoints]. When the backend adds them, an HTTP implementation
/// replaces the local ones and no screen changes.
abstract interface class RankPolicyApi {
  /// The ranks in force right now.
  Future<RankPolicy> fetch();

  /// The current ranks, then every change.
  Stream<RankPolicy> watch();

  /// Replaces the ranks. Console only, and only for an admin.
  Future<RankPolicy> update(RankPolicy policy);
}
