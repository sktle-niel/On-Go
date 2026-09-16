import 'job_evaluation.dart';
import 'json.dart';

/// How a job a mechanic took on ended, for the record.
enum JobOutcomeKind {
  /// Paid and complete.
  completed('completed'),

  /// The mechanic dropped the job after accepting it.
  cancelledByMechanic('cancelled_by_mechanic'),

  /// The mechanic let the job's completion window run out.
  expired('expired');

  const JobOutcomeKind(this.wireName);

  final String wireName;

  static JobOutcomeKind fromWire(String value) =>
      values.firstWhere((kind) => kind.wireName == value, orElse: () => JobOutcomeKind.completed);
}

/// One event in a mechanic's work history — `job_outcomes` in a backend.
///
/// The raw record performance statistics, rank and the seasonal leaderboard
/// are all calculated from. A job's own fields are overwritten when it is
/// cancelled and re-accepted; these are not, so a mechanic's history is not
/// lost when the job moves on.
class JobOutcome {
  const JobOutcome({
    required this.id,
    required this.jobId,
    required this.mechanicId,
    required this.kind,
    required this.at,
    this.clientId,
    this.urgency = 'Normal',
    this.payout,
    this.arrivedOnTime,
    this.voidedAt,
    this.voidReason,
  });

  /// A completion is one per job and mechanic; a job can be accepted and
  /// dropped more than once, so cancellations and expiries carry their time.
  static String idFor(JobOutcomeKind kind, String jobId, String mechanicId, DateTime at) =>
      kind == JobOutcomeKind.completed
          ? '${kind.wireName}:$jobId:$mechanicId'
          : '${kind.wireName}:$jobId:$mechanicId:${at.microsecondsSinceEpoch}';

  final String id;
  final String jobId;
  final String mechanicId;
  final JobOutcomeKind kind;
  final DateTime at;
  final String? clientId;
  final String urgency;

  /// What the mechanic was paid, for a completion.
  final double? payout;

  /// For a completion: whether they arrived by the time their ETA promised.
  /// Null when it cannot be told — no arrival was recorded.
  final bool? arrivedOnTime;

  final DateTime? voidedAt;
  final String? voidReason;

  bool get counts => voidedAt == null;

  JobOutcome voided(String reason, {required DateTime at}) => JobOutcome(
        id: id,
        jobId: jobId,
        mechanicId: mechanicId,
        kind: kind,
        at: this.at,
        clientId: clientId,
        urgency: urgency,
        payout: payout,
        arrivedOnTime: arrivedOnTime,
        voidedAt: at,
        voidReason: reason,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'jobId': jobId,
        'mechanicId': mechanicId,
        'kind': kind.wireName,
        'at': writeDate(at),
        'clientId': clientId,
        'urgency': urgency,
        'payout': payout,
        'arrivedOnTime': arrivedOnTime,
        'voidedAt': writeDateOrNull(voidedAt),
        'voidReason': voidReason,
      };

  factory JobOutcome.fromJson(Map<String, dynamic> json) => JobOutcome(
        id: readString(json['id']),
        jobId: readString(json['jobId']),
        mechanicId: readString(json['mechanicId']),
        kind: JobOutcomeKind.fromWire(readString(json['kind'])),
        at: readDate(json['at']),
        clientId: readStringOrNull(json['clientId']),
        urgency: readString(json['urgency']).isEmpty ? 'Normal' : readString(json['urgency']),
        payout: json['payout'] is num ? readDouble(json['payout']) : null,
        arrivedOnTime: json['arrivedOnTime'] is bool ? json['arrivedOnTime'] as bool : null,
        voidedAt: readDateOrNull(json['voidedAt']),
        voidReason: readStringOrNull(json['voidReason']),
      );
}

/// A mechanic's measurable performance, worked out from their outcomes and
/// evaluations. Every rate is null until there is data behind it, so nothing
/// is ever shown as a figure it is not.
class MechanicPerformance {
  const MechanicPerformance({
    this.completedJobs = 0,
    this.cancelledJobs = 0,
    this.expiredJobs = 0,
    this.timedArrivals = 0,
    this.onTimeArrivals = 0,
    this.rating = const RatingSummary(),
  });

  factory MechanicPerformance.from({
    required Iterable<JobOutcome> outcomes,
    required Iterable<JobEvaluation> evaluations,
  }) {
    var completed = 0;
    var cancelled = 0;
    var expired = 0;
    var timed = 0;
    var onTime = 0;
    for (final outcome in outcomes.where((o) => o.counts)) {
      switch (outcome.kind) {
        case JobOutcomeKind.completed:
          completed++;
          final arrived = outcome.arrivedOnTime;
          if (arrived != null) {
            timed++;
            if (arrived) onTime++;
          }
        case JobOutcomeKind.cancelledByMechanic:
          cancelled++;
        case JobOutcomeKind.expired:
          expired++;
      }
    }
    return MechanicPerformance(
      completedJobs: completed,
      cancelledJobs: cancelled,
      expiredJobs: expired,
      timedArrivals: timed,
      onTimeArrivals: onTime,
      rating: RatingSummary.of([
        for (final evaluation in evaluations)
          if (evaluation.counts) evaluation.rating!,
      ]),
    );
  }

  final int completedJobs;
  final int cancelledJobs;
  final int expiredJobs;

  /// Completions where an arrival was recorded against an ETA.
  final int timedArrivals;
  final int onTimeArrivals;

  /// The overall rating: every job evaluation that counts.
  final RatingSummary rating;

  /// Jobs they took on that ended one way or another.
  int get acceptedJobs => completedJobs + cancelledJobs + expiredJobs;

  /// Share of the jobs they took on that they finished.
  double? get completionRate => acceptedJobs == 0 ? null : completedJobs / acceptedJobs;

  /// Share of timed arrivals that were on time.
  double? get onTimeRate => timedArrivals == 0 ? null : onTimeArrivals / timedArrivals;

  /// Share of evaluations at 4★ or 5★.
  double? get satisfactionRate => rating.shareAtLeast(4);
}
