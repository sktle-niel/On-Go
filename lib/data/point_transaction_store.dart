import 'package:flutter/foundation.dart';

import '../services/backend/mobile_backend.dart';
import '../services/local/record_box.dart';

/// Every award of reward points to a mechanic, with the factors behind it.
///
/// The audit trail of the points economy. [PointsWalletStore] holds balances;
/// this says why each award was the size it was. Only the admin reads it —
/// mechanics are never shown per-job points. Saved between launches.
class PointTransactionStore extends ChangeNotifier {
  PointTransactionStore._internal();
  static final PointTransactionStore instance = PointTransactionStore._internal();

  RecordWriter _writer = RecordWriter(const SharedPreferencesRecordBox('point_transactions'));
  final Map<String, PointTransaction> _byId = {};

  Future<void> load() async {
    for (final json in await _writer.box.load()) {
      final transaction = PointTransaction.fromJson(json);
      if (transaction.id.isEmpty) continue;
      _byId.putIfAbsent(transaction.id, () => transaction);
    }
    notifyListeners();
  }

  List<PointTransaction> get all => List.unmodifiable(_byId.values);

  List<PointTransaction> forMechanic(String mechanicId) =>
      _byId.values.where((t) => t.mechanicId == mechanicId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Records [transaction]. False, and nothing recorded, when its source has
  /// already paid out — one transaction per source.
  bool record(PointTransaction transaction) {
    if (_byId.containsKey(transaction.id)) return false;
    _byId[transaction.id] = transaction;
    _writer.write([for (final t in _byId.values) t.toJson()]);
    notifyListeners();
    return true;
  }

  @visibleForTesting
  void debugUse(RecordBox box) {
    _writer = RecordWriter(box);
    _byId.clear();
    notifyListeners();
  }
}
