import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/backend/mobile_backend.dart';
import 'job_evaluation_store.dart';
import 'mechanic_performance_store.dart';
import 'mechanic_rank_store.dart';
import 'rank_policy_store.dart';

/// The leaderboard settings and seasons, cached on this device.
class LeaderboardConfigStore extends ChangeNotifier {
  LeaderboardConfigStore._internal();
  static final LeaderboardConfigStore instance = LeaderboardConfigStore._internal();

  LeaderboardConfig _config = LeaderboardConfig.defaults;
  List<Season> _seasons = const [];
  StreamSubscription<LeaderboardConfig>? _configWatch;
  StreamSubscription<List<Season>>? _seasonsWatch;

  /// [LeaderboardConfig.defaults] — disabled — until an update arrives.
  LeaderboardConfig get config => _config;

  List<Season> get seasons => _seasons;

  /// The season scoring right now, if any.
  Season? activeSeason([DateTime? now]) {
    final at = now ?? DateTime.now();
    for (final season in _seasons) {
      if (season.isRunningAt(at)) return season;
    }
    return null;
  }

  /// Starts following the settings and seasons. Never waits on the network;
  /// a failure keeps what is there.
  Future<void> load() async {
    await _configWatch?.cancel();
    await _seasonsWatch?.cancel();
    final api = MobileBackend.instance.leaderboardConfig;
    _configWatch = api.watchConfig().listen(_applyConfig, onError: (Object _) {});
    _seasonsWatch = api.watchSeasons().listen(_applySeasons, onError: (Object _) {});
  }

  void _applyConfig(LeaderboardConfig config) {
    if (config == _config || !config.isValid) return;
    _config = config;
    notifyListeners();
  }

  void _applySeasons(List<Season> seasons) {
    _seasons = List.unmodifiable(seasons);
    notifyListeners();
  }

  @visibleForTesting
  void debugSet({LeaderboardConfig? config, List<Season>? seasons}) {
    if (config != null) _config = config;
    if (seasons != null) _seasons = List.unmodifiable(seasons);
    notifyListeners();
  }
}

/// The seasonal leaderboard as this device can work it out: standings, Gem
/// placements and the seasonal multiplier, calculated from the saved job
/// outcomes and evaluations with [LeaderboardEngine].
///
/// Two levels, on purpose:
///
/// * [standings] and [gemFor] work whether or not the leaderboard is public —
///   the internal preview.
/// * [badgeFor] and [seasonalMultiplierFor] are what users see and what pays
///   out, and do nothing while the leaderboard is disabled.
///
/// Rank is never touched: a Gem is shown in its place, never instead of it in
/// the data.
class LeaderboardStore {
  LeaderboardStore._internal();
  static final LeaderboardStore instance = LeaderboardStore._internal();

  late final Listenable changes = Listenable.merge([
    LeaderboardConfigStore.instance,
    MechanicPerformanceStore.instance,
    JobEvaluationStore.instance,
    RankPolicyStore.instance,
  ]);

  LeaderboardConfig get config => LeaderboardConfigStore.instance.config;

  /// Whether the leaderboard is public.
  bool get enabled => config.enabled;

  Season? get activeSeason => LeaderboardConfigStore.instance.activeSeason();

  LeaderboardEngine get _engine => LeaderboardEngine(config);

  /// [season]'s standings — the running season by default; none without one.
  List<LeaderboardStanding> standings([Season? season]) {
    final target = season ?? activeSeason;
    if (target == null) return const [];
    return _engine.standings(
      season: target,
      outcomes: MechanicPerformanceStore.instance.all,
      evaluations: JobEvaluationStore.instance.all,
    );
  }

  /// [mechanicId]'s Gem in the running season, public or not.
  GemPlacement? gemFor(String mechanicId) {
    final season = activeSeason;
    if (season == null) return null;
    return _engine.gemFor(mechanicId, season, standings(season));
  }

  /// What [mechanicId] shows publicly: their rank, with their Gem in front of
  /// it while the leaderboard is live.
  MechanicBadge badgeFor(String mechanicId) => MechanicBadge(
        rank: MechanicRankStore.instance.rankFor(mechanicId),
        gem: enabled ? gemFor(mechanicId) : null,
      );

  /// The seasonal multiplier on [mechanicId]'s points — x1 unless the
  /// leaderboard is live, a season is running and their placement earns one.
  double seasonalMultiplierFor(String mechanicId) {
    final season = activeSeason;
    if (!enabled || season == null) return 1;
    return _engine.seasonalMultiplierFor(mechanicId, standings(season));
  }

  /// Everything that multiplies [mechanicId]'s reward points: rank, bonuses
  /// and the seasonal multiplier, held to the configured cap.
  PointsMultiplier multiplierFor(String mechanicId) => MechanicRankStore.instance
      .multiplierFor(mechanicId)
      .withLeaderboard(seasonalMultiplierFor(mechanicId), cap: config.maxEffectiveMultiplier);
}
