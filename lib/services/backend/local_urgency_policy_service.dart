import 'dart:async';

import 'package:on_go_shared/on_go_shared.dart';

/// The mobile app's read-only end of the urgency terms: each level's
/// additional charge and completion time.
///
/// The admin sets them in the console, but the On Go API does not store them
/// yet (see [UrgencyPolicyApi]), so there is nothing to deliver an admin's
/// change to a phone. Until there is, [fetch] and [watch] report
/// [UrgencyPolicy.defaults] — Normal ₱10 with no time limit, Urgent ₱50 within
/// 3 days, Emergency ₱100 within 12 hours — and pricing, deadlines and the ETA
/// cap all follow those.
///
/// [update] refuses: setting the terms is a console action.
class LocalUrgencyPolicyService implements UrgencyPolicyApi {
  LocalUrgencyPolicyService({UrgencyPolicy? policy}) : _policy = policy ?? UrgencyPolicy.defaults;

  final UrgencyPolicy _policy;

  @override
  Future<UrgencyPolicy> fetch() async => _policy;

  @override
  Stream<UrgencyPolicy> watch() {
    late StreamController<UrgencyPolicy> controller;
    controller = StreamController<UrgencyPolicy>.broadcast(
      onListen: () => controller.add(_policy),
    );
    return controller.stream;
  }

  @override
  Future<UrgencyPolicy> update(UrgencyPolicy policy) {
    throw const ApiException(
      ApiErrorKind.forbidden,
      'Urgency levels are configured in the On Go admin console.',
    );
  }
}
