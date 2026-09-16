import 'dart:async';

import 'package:on_go_shared/on_go_shared.dart';

/// The mobile app's read-only end of the mechanic ranks.
///
/// The admin sets requirements and multipliers in the console, but the On Go
/// API does not store them yet (see [RankPolicyApi]), so there is nothing to
/// deliver an admin's change to a phone. Until there is, [fetch] and [watch]
/// report [RankPolicy.defaults], and ranks and point multipliers follow those.
///
/// [update] refuses: setting the ranks is a console action.
class LocalRankPolicyService implements RankPolicyApi {
  LocalRankPolicyService({RankPolicy? policy}) : _policy = policy ?? RankPolicy.defaults;

  final RankPolicy _policy;

  @override
  Future<RankPolicy> fetch() async => _policy;

  @override
  Stream<RankPolicy> watch() {
    late StreamController<RankPolicy> controller;
    controller = StreamController<RankPolicy>.broadcast(
      onListen: () => controller.add(_policy),
    );
    return controller.stream;
  }

  @override
  Future<RankPolicy> update(RankPolicy policy) {
    throw const ApiException(
      ApiErrorKind.forbidden,
      'Mechanic ranks are configured in the On Go admin console.',
    );
  }
}
