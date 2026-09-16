import 'package:flutter/material.dart';

import '../data/leaderboard_store.dart';
import '../services/backend/mobile_backend.dart';
import '../theme/app_theme.dart';
import 'rank_widgets.dart';

/// The seasonal leaderboard, shared by the Client and Mechanic tabs.
///
/// Placement is seasonal performance, not rank: the list is the running
/// season's standings, best first. While the leaderboard is disabled nothing
/// competitive is shown at all — only that it is not active yet.
class SeasonLeaderboardView extends StatefulWidget {
  const SeasonLeaderboardView({super.key, required this.onOpenMechanic, this.highlightName});

  final void Function(String mechanicName) onOpenMechanic;

  /// Marked "You".
  final String? highlightName;

  @override
  State<SeasonLeaderboardView> createState() => _SeasonLeaderboardViewState();
}

class _SeasonLeaderboardViewState extends State<SeasonLeaderboardView> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final leaderboard = LeaderboardStore.instance;
    final muted = AppColors.textdark.withValues(alpha: 0.55);

    return AnimatedBuilder(
      animation: leaderboard.changes,
      builder: (context, _) {
        if (!leaderboard.enabled) {
          return _Message(
            icon: Icons.emoji_events_outlined,
            title: "The leaderboard isn't active yet",
            detail: 'Seasons will start once On Go has enough activity for a fair competition.',
          );
        }
        final season = leaderboard.activeSeason;
        if (season == null) {
          return const _Message(
            icon: Icons.event_busy_outlined,
            title: 'No season is running',
            detail: 'The next season will appear here when it starts.',
          );
        }
        final standings = leaderboard
            .standings(season)
            .where((s) => s.mechanicId.toLowerCase().contains(_query.toLowerCase()))
            .toList();

        return ListView(
          padding: context.layout.pageInsets,
          children: [
            Text(season.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(24)),
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  // The list filters as you type, so the magnifier marks the
                  // field instead of sitting outside it as decoration.
                  prefixIcon: Icon(Icons.search, size: 20, color: AppColors.textdark.withValues(alpha: 0.55)),
                  prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  hintText: 'Search mechanics...',
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (standings.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No scores yet this season.', style: TextStyle(color: muted))),
              ),
            for (final standing in standings)
              GestureDetector(
                onTap: () => widget.onOpenMechanic(standing.mechanicId),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.textdark.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        child: Text('#${standing.placement}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(standing.mechanicId,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                ),
                                if (standing.mechanicId == widget.highlightName) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(4)),
                                    child: Text('You', style: TextStyle(fontSize: 10, color: AppColors.textlight, fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${formatPoints(standing.points)} season points · ${standing.completedJobs} jobs',
                              style: TextStyle(fontSize: 11, color: muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      MechanicBadgeView(badge: leaderboard.badgeFor(standing.mechanicId), compact: true),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.detail});

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.textdark.withValues(alpha: 0.55);
    return Center(
      child: SingleChildScrollView(
        padding: context.layout.pageInsets,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: muted),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(detail, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: muted)),
          ],
        ),
      ),
    );
  }
}
