import 'package:flutter/foundation.dart';

/// Why points moved. Adding a way to earn or spend them means adding a value
/// here and a method that writes it — no balance arithmetic changes, because
/// a balance is only ever the sum of the entries.
enum PointsEntryKind {
  /// A client completed a job: points for its urgency.
  clientJobCompleted,

  /// A mechanic was paid for a job: the points for its urgency the client
  /// earned, times the mechanic's rank multiplier.
  mechanicJobCompleted,

  /// A client put points towards a job's additional charge.
  clientPaidSurcharge,

  /// A mechanic turned points into account balance.
  mechanicConvertedToBalance,
}

extension PointsEntryKindLabel on PointsEntryKind {
  String get label {
    switch (this) {
      case PointsEntryKind.clientJobCompleted:
        return 'Job completed';
      case PointsEntryKind.mechanicJobCompleted:
        return 'Job paid';
      case PointsEntryKind.clientPaidSurcharge:
        return 'Paid additional charge';
      case PointsEntryKind.mechanicConvertedToBalance:
        return 'Converted to balance';
    }
  }

  /// Whether this kind adds points. Spending kinds are stored as negative
  /// amounts, so this is only for wording and colour.
  bool get isCredit =>
      this == PointsEntryKind.clientJobCompleted ||
      this == PointsEntryKind.mechanicJobCompleted;
}

/// One movement of points, in or out.
@immutable
class PointsEntry {
  final String id;

  /// Whose points these are — a client's name or a mechanic's, the same key
  /// every other store in this app uses for a person.
  final String owner;

  final PointsEntryKind kind;

  /// Signed: positive earns, negative spends.
  final double points;

  /// The pesos this movement was worth, where it had a peso side — a
  /// converted balance, a fee paid with points. Null for a plain earning.
  final double? pesos;

  /// What it was for, in words, for a history list.
  final String note;

  final DateTime at;

  const PointsEntry({
    required this.id,
    required this.owner,
    required this.kind,
    required this.points,
    required this.note,
    required this.at,
    this.pesos,
  });
}

/// Every point anyone holds, as a ledger rather than a number.
///
/// A balance is the sum of an owner's entries, so it cannot drift from the
/// history that explains it, and a new way to earn or spend points is one more
/// [PointsEntryKind] rather than a new field to keep in step.
///
/// Owners are keyed by name, like credentials and reviews, so a client's
/// balance and a mechanic's live in the same ledger without either needing to
/// know the other exists.
class PointsWalletStore extends ChangeNotifier {
  PointsWalletStore._internal();
  static final PointsWalletStore instance = PointsWalletStore._internal();

  final List<PointsEntry> _entries = [];

  /// [owner]'s movements, newest first.
  List<PointsEntry> entriesFor(String owner) =>
      _entries.where((e) => e.owner == owner).toList().reversed.toList();

  /// The pesos [owner] has turned points into — what their conversions have
  /// added to their account balance. Read from the same entries as
  /// [balanceFor], so the points a conversion takes away and the balance it
  /// adds cannot disagree.
  double convertedPesosFor(String owner) => _entries
      .where((e) => e.owner == owner && e.kind == PointsEntryKind.mechanicConvertedToBalance)
      .fold(0.0, (sum, e) => sum + (e.pesos ?? 0));

  /// What [owner] can spend right now.
  double balanceFor(String owner) => _entries
      .where((e) => e.owner == owner)
      .fold(0.0, (sum, e) => sum + e.points);

  /// Whether [owner] holds at least [points]. The check every spend goes
  /// through, so "not enough points" is decided in one place.
  bool canAfford(String owner, double points) =>
      points <= 0 || balanceFor(owner) + _tolerance >= points;

  /// Rates can be fractional, so a balance can land a hair under what it
  /// should be. A hundredth of a point is not a real shortfall.
  static const double _tolerance = 0.001;

  /// Credits [points] to [owner]. No-op for a non-positive amount, so a rate
  /// configured to zero simply awards nothing rather than writing noise.
  PointsEntry? credit({
    required String owner,
    required PointsEntryKind kind,
    required double points,
    required String note,
    double? pesos,
  }) {
    if (owner.isEmpty || points <= 0) return null;
    return _add(owner: owner, kind: kind, points: points, note: note, pesos: pesos);
  }

  /// Debits [points] from [owner], refusing if they cannot cover it.
  ///
  /// Returns the entry written, or null when the balance is short — the
  /// caller must treat null as "not spent" rather than assuming it worked.
  PointsEntry? debit({
    required String owner,
    required PointsEntryKind kind,
    required double points,
    required String note,
    double? pesos,
  }) {
    if (owner.isEmpty || points <= 0) return null;
    if (!canAfford(owner, points)) return null;
    return _add(owner: owner, kind: kind, points: -points, note: note, pesos: pesos);
  }

  PointsEntry _add({
    required String owner,
    required PointsEntryKind kind,
    required double points,
    required String note,
    double? pesos,
  }) {
    final entry = PointsEntry(
      id: 'pts_${DateTime.now().microsecondsSinceEpoch}_${_entries.length}',
      owner: owner,
      kind: kind,
      points: points,
      note: note,
      pesos: pesos,
      at: DateTime.now(),
    );
    _entries.add(entry);
    notifyListeners();
    return entry;
  }

  /// Test/demo hook — drops every ledger.
  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
