import 'dart:async';

import 'package:on_go_shared/on_go_shared.dart';

/// The mobile app's read-only end of the leaderboard settings and seasons.
///
/// Set in the console, but not in the On Go API yet (see
/// [LeaderboardConfigApi]), so nothing delivers an admin's change to a phone.
/// Until something does, the app runs on [LeaderboardConfig.defaults] — the
/// leaderboard disabled — and no season, while still recording the evaluations
/// and job outcomes a season will be scored from.
///
/// Every write refuses: seasons and settings are console actions.
class LocalLeaderboardConfigService implements LeaderboardConfigApi {
  LocalLeaderboardConfigService({LeaderboardConfig? config, List<Season> seasons = const []})
      : _config = config ?? LeaderboardConfig.defaults,
        _seasons = seasons;

  final LeaderboardConfig _config;
  final List<Season> _seasons;

  static const ApiException _consoleOnly = ApiException(
    ApiErrorKind.forbidden,
    'The leaderboard is configured in the On Go admin console.',
  );

  @override
  Future<LeaderboardConfig> fetchConfig() async => _config;

  @override
  Stream<LeaderboardConfig> watchConfig() => _replay(_config);

  @override
  Future<LeaderboardConfig> updateConfig(LeaderboardConfig config, {required String actor, String? reason}) =>
      Future.error(_consoleOnly);

  @override
  Future<List<Season>> listSeasons() async => _seasons;

  @override
  Stream<List<Season>> watchSeasons() => _replay(_seasons);

  @override
  Future<Season> createSeason({
    required String name,
    required DateTime startsAt,
    required DateTime endsAt,
    required String actor,
  }) =>
      Future.error(_consoleOnly);

  @override
  Future<Season> startSeason(String seasonId, {required String actor}) => Future.error(_consoleOnly);

  @override
  Future<Season> endSeason(String seasonId, {required String actor, List<SeasonResult> results = const []}) =>
      Future.error(_consoleOnly);

  static Stream<T> _replay<T>(T value) {
    late StreamController<T> controller;
    controller = StreamController<T>.broadcast(onListen: () => controller.add(value));
    return controller.stream;
  }
}
