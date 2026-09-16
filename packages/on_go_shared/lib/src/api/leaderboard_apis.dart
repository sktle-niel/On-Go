import '../models/job_evaluation.dart';
import '../models/leaderboard.dart';
import '../models/point_transaction.dart';

// NOT IN THE API CONTRACT YET. Evaluations, job outcomes and point
// transactions belong to the jobs domain (Step 10), and seasons are a new
// domain; no route serves any of them, so both apps back these interfaces
// with local implementations and there are no entries in ApiEndpoints. When
// the backend adds them, HTTP implementations replace the local ones and no
// screen changes.
//
// The server, not the apps, is what must own point generation once it exists:
// these calculations are shared so the apps can show what the server decided,
// never so a client's arithmetic can be trusted.

/// The leaderboard's settings and seasons: set in the console, obeyed by the
/// mobile app.
abstract interface class LeaderboardConfigApi {
  Future<LeaderboardConfig> fetchConfig();

  Stream<LeaderboardConfig> watchConfig();

  /// Admin only. Recorded in the audit trail with [actor] and [reason].
  Future<LeaderboardConfig> updateConfig(LeaderboardConfig config, {required String actor, String? reason});

  Future<List<Season>> listSeasons();

  Stream<List<Season>> watchSeasons();

  Future<Season> createSeason({
    required String name,
    required DateTime startsAt,
    required DateTime endsAt,
    required String actor,
  });

  /// Starts a scheduled season. Only one season runs at a time.
  Future<Season> startSeason(String seasonId, {required String actor});

  /// Ends a running season: its score stops accumulating and [results] are
  /// recorded as its final placements. Ranks and lifetime statistics are not
  /// touched.
  Future<Season> endSeason(String seasonId, {required String actor, List<SeasonResult> results = const []});
}

/// What an admin reviews: standings, where each point came from, evaluations
/// (with their clients), flagged activity, and the audited corrections.
abstract interface class PerformanceReviewApi {
  /// The season's standings — a preview while the leaderboard is disabled.
  Future<List<LeaderboardStanding>> standings(String seasonId);

  Future<List<ScoreLine>> scoreLines(String seasonId, String mechanicId);

  Future<List<PointTransaction>> pointTransactions({String? mechanicId});

  /// Admin view: includes the client of every evaluation.
  Future<List<JobEvaluation>> evaluations({String? mechanicId});

  Future<List<SuspiciousActivity>> suspiciousActivity(String seasonId);

  /// Stops an evaluation counting. Needs a reason; recorded in the audit trail.
  Future<JobEvaluation> invalidateEvaluation(String evaluationId, {required String reason, required String actor});

  /// Adds a signed, reasoned adjustment to a season score.
  Future<ScoreAdjustment> adjustScore(ScoreAdjustment adjustment);

  Future<List<PerformanceAuditEntry>> auditTrail();
}
