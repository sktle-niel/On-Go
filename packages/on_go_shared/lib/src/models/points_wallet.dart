import 'json.dart';

/// Why points moved. The wire spelling is the name the mobile app's own
/// wallet already used for each kind.
enum PointsLedgerKind {
  /// A client finished and paid for a job.
  clientJobCompleted('clientJobCompleted'),

  /// A mechanic was paid for a job.
  mechanicJobCompleted('mechanicJobCompleted'),

  /// A client spent points on a priority fee.
  clientPaidSurcharge('clientPaidSurcharge'),

  /// A mechanic converted points to balance.
  mechanicConvertedToBalance('mechanicConvertedToBalance');

  const PointsLedgerKind(this.wireName);

  final String wireName;

  static PointsLedgerKind fromWire(String value) => PointsLedgerKind.values.firstWhere(
        (kind) => kind.wireName == value,
        orElse: () => PointsLedgerKind.clientJobCompleted,
      );
}

/// One movement of points, in or out. The server's ledger only ever grows.
class PointsLedgerEntry {
  final String id;
  final PointsLedgerKind kind;

  /// Signed: positive earns, negative spends.
  final double points;

  /// The peso side of a conversion or of a fee paid with points; null otherwise.
  final double? pesos;

  final String note;

  /// The job the points came from, when there was one.
  final String? requestId;

  final DateTime at;

  const PointsLedgerEntry({
    required this.id,
    required this.kind,
    required this.points,
    required this.at,
    this.pesos,
    this.note = '',
    this.requestId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.wireName,
        'points': points,
        'pesos': pesos,
        'note': note,
        'requestId': requestId,
        'at': writeDate(at),
      };

  factory PointsLedgerEntry.fromJson(Map<String, dynamic> json) => PointsLedgerEntry(
        id: readString(json['id']),
        kind: PointsLedgerKind.fromWire(readString(json['kind'])),
        points: readDouble(json['points']),
        pesos: readDoubleOrNull(json['pesos']),
        note: readString(json['note']),
        requestId: readStringOrNull(json['requestId']),
        at: readDate(json['at']),
      );
}

/// The signed-in account's points and, for a mechanic, what they are owed.
///
/// Every figure is the server's. [balance] sums the whole ledger, not only the
/// [entries] returned with it.
class PointsWallet {
  /// Points the account can spend now.
  final double balance;

  /// Mechanic: pesos from paid jobs. Zero for a client.
  final double earnings;

  /// Mechanic: pesos added to the balance by converting points.
  final double convertedPesos;

  /// Mechanic: [earnings] plus [convertedPesos].
  final double availableBalance;

  /// Newest first, at most 200.
  final List<PointsLedgerEntry> entries;

  const PointsWallet({
    this.balance = 0,
    this.earnings = 0,
    this.convertedPesos = 0,
    this.availableBalance = 0,
    this.entries = const [],
  });

  Map<String, dynamic> toJson() => {
        'balance': balance,
        'earnings': earnings,
        'convertedPesos': convertedPesos,
        'availableBalance': availableBalance,
        'entries': entries.map((entry) => entry.toJson()).toList(),
      };

  factory PointsWallet.fromJson(Map<String, dynamic> json) => PointsWallet(
        balance: readDouble(json['balance']),
        earnings: readDouble(json['earnings']),
        convertedPesos: readDouble(json['convertedPesos']),
        availableBalance: readDouble(json['availableBalance']),
        entries: readObjectList(json['entries'])
            .map(PointsLedgerEntry.fromJson)
            .toList(growable: false),
      );
}
