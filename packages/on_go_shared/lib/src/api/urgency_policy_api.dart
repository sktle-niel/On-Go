import '../models/urgency_policy.dart';

/// Each urgency level's additional charge and completion time: set in the
/// console, obeyed by the mobile app — the same shape as [PointsPolicyApi].
///
/// NOT IN THE API CONTRACT YET. The On Go API's points policy stores only the
/// points, and no route stores these values, so both apps back this interface
/// with a local implementation and there is no entry for it in
/// [ApiEndpoints]. When the backend adds them, an HTTP implementation replaces
/// the local ones and no screen changes.
abstract interface class UrgencyPolicyApi {
  /// The terms in force right now.
  Future<UrgencyPolicy> fetch();

  /// The current terms, then every change.
  Stream<UrgencyPolicy> watch();

  /// Replaces the terms. Console only, and only for an admin.
  Future<UrgencyPolicy> update(UrgencyPolicy policy);
}
