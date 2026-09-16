import 'json.dart';
import 'mechanic_rank.dart';

/// What gave a mechanic reward points.
enum PointTransactionSource {
  jobCompleted('job_completed', 'Completed job');

  const PointTransactionSource(this.wireName, this.label);

  final String wireName;
  final String label;

  static PointTransactionSource fromWire(String value) =>
      values.firstWhere((source) => source.wireName == value, orElse: () => PointTransactionSource.jobCompleted);
}

/// One award of reward points to a mechanic, with every factor that produced
/// it — `point_transactions` in a backend.
///
/// The audit trail behind a points balance: base 20 × rank x2 × seasonal x1.1
/// = 44 reads as exactly that, not as an unexplained 44. Stored when the
/// points are awarded and never recalculated, because points turn into money.
class PointTransaction {
  const PointTransaction({
    required this.id,
    required this.mechanicId,
    required this.sourceType,
    required this.sourceId,
    required this.basePoints,
    required this.rank,
    required this.rankMultiplier,
    required this.leaderboardMultiplier,
    required this.effectiveMultiplier,
    required this.finalPoints,
    required this.createdAt,
    this.bonusMultiplier = 0,
    this.cap,
    this.seasonId,
    this.voidedAt,
    this.voidReason,
  });

  /// Points for a completed job, from the multiplier in force when it was paid.
  factory PointTransaction.forJob({
    required String jobId,
    required String mechanicId,
    required double basePoints,
    required PointsMultiplier multiplier,
    required DateTime at,
    String? seasonId,
  }) =>
      PointTransaction(
        id: idFor(PointTransactionSource.jobCompleted, jobId, mechanicId),
        mechanicId: mechanicId,
        sourceType: PointTransactionSource.jobCompleted,
        sourceId: jobId,
        basePoints: basePoints,
        rank: multiplier.rank,
        rankMultiplier: multiplier.rankMultiplier,
        bonusMultiplier: multiplier.bonusTotal,
        leaderboardMultiplier: multiplier.leaderboardMultiplier,
        cap: multiplier.cap,
        effectiveMultiplier: multiplier.total,
        finalPoints: multiplier.apply(basePoints),
        createdAt: at,
        seasonId: seasonId,
      );

  /// One transaction per source per mechanic, so the same job cannot pay out
  /// twice.
  static String idFor(PointTransactionSource source, String sourceId, String mechanicId) =>
      '${source.wireName}:$sourceId:$mechanicId';

  final String id;
  final String mechanicId;
  final PointTransactionSource sourceType;
  final String sourceId;
  final double basePoints;
  final MechanicRank rank;
  final double rankMultiplier;

  /// Additive bonuses on top of the rank multiplier.
  final double bonusMultiplier;

  /// The seasonal leaderboard multiplier; 1 without one.
  final double leaderboardMultiplier;

  /// The cap in force, if any.
  final double? cap;

  /// What was actually applied, after the cap.
  final double effectiveMultiplier;
  final double finalPoints;
  final DateTime createdAt;

  /// The season running when it was awarded, if any.
  final String? seasonId;
  final DateTime? voidedAt;
  final String? voidReason;

  bool get wasCapped {
    final limit = cap;
    return limit != null && (rankMultiplier + bonusMultiplier) * leaderboardMultiplier > limit;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'mechanicId': mechanicId,
        'sourceType': sourceType.wireName,
        'sourceId': sourceId,
        'basePoints': basePoints,
        'rank': rank.wireName,
        'rankMultiplier': rankMultiplier,
        'bonusMultiplier': bonusMultiplier,
        'leaderboardMultiplier': leaderboardMultiplier,
        'cap': cap,
        'effectiveMultiplier': effectiveMultiplier,
        'finalPoints': finalPoints,
        'createdAt': writeDate(createdAt),
        'seasonId': seasonId,
        'voidedAt': writeDateOrNull(voidedAt),
        'voidReason': voidReason,
      };

  factory PointTransaction.fromJson(Map<String, dynamic> json) => PointTransaction(
        id: readString(json['id']),
        mechanicId: readString(json['mechanicId']),
        sourceType: PointTransactionSource.fromWire(readString(json['sourceType'])),
        sourceId: readString(json['sourceId']),
        basePoints: readDouble(json['basePoints']),
        rank: MechanicRank.fromWire(readString(json['rank'])),
        rankMultiplier: readDouble(json['rankMultiplier'], 1),
        bonusMultiplier: readDouble(json['bonusMultiplier']),
        leaderboardMultiplier: readDouble(json['leaderboardMultiplier'], 1),
        cap: json['cap'] is num ? readDouble(json['cap']) : null,
        effectiveMultiplier: readDouble(json['effectiveMultiplier'], 1),
        finalPoints: readDouble(json['finalPoints']),
        createdAt: readDate(json['createdAt']),
        seasonId: readStringOrNull(json['seasonId']),
        voidedAt: readDateOrNull(json['voidedAt']),
        voidReason: readStringOrNull(json['voidReason']),
      );
}
