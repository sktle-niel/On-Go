import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/backend/mobile_backend.dart';

/// Each urgency level's additional charge and completion time, cached on this
/// device — the [UrgencyPolicy] counterpart of `PointsPolicyStore`.
///
/// Pricing a new job and working out its deadline happen synchronously, so
/// they read [current] here rather than awaiting [UrgencyPolicyApi]. It is the
/// ONLY place the app reads these terms from.
class UrgencyPolicyStore extends ChangeNotifier {
  UrgencyPolicyStore._internal();
  static final UrgencyPolicyStore instance = UrgencyPolicyStore._internal();

  UrgencyPolicy _current = UrgencyPolicy.defaults;
  StreamSubscription<UrgencyPolicy>? _watch;

  /// The terms in force — [UrgencyPolicy.defaults] until an update arrives,
  /// never null.
  UrgencyPolicy get current => _current;

  /// Starts following the terms. Safe to call before `runApp`; never waits on
  /// the network, and a failure leaves the terms in place.
  Future<void> load() async {
    await _watch?.cancel();
    _watch = MobileBackend.instance.urgencyPolicy.watch().listen(
          _apply,
          onError: (Object _) {
            // Keep the terms we already have.
          },
        );
  }

  void _apply(UrgencyPolicy policy) {
    if (policy == _current || !policy.isValid) return;
    _current = policy;
    notifyListeners();
  }

  /// Test hook — swaps the terms in without a backend.
  @visibleForTesting
  void debugSet(UrgencyPolicy policy) => _apply(policy);

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }
}
