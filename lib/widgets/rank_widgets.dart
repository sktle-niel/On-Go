import 'package:flutter/material.dart';

import '../data/mechanic_rank_store.dart';
import '../services/backend/mobile_backend.dart';
import '../theme/app_theme.dart';
import 'app_widgets.dart';
import 'common_widgets.dart';

/// A mechanic's rank on their profile — Iron, Bronze, Silver, Gold or Platinum.
///
/// On their own profile it also shows the points multiplier the rank gives
/// them and what the next rank asks for. A client sees the rank only.
///
/// Rank only: seasonal placement, Gem badges and the seasonal multiplier
/// belong to the future competitive leaderboard and are not shown here.
class MechanicRankCard extends StatelessWidget {
  const MechanicRankCard({super.key, required this.mechanicName, this.showProgress = true});

  final String mechanicName;

  /// The mechanic's own view: multiplier and progress.
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final ranks = MechanicRankStore.instance;

    return AnimatedBuilder(
      animation: ranks.changes,
      builder: (context, _) {
        final progress = ranks.progressFor(mechanicName);
        final standing = progress.standing;
        final next = progress.next;
        final requirement = progress.nextRequirement;
        final muted = AppColors.textdark.withValues(alpha: 0.55);

        return AppCard(
          padding: const EdgeInsets.all(16),
          color: AppColors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.military_tech_outlined, size: 20, color: AppColors.warning),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Rank', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                  TierBadge(tier: progress.rank.label),
                ],
              ),
              if (showProgress) ...[
                const SizedBox(height: 10),
                Text(
                  '${formatMultiplier(ranks.multiplierFor(mechanicName).total)} points on every paid job',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                if (next == null || requirement == null)
                  Text('Top rank reached.', style: TextStyle(fontSize: 12, color: muted))
                else ...[
                  Text('To reach ${next.label}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _ProgressRow(
                    label: 'Jobs done',
                    current: standing.completedJobs.toDouble(),
                    target: requirement.completedJobs.toDouble(),
                    format: (value) => value.toStringAsFixed(0),
                  ),
                  _ProgressRow(
                    label: 'Profile reviews',
                    current: standing.reviews.toDouble(),
                    target: requirement.reviews.toDouble(),
                    format: (value) => value.toStringAsFixed(0),
                  ),
                  _ProgressRow(
                    label: 'Average rating',
                    current: standing.averageRating,
                    target: requirement.averageRating,
                    format: (value) => value.toStringAsFixed(1),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

/// A mechanic's public badge: their 💎 Gem placement while the leaderboard is
/// live and they hold one — with the rank shown beneath it — otherwise their
/// rank.
class MechanicBadgeView extends StatelessWidget {
  const MechanicBadgeView({super.key, required this.badge, this.compact = false});

  final MechanicBadge badge;

  /// Just the pill, for lists.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final gem = badge.gem;
    if (gem == null) return TierBadge(tier: badge.rank.label);

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(gem.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.info)),
    );
    if (compact) return pill;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        pill,
        const SizedBox(height: 2),
        Text('Rank: ${badge.rank.label}',
            style: TextStyle(fontSize: 10, color: AppColors.textdark.withValues(alpha: 0.55))),
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.label,
    required this.current,
    required this.target,
    required this.format,
  });

  final String label;
  final double current;
  final double target;
  final String Function(double value) format;

  @override
  Widget build(BuildContext context) {
    final met = current >= target;
    final fraction = target <= 0 ? 1.0 : (current / target).clamp(0.0, 1.0);
    final color = met ? AppColors.success : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
              Text(
                '${format(current)} / ${format(target)}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: met ? AppColors.success : AppColors.textdark),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: AppColors.textdark.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}
