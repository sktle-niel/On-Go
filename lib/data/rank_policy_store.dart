import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/backend/mobile_backend.dart';

/// The mechanic ranks' requirements and multipliers, cached on this device —
/// the [RankPolicy] counterpart of `PointsPolicyStore`.
///
/// Settling a payment is synchronous, so the multiplier it applies is read
/// from [current] here rather than awaited from [RankPolicyApi].
class RankPolicyStore extends ChangeNotifier {
  RankPolicyStore._internal();
  static final RankPolicyStore instance = RankPolicyStore._internal();

  RankPolicy _current = RankPolicy.defaults;
  StreamSubscription<RankPolicy>? _watch;

  /// The ranks in force — [RankPolicy.defaults] until an update arrives.
  RankPolicy get current => _current;

  /// Starts following the ranks. Safe to call before `runApp`; never waits on
  /// the network, and a failure leaves the ranks in place.
  Future<void> load() async {
    await _watch?.cancel();
    _watch = MobileBackend.instance.rankPolicy.watch().listen(
          _apply,
          onError: (Object _) {
            // Keep the ranks we already have.
          },
        );
  }

  void _apply(RankPolicy policy) {
    if (policy == _current || !policy.isValid) return;
    _current = policy;
    notifyListeners();
  }

  /// Test hook — swaps the ranks in without a backend.
  @visibleForTesting
  void debugSet(RankPolicy policy) => _apply(policy);

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }
}
