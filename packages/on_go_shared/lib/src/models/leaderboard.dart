import 'dart:math' as math;

import 'job_evaluation.dart';
import 'json.dart';
import 'mechanic_performance.dart';
import 'mechanic_rank.dart';

// The seasonal leaderboard. Deliberately separate from rank: rank is long-term
// progression (it never resets), the leaderboard is competitive performance
// within a season (it resets every season). A season's score is never stored
// as a number to add to — it is recalculated from the raw records
// ([JobOutcome], [JobEvaluation], [ScoreAdjustment]), so voiding a record
// removes its points and every point can be traced to what earned it.

enum SeasonStatus {
  scheduled('scheduled', 'Scheduled'),
  active('active', 'Active'),
  ended('ended', 'Ended');

  const SeasonStatus(this.wireName, this.label);

  final String wireName;
  final String label;

  static SeasonStatus fromWire(String value) =>
      values.firstWhere((status) => status.wireName == value, orElse: () => SeasonStatus.scheduled);
}

/// A mechanic's final placement in a season, frozen when it ended — the
/// historical achievement ("Season 1 — #58") that outlives the season.
class SeasonResult {
  const SeasonResult({required this.mechanicId, required this.placement, required this.points});

  final String mechanicId;
  final int placement;
  final double points;

  Map<String, dynamic> toJson() => {'mechanicId': mechanicId, 'placement': placement, 'points': points};

  factory SeasonResult.fromJson(Map<String, dynamic> json) => SeasonResult(
        mechanicId: readString(json['mechanicId']),
        placement: readInt(json['placement']),
        points: readDouble(json['points']),
      );
}

/// A competitive season. Dates are the admin's, not a fixed length.
class Season {
  const Season({
    required this.id,
    required this.name,
    required this.startsAt,
    required this.endsAt,
    this.status = SeasonStatus.scheduled,
    this.startedAt,
    this.endedAt,
    this.results = const [],
  });

  final String id;
  final String name;
  final DateTime startsAt;
  final DateTime endsAt;
  final SeasonStatus status;

  /// When an admin started it.
  final DateTime? startedAt;

  /// When an admin ended it — possibly before [endsAt].
  final DateTime? endedAt;

  /// Final placements, recorded when it ended.
  final List<SeasonResult> results;

  /// Points count from the later of its start date and when it was started…
  DateTime get scoringStart {
    final started = startedAt;
    return started != null && started.isAfter(startsAt) ? started : startsAt;
  }

  /// …to the earlier of its end date and when it was ended.
  DateTime get scoringEnd {
    final ended = endedAt;
    return ended != null && ended.isBefore(endsAt) ? ended : endsAt;
  }

  /// Whether something that happened [at] counts toward this season. A
  /// season that has not been started counts nothing; one that has ended
  /// counts nothing after it ended.
  bool accumulatesAt(DateTime at) =>
      status != SeasonStatus.scheduled && !at.isBefore(scoringStart) && at.isBefore(scoringEnd);

  bool isRunningAt(DateTime now) => status == SeasonStatus.active && accumulatesAt(now);

  String? get problem {
    if (name.trim().isEmpty) return 'Give the season a name.';
    if (!endsAt.isAfter(startsAt)) return 'A season must end after it starts.';
    return null;
  }

  Season copyWith({
    SeasonStatus? status,
    DateTime? startedAt,
    DateTime? endedAt,
    List<SeasonResult>? results,
  }) =>
      Season(
        id: id,
        name: name,
        startsAt: startsAt,
        endsAt: endsAt,
        status: status ?? this.status,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
        results: results ?? this.results,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startsAt': writeDate(startsAt),
        'endsAt': writeDate(endsAt),
        'status': status.wireName,
        'startedAt': writeDateOrNull(startedAt),
        'endedAt': writeDateOrNull(endedAt),
        'results': [for (final result in results) result.toJson()],
      };

  factory Season.fromJson(Map<String, dynamic> json) => Season(
        id: readString(json['id']),
        name: readString(json['name']),
        startsAt: readDate(json['startsAt']),
        endsAt: readDate(json['endsAt']),
        status: SeasonStatus.fromWire(readString(json['status'])),
        startedAt: readDateOrNull(json['startedAt']),
        endedAt: readDateOrNull(json['endedAt']),
        results: readObjectList(json['results']).map(SeasonResult.fromJson).toList(),
      );
}

/// How seasonal leaderboard points are earned and lost. All admin-configurable.
///
/// Built to reward good service rather than volume: a small job earns less,
/// repeat jobs for the same client in a day stop scoring past a limit, and a
/// poor evaluation or a dropped job costs points.
class LeaderboardScoring {
  const LeaderboardScoring({
    this.completedJob = 10,
    this.ratingPoints = const [-4, -2, 1, 3, 6],
    this.onTimeArrival = 2,
    this.jobValuePerThousandPesos = 1,
    this.maxJobValuePoints = 3,
    this.smallJobPayout = 300,
    this.smallJobFactor = 0.5,
    this.maxScoredJobsPerClientPerDay = 2,
    this.cancellationPenalty = -8,
    this.expiryPenalty = -5,
  });

  /// For a paid, completed job.
  final double completedJob;

  /// For the job's evaluation, by stars: index 0 is 1★, index 4 is 5★.
  final List<double> ratingPoints;

  /// For arriving by the ETA promised.
  final double onTimeArrival;

  /// For the size of the job, per ₱1,000 paid, up to [maxJobValuePoints].
  final double jobValuePerThousandPesos;
  final double maxJobValuePoints;

  /// A job paying less than this earns [smallJobFactor] of [completedJob].
  final double smallJobPayout;
  final double smallJobFactor;

  /// Jobs for one client in one day that score; the rest do not.
  final int maxScoredJobsPerClientPerDay;

  /// For dropping a job after accepting it (0 or less).
  final double cancellationPenalty;

  /// For letting a job's completion window run out (0 or less).
  final double expiryPenalty;

  double ratingPointsFor(int stars) => ratingPoints[(stars.clamp(1, 5)) - 1];

  String? get problem {
    if (completedJob < 0 || onTimeArrival < 0 || jobValuePerThousandPesos < 0 || maxJobValuePoints < 0) {
      return 'Points earned cannot be negative.';
    }
    if (ratingPoints.length != 5) return 'Give points for each of 1 to 5 stars.';
    for (var i = 1; i < ratingPoints.length; i++) {
      if (ratingPoints[i] < ratingPoints[i - 1]) {
        return 'A higher star rating cannot earn fewer points than a lower one.';
      }
    }
    if (smallJobPayout < 0) return 'The small-job amount cannot be negative.';
    if (smallJobFactor < 0 || smallJobFactor > 1) return 'The small-job share must be between 0 and 1.';
    if (maxScoredJobsPerClientPerDay < 1) return 'At least one job per client per day must score.';
    if (cancellationPenalty > 0 || expiryPenalty > 0) return 'Penalties must be 0 or less.';
    return null;
  }

  LeaderboardScoring copyWith({
    double? completedJob,
    List<double>? ratingPoints,
    double? onTimeArrival,
    double? jobValuePerThousandPesos,
    double? maxJobValuePoints,
    double? smallJobPayout,
    double? smallJobFactor,
    int? maxScoredJobsPerClientPerDay,
    double? cancellationPenalty,
    double? expiryPenalty,
  }) =>
      LeaderboardScoring(
        completedJob: completedJob ?? this.completedJob,
        ratingPoints: ratingPoints ?? this.ratingPoints,
        onTimeArrival: onTimeArrival ?? this.onTimeArrival,
        jobValuePerThousandPesos: jobValuePerThousandPesos ?? this.jobValuePerThousandPesos,
        maxJobValuePoints: maxJobValuePoints ?? this.maxJobValuePoints,
        smallJobPayout: smallJobPayout ?? this.smallJobPayout,
        smallJobFactor: smallJobFactor ?? this.smallJobFactor,
        maxScoredJobsPerClientPerDay: maxScoredJobsPerClientPerDay ?? this.maxScoredJobsPerClientPerDay,
        cancellationPenalty: cancellationPenalty ?? this.cancellationPenalty,
        expiryPenalty: expiryPenalty ?? this.expiryPenalty,
      );

  Map<String, dynamic> toJson() => {
        'completedJob': completedJob,
        'ratingPoints': ratingPoints,
        'onTimeArrival': onTimeArrival,
        'jobValuePerThousandPesos': jobValuePerThousandPesos,
        'maxJobValuePoints': maxJobValuePoints,
        'smallJobPayout': smallJobPayout,
        'smallJobFactor': smallJobFactor,
        'maxScoredJobsPerClientPerDay': maxScoredJobsPerClientPerDay,
        'cancellationPenalty': cancellationPenalty,
        'expiryPenalty': expiryPenalty,
      };

  factory LeaderboardScoring.fromJson(Map<String, dynamic> json) {
    const d = LeaderboardScoring();
    final stars = json['ratingPoints'];
    return LeaderboardScoring(
      completedJob: readDouble(json['completedJob'], d.completedJob),
      ratingPoints: stars is List && stars.length == 5
          ? [for (final value in stars) readDouble(value)]
          : d.ratingPoints,
      onTimeArrival: readDouble(json['onTimeArrival'], d.onTimeArrival),
      jobValuePerThousandPesos: readDouble(json['jobValuePerThousandPesos'], d.jobValuePerThousandPesos),
      maxJobValuePoints: readDouble(json['maxJobValuePoints'], d.maxJobValuePoints),
      smallJobPayout: readDouble(json['smallJobPayout'], d.smallJobPayout),
      smallJobFactor: readDouble(json['smallJobFactor'], d.smallJobFactor),
      maxScoredJobsPerClientPerDay: json['maxScoredJobsPerClientPerDay'] is num
          ? readInt(json['maxScoredJobsPerClientPerDay'])
          : d.maxScoredJobsPerClientPerDay,
      cancellationPenalty: readDouble(json['cancellationPenalty'], d.cancellationPenalty),
      expiryPenalty: readDouble(json['expiryPenalty'], d.expiryPenalty),
    );
  }

  @override
  bool operator ==(Object other) => other is LeaderboardScoring && _sameJson(toJson(), other.toJson());

  @override
  int get hashCode => Object.hashAll(toJson().values.map((v) => v is List ? Object.hashAll(v) : v));
}

/// The seasonal points multiplier for placements down to [upToPlacement].
class PlacementMultiplier {
  const PlacementMultiplier({required this.upToPlacement, required this.multiplier});

  final int upToPlacement;
  final double multiplier;

  Map<String, dynamic> toJson() => {'upToPlacement': upToPlacement, 'multiplier': multiplier};

  factory PlacementMultiplier.fromJson(Map<String, dynamic> json) => PlacementMultiplier(
        upToPlacement: readInt(json['upToPlacement']),
        multiplier: readDouble(json['multiplier'], 1),
      );
}

/// Everything about the leaderboard an admin controls.
class LeaderboardConfig {
  const LeaderboardConfig({
    this.enabled = false,
    this.scoring = const LeaderboardScoring(),
    this.gemMaxPlacement = 250,
    this.placementMultipliers = defaultPlacementMultipliers,
    this.maxEffectiveMultiplier = 4.5,
    this.suspiciousJobsPerHour = 4,
    this.minActiveMechanics,
    this.minCompletedJobs,
  });

  static const LeaderboardConfig defaults = LeaderboardConfig();

  static const List<PlacementMultiplier> defaultPlacementMultipliers = [
    PlacementMultiplier(upToPlacement: 10, multiplier: 1.5),
    PlacementMultiplier(upToPlacement: 50, multiplier: 1.25),
    PlacementMultiplier(upToPlacement: 250, multiplier: 1.1),
  ];

  /// The public switch. Off: no leaderboard navigation, no Gem badges, no
  /// seasonal multiplier — while the data it needs keeps being collected.
  final bool enabled;

  final LeaderboardScoring scoring;

  /// Placements that earn a Gem badge: #1 down to this. 0 awards none.
  final int gemMaxPlacement;

  /// Seasonal multipliers by placement, best placements first.
  final List<PlacementMultiplier> placementMultipliers;

  /// The most any combination of multipliers may multiply points by.
  final double maxEffectiveMultiplier;

  /// Completed jobs by one mechanic within an hour that flag for review.
  final int suspiciousJobsPerHour;

  /// Activation guidance for admins, not an automatic rule: how many active
  /// mechanics and completed jobs make a season worth running. Null: not set.
  final int? minActiveMechanics;
  final int? minCompletedJobs;

  /// The seasonal multiplier for [placement]; x1 outside every tier.
  double multiplierForPlacement(int placement) {
    for (final tier in placementMultipliers) {
      if (placement <= tier.upToPlacement) return tier.multiplier;
    }
    return 1;
  }

  String? get problem {
    final scoringProblem = scoring.problem;
    if (scoringProblem != null) return scoringProblem;
    if (maxEffectiveMultiplier < 1) return 'The multiplier cap must be at least x1.';
    if (gemMaxPlacement < 0) return 'The Gem placement limit cannot be negative.';
    if (suspiciousJobsPerHour < 2) return 'Flag mechanics at 2 or more jobs an hour.';
    if ((minActiveMechanics ?? 0) < 0 || (minCompletedJobs ?? 0) < 0) {
      return 'Activation guidance cannot be negative.';
    }
    PlacementMultiplier? previous;
    for (final tier in placementMultipliers) {
      if (tier.upToPlacement < 1) return 'Placement tiers start at #1.';
      if (tier.multiplier < 1) return 'A seasonal multiplier cannot be below x1.';
      if (previous != null) {
        if (tier.upToPlacement <= previous.upToPlacement) {
          return 'List placement tiers from the best placements down.';
        }
        if (tier.multiplier > previous.multiplier) {
          return 'A lower placement cannot earn a bigger multiplier than a higher one.';
        }
      }
      previous = tier;
    }
    return null;
  }

  bool get isValid => problem == null;

  LeaderboardConfig copyWith({
    bool? enabled,
    LeaderboardScoring? scoring,
    int? gemMaxPlacement,
    List<PlacementMultiplier>? placementMultipliers,
    double? maxEffectiveMultiplier,
    int? suspiciousJobsPerHour,
  }) =>
      LeaderboardConfig(
        enabled: enabled ?? this.enabled,
        scoring: scoring ?? this.scoring,
        gemMaxPlacement: gemMaxPlacement ?? this.gemMaxPlacement,
        placementMultipliers: placementMultipliers ?? this.placementMultipliers,
        maxEffectiveMultiplier: maxEffectiveMultiplier ?? this.maxEffectiveMultiplier,
        suspiciousJobsPerHour: suspiciousJobsPerHour ?? this.suspiciousJobsPerHour,
        minActiveMechanics: minActiveMechanics,
        minCompletedJobs: minCompletedJobs,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'scoring': scoring.toJson(),
        'gemMaxPlacement': gemMaxPlacement,
        'placementMultipliers': [for (final tier in placementMultipliers) tier.toJson()],
        'maxEffectiveMultiplier': maxEffectiveMultiplier,
        'suspiciousJobsPerHour': suspiciousJobsPerHour,
        'minActiveMechanics': minActiveMechanics,
        'minCompletedJobs': minCompletedJobs,
      };

  factory LeaderboardConfig.fromJson(Map<String, dynamic> json) => LeaderboardConfig(
        enabled: json['enabled'] == true,
        scoring: json['scoring'] is Map
            ? LeaderboardScoring.fromJson(readObject(json['scoring']))
            : const LeaderboardScoring(),
        gemMaxPlacement: json['gemMaxPlacement'] is num ? readInt(json['gemMaxPlacement']) : defaults.gemMaxPlacement,
        placementMultipliers: json['placementMultipliers'] is List
            ? readObjectList(json['placementMultipliers']).map(PlacementMultiplier.fromJson).toList()
            : defaultPlacementMultipliers,
        maxEffectiveMultiplier: readDouble(json['maxEffectiveMultiplier'], defaults.maxEffectiveMultiplier),
        suspiciousJobsPerHour: json['suspiciousJobsPerHour'] is num
            ? readInt(json['suspiciousJobsPerHour'])
            : defaults.suspiciousJobsPerHour,
        minActiveMechanics: json['minActiveMechanics'] is num ? readInt(json['minActiveMechanics']) : null,
        minCompletedJobs: json['minCompletedJobs'] is num ? readInt(json['minCompletedJobs']) : null,
      );

  @override
  bool operator ==(Object other) => other is LeaderboardConfig && _sameJson(toJson(), other.toJson());

  @override
  int get hashCode => Object.hash(enabled, gemMaxPlacement, maxEffectiveMultiplier, placementMultipliers.length);
}

/// What a season's score is made of, for the breakdown an admin reads.
enum ScoreCategory {
  completion('Completed jobs'),
  satisfaction('Customer satisfaction'),
  reliability('Reliability'),
  value('Job value'),
  adjustment('Adjustments');

  const ScoreCategory(this.label);

  final String label;
}

enum ScoreSource {
  jobCompleted('job_completed', ScoreCategory.completion),
  evaluation('evaluation', ScoreCategory.satisfaction),
  onTimeArrival('on_time_arrival', ScoreCategory.reliability),
  cancellation('cancellation', ScoreCategory.reliability),
  expiry('expiry', ScoreCategory.reliability),
  jobValue('job_value', ScoreCategory.value),
  adjustment('adjustment', ScoreCategory.adjustment);

  const ScoreSource(this.wireName, this.category);

  final String wireName;
  final ScoreCategory category;
}

/// One reason a mechanic's season score moved — traced to the record that
/// caused it. Calculated, never stored as the score.
class ScoreLine {
  const ScoreLine({
    required this.mechanicId,
    required this.seasonId,
    required this.source,
    required this.sourceId,
    required this.points,
    required this.at,
    this.note,
  });

  final String mechanicId;
  final String seasonId;
  final ScoreSource source;

  /// The job, evaluation, outcome or adjustment it came from.
  final String sourceId;
  final double points;
  final DateTime at;
  final String? note;
}

/// An admin's manual change to a mechanic's season score. Never a bare
/// "set the score to": a signed amount, with the reason and who made it.
class ScoreAdjustment {
  const ScoreAdjustment({
    required this.id,
    required this.seasonId,
    required this.mechanicId,
    required this.points,
    required this.reason,
    required this.actor,
    required this.createdAt,
    this.voidedAt,
  });

  final String id;
  final String seasonId;
  final String mechanicId;
  final double points;
  final String reason;
  final String actor;
  final DateTime createdAt;
  final DateTime? voidedAt;

  String? get problem {
    if (points == 0) return 'An adjustment has to change the score.';
    if (reason.trim().length < 5) return 'Say why — every adjustment needs a reason.';
    if (actor.trim().isEmpty) return 'An adjustment needs to record who made it.';
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'seasonId': seasonId,
        'mechanicId': mechanicId,
        'points': points,
        'reason': reason,
        'actor': actor,
        'createdAt': writeDate(createdAt),
        'voidedAt': writeDateOrNull(voidedAt),
      };

  factory ScoreAdjustment.fromJson(Map<String, dynamic> json) => ScoreAdjustment(
        id: readString(json['id']),
        seasonId: readString(json['seasonId']),
        mechanicId: readString(json['mechanicId']),
        points: readDouble(json['points']),
        reason: readString(json['reason']),
        actor: readString(json['actor']),
        createdAt: readDate(json['createdAt']),
        voidedAt: readDateOrNull(json['voidedAt']),
      );
}

enum PerformanceAuditAction {
  configUpdated('config_updated', 'Leaderboard settings changed'),
  seasonCreated('season_created', 'Season created'),
  seasonStarted('season_started', 'Season started'),
  seasonEnded('season_ended', 'Season ended'),
  evaluationInvalidated('evaluation_invalidated', 'Evaluation invalidated'),
  scoreAdjusted('score_adjusted', 'Score adjusted');

  const PerformanceAuditAction(this.wireName, this.label);

  final String wireName;
  final String label;

  static PerformanceAuditAction fromWire(String value) =>
      values.firstWhere((action) => action.wireName == value, orElse: () => PerformanceAuditAction.configUpdated);
}

/// Who changed something about the leaderboard, what, and why.
class PerformanceAuditEntry {
  const PerformanceAuditEntry({
    required this.id,
    required this.action,
    required this.actor,
    required this.subjectId,
    required this.at,
    this.reason,
    this.detail,
  });

  final String id;
  final PerformanceAuditAction action;
  final String actor;

  /// The season, evaluation or mechanic it was about.
  final String subjectId;
  final DateTime at;
  final String? reason;
  final String? detail;

  Map<String, dynamic> toJson() => {
        'id': id,
        'action': action.wireName,
        'actor': actor,
        'subjectId': subjectId,
        'at': writeDate(at),
        'reason': reason,
        'detail': detail,
      };

  factory PerformanceAuditEntry.fromJson(Map<String, dynamic> json) => PerformanceAuditEntry(
        id: readString(json['id']),
        action: PerformanceAuditAction.fromWire(readString(json['action'])),
        actor: readString(json['actor']),
        subjectId: readString(json['subjectId']),
        at: readDate(json['at']),
        reason: readStringOrNull(json['reason']),
        detail: readStringOrNull(json['detail']),
      );
}

/// A mechanic's place in a season.
class LeaderboardStanding {
  const LeaderboardStanding({
    required this.mechanicId,
    required this.placement,
    required this.points,
    required this.rating,
    required this.completedJobs,
    required this.cancellationRate,
    required this.reachedAt,
    required this.byCategory,
  });

  final String mechanicId;

  /// #1 is the best.
  final int placement;
  final double points;

  /// Evaluations of this season's scored jobs.
  final RatingSummary rating;
  final int completedJobs;

  /// Dropped or expired jobs as a share of jobs taken on this season.
  final double cancellationRate;

  /// When the mechanic's score last changed — the earlier one wins a tie.
  final DateTime reachedAt;
  final Map<ScoreCategory, double> byCategory;
}

/// A seasonal placement shown as a badge: 💎 #58 Gem.
class GemPlacement {
  const GemPlacement({required this.seasonId, required this.seasonName, required this.placement});

  final String seasonId;
  final String seasonName;
  final int placement;

  String get label => '💎 #$placement Gem';
}

enum SuspiciousActivityKind {
  /// More jobs for one client in a day than score.
  repeatClient('Repeat jobs for one client'),

  /// Unusually many completed jobs in a short time.
  rapidJobs('Many jobs in a short time');

  const SuspiciousActivityKind(this.label);

  final String label;
}

/// Something about a mechanic's jobs worth a person's attention. Flagged for
/// review, never acted on automatically.
class SuspiciousActivity {
  const SuspiciousActivity({required this.kind, required this.mechanicId, required this.jobIds, required this.detail});

  final SuspiciousActivityKind kind;
  final String mechanicId;
  final List<String> jobIds;
  final String detail;
}

/// Works out a season from the raw records. Pure and deterministic — the same
/// records and settings always give the same scores and the same order — so a
/// server, the console and the app all agree.
class LeaderboardEngine {
  const LeaderboardEngine(this.config);

  final LeaderboardConfig config;

  LeaderboardScoring get _scoring => config.scoring;

  /// Every reason a mechanic's score moved during [season].
  List<ScoreLine> scoreLines({
    required Season season,
    required Iterable<JobOutcome> outcomes,
    required Iterable<JobEvaluation> evaluations,
    Iterable<ScoreAdjustment> adjustments = const [],
  }) {
    final lines = <ScoreLine>[];
    final scored = _scoredCompletions(season, outcomes);
    final scoredKeys = {for (final o in scored) '${o.jobId}|${o.mechanicId}'};

    for (final outcome in _inSeason(season, outcomes)) {
      switch (outcome.kind) {
        case JobOutcomeKind.completed:
          if (!scoredKeys.contains('${outcome.jobId}|${outcome.mechanicId}')) continue;
          final payout = outcome.payout;
          final small = payout != null && payout < _scoring.smallJobPayout;
          lines.add(_line(season, outcome.mechanicId, ScoreSource.jobCompleted, outcome.jobId,
              _scoring.completedJob * (small ? _scoring.smallJobFactor : 1), outcome.at,
              note: small ? 'Small job' : null));
          if (outcome.arrivedOnTime == true && _scoring.onTimeArrival != 0) {
            lines.add(_line(season, outcome.mechanicId, ScoreSource.onTimeArrival, outcome.jobId,
                _scoring.onTimeArrival, outcome.at));
          }
          if (payout != null && _scoring.jobValuePerThousandPesos > 0) {
            final value = math.min(payout / 1000 * _scoring.jobValuePerThousandPesos, _scoring.maxJobValuePoints);
            if (value > 0) {
              lines.add(_line(season, outcome.mechanicId, ScoreSource.jobValue, outcome.jobId, value, outcome.at));
            }
          }
        case JobOutcomeKind.cancelledByMechanic:
          if (_scoring.cancellationPenalty != 0) {
            lines.add(_line(season, outcome.mechanicId, ScoreSource.cancellation, outcome.id,
                _scoring.cancellationPenalty, outcome.at));
          }
        case JobOutcomeKind.expired:
          if (_scoring.expiryPenalty != 0) {
            lines.add(_line(season, outcome.mechanicId, ScoreSource.expiry, outcome.id, _scoring.expiryPenalty,
                outcome.at));
          }
      }
    }

    for (final evaluation in _scoredEvaluations(season, evaluations, scoredKeys)) {
      lines.add(_line(season, evaluation.mechanicId, ScoreSource.evaluation, evaluation.id,
          _scoring.ratingPointsFor(evaluation.rating!), evaluation.submittedAt!,
          note: '${evaluation.rating}★'));
    }

    for (final adjustment in adjustments) {
      if (adjustment.seasonId != season.id || adjustment.voidedAt != null) continue;
      lines.add(_line(season, adjustment.mechanicId, ScoreSource.adjustment, adjustment.id, adjustment.points,
          adjustment.createdAt,
          note: '${adjustment.reason} — ${adjustment.actor}'));
    }

    lines.sort((a, b) {
      final byTime = a.at.compareTo(b.at);
      return byTime != 0 ? byTime : a.sourceId.compareTo(b.sourceId);
    });
    return lines;
  }

  /// Every mechanic who scored in [season], placed. Ties break, in order, on:
  /// points, season rating, completed jobs, fewer cancellations, reaching the
  /// score first — and finally the mechanic id, so the order never changes on
  /// a refresh.
  List<LeaderboardStanding> standings({
    required Season season,
    required Iterable<JobOutcome> outcomes,
    required Iterable<JobEvaluation> evaluations,
    Iterable<ScoreAdjustment> adjustments = const [],
  }) {
    final lines = scoreLines(season: season, outcomes: outcomes, evaluations: evaluations, adjustments: adjustments);
    final scored = _scoredCompletions(season, outcomes);
    final scoredKeys = {for (final o in scored) '${o.jobId}|${o.mechanicId}'};
    final seasonEvaluations = _scoredEvaluations(season, evaluations, scoredKeys).toList();
    final inSeason = _inSeason(season, outcomes).toList();

    final mechanics = <String>{for (final line in lines) line.mechanicId};
    final unplaced = <_Unplaced>[];
    for (final mechanic in mechanics) {
      final own = lines.where((l) => l.mechanicId == mechanic).toList();
      final byCategory = <ScoreCategory, double>{};
      for (final line in own) {
        byCategory[line.source.category] = _round((byCategory[line.source.category] ?? 0) + line.points);
      }
      final completed = scored.where((o) => o.mechanicId == mechanic).length;
      final dropped = inSeason
          .where((o) => o.mechanicId == mechanic && o.kind != JobOutcomeKind.completed)
          .length;
      final taken = inSeason.where((o) => o.mechanicId == mechanic).length;
      unplaced.add(_Unplaced(
        mechanicId: mechanic,
        points: _round(own.fold(0, (sum, line) => sum + line.points)),
        rating: RatingSummary.of([
          for (final e in seasonEvaluations)
            if (e.mechanicId == mechanic) e.rating!,
        ]),
        completedJobs: completed,
        cancellationRate: taken == 0 ? 0 : dropped / taken,
        reachedAt: own.last.at,
        byCategory: byCategory,
      ));
    }

    unplaced.sort((a, b) {
      int? decide(int value) => value == 0 ? null : value;
      return decide(b.points.compareTo(a.points)) ??
          decide(b.rating.average.compareTo(a.rating.average)) ??
          decide(b.completedJobs.compareTo(a.completedJobs)) ??
          decide(a.cancellationRate.compareTo(b.cancellationRate)) ??
          decide(a.reachedAt.compareTo(b.reachedAt)) ??
          a.mechanicId.compareTo(b.mechanicId);
    });

    return [
      for (var i = 0; i < unplaced.length; i++)
        LeaderboardStanding(
          mechanicId: unplaced[i].mechanicId,
          placement: i + 1,
          points: unplaced[i].points,
          rating: unplaced[i].rating,
          completedJobs: unplaced[i].completedJobs,
          cancellationRate: unplaced[i].cancellationRate,
          reachedAt: unplaced[i].reachedAt,
          byCategory: unplaced[i].byCategory,
        ),
    ];
  }

  /// [mechanicId]'s Gem, if their placement earns one. A score of 0 or less
  /// earns nothing, whatever the placement.
  GemPlacement? gemFor(String mechanicId, Season season, List<LeaderboardStanding> standings) {
    final standing = _standingOf(mechanicId, standings);
    if (standing == null || standing.points <= 0 || standing.placement > config.gemMaxPlacement) return null;
    return GemPlacement(seasonId: season.id, seasonName: season.name, placement: standing.placement);
  }

  /// [mechanicId]'s seasonal multiplier from their placement; x1 without one.
  double seasonalMultiplierFor(String mechanicId, List<LeaderboardStanding> standings) {
    final standing = _standingOf(mechanicId, standings);
    if (standing == null || standing.points <= 0) return 1;
    return config.multiplierForPlacement(standing.placement);
  }

  /// Patterns in [season] worth an admin's look.
  List<SuspiciousActivity> suspiciousActivity({required Season season, required Iterable<JobOutcome> outcomes}) {
    final flags = <SuspiciousActivity>[];
    final completions = _inSeason(season, outcomes).where((o) => o.kind == JobOutcomeKind.completed).toList();

    final byClientDay = <String, List<JobOutcome>>{};
    for (final outcome in completions) {
      if (outcome.clientId == null) continue;
      byClientDay.putIfAbsent(_clientDayKey(outcome), () => []).add(outcome);
    }
    for (final group in byClientDay.values) {
      if (group.length <= _scoring.maxScoredJobsPerClientPerDay) continue;
      flags.add(SuspiciousActivity(
        kind: SuspiciousActivityKind.repeatClient,
        mechanicId: group.first.mechanicId,
        jobIds: [for (final o in group) o.jobId],
        detail: '${group.length} jobs for one client on one day; '
            '${_scoring.maxScoredJobsPerClientPerDay} scored.',
      ));
    }

    final byMechanic = <String, List<JobOutcome>>{};
    for (final outcome in completions) {
      byMechanic.putIfAbsent(outcome.mechanicId, () => []).add(outcome);
    }
    for (final entry in byMechanic.entries) {
      final list = entry.value..sort((a, b) => a.at.compareTo(b.at));
      var start = 0;
      for (var end = 0; end < list.length; end++) {
        while (list[end].at.difference(list[start].at) > const Duration(hours: 1)) {
          start++;
        }
        if (end - start + 1 >= config.suspiciousJobsPerHour) {
          flags.add(SuspiciousActivity(
            kind: SuspiciousActivityKind.rapidJobs,
            mechanicId: entry.key,
            jobIds: [for (final o in list.sublist(start, end + 1)) o.jobId],
            detail: '${end - start + 1} completed jobs within an hour.',
          ));
          break;
        }
      }
    }
    return flags;
  }

  Iterable<JobOutcome> _inSeason(Season season, Iterable<JobOutcome> outcomes) {
    final list = outcomes.where((o) => o.counts && season.accumulatesAt(o.at)).toList()
      ..sort((a, b) {
        final byTime = a.at.compareTo(b.at);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    return list;
  }

  /// Completed jobs that score: in the season, and within the per-client
  /// daily limit.
  List<JobOutcome> _scoredCompletions(Season season, Iterable<JobOutcome> outcomes) {
    final perClientDay = <String, int>{};
    final scored = <JobOutcome>[];
    for (final outcome in _inSeason(season, outcomes)) {
      if (outcome.kind != JobOutcomeKind.completed) continue;
      if (outcome.clientId != null) {
        final key = _clientDayKey(outcome);
        final count = perClientDay[key] ?? 0;
        if (count >= _scoring.maxScoredJobsPerClientPerDay) continue;
        perClientDay[key] = count + 1;
      }
      scored.add(outcome);
    }
    return scored;
  }

  /// Evaluations of scored jobs, submitted while the season was counting.
  Iterable<JobEvaluation> _scoredEvaluations(
    Season season,
    Iterable<JobEvaluation> evaluations,
    Set<String> scoredKeys,
  ) =>
      evaluations.where((e) =>
          e.counts &&
          e.submittedAt != null &&
          season.accumulatesAt(e.submittedAt!) &&
          scoredKeys.contains('${e.jobId}|${e.mechanicId}'));

  static String _clientDayKey(JobOutcome outcome) =>
      '${outcome.mechanicId}|${outcome.clientId}|${outcome.at.year}-${outcome.at.month}-${outcome.at.day}';

  static LeaderboardStanding? _standingOf(String mechanicId, List<LeaderboardStanding> standings) {
    for (final standing in standings) {
      if (standing.mechanicId == mechanicId) return standing;
    }
    return null;
  }

  static ScoreLine _line(
    Season season,
    String mechanicId,
    ScoreSource source,
    String sourceId,
    double points,
    DateTime at, {
    String? note,
  }) =>
      ScoreLine(
        mechanicId: mechanicId,
        seasonId: season.id,
        source: source,
        sourceId: sourceId,
        points: _round(points),
        at: at,
        note: note,
      );

  static double _round(double value) => (value * 100).round() / 100;
}

class _Unplaced {
  _Unplaced({
    required this.mechanicId,
    required this.points,
    required this.rating,
    required this.completedJobs,
    required this.cancellationRate,
    required this.reachedAt,
    required this.byCategory,
  });

  final String mechanicId;
  final double points;
  final RatingSummary rating;
  final int completedJobs;
  final double cancellationRate;
  final DateTime reachedAt;
  final Map<ScoreCategory, double> byCategory;
}

bool _sameJson(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_sameJson(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameJson(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is num && b is num) return a == b;
  return a == b;
}

/// The rank a mechanic shows publicly, and the Gem that takes its place when
/// the leaderboard is live and their placement earns one. The rank is never
/// replaced in the data — only in what is shown first.
class MechanicBadge {
  const MechanicBadge({required this.rank, this.gem});

  final MechanicRank rank;
  final GemPlacement? gem;

  bool get showsGem => gem != null;

  String get primaryLabel => gem?.label ?? rank.label;
}
