import 'package:flutter/material.dart';

import '../data/points_wallet_store.dart';
import '../services/backend/mobile_backend.dart';
import '../theme/app_theme.dart';
import 'common_widgets.dart';

/// The balance headline, used by the client's Rewards screen and the
/// mechanic's Points screen so a balance reads the same to both.
class PointsBalanceCard extends StatelessWidget {
  const PointsBalanceCard({
    super.key,
    required this.points,
    this.caption,
    this.action,
  });

  final double points;
  final String? caption;

  /// A button under the figure — the mechanic's View Offer, and whatever the
  /// next surface needs.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      color: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.stars_rounded, size: 18, color: AppColors.textlight),
              const SizedBox(width: 6),
              Text(
                'Your points',
                style: TextStyle(
                  color: AppColors.textlight,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            formatPointsLabel(points),
            style: TextStyle(
              color: AppColors.textlight,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              style: TextStyle(
                color: AppColors.textlight.withValues(alpha: 0.8),
                fontSize: 12,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: action),
          ],
        ],
      ),
    );
  }
}

/// One line of points history.
class PointsEntryRow extends StatelessWidget {
  const PointsEntryRow({super.key, required this.entry});

  final PointsEntry entry;

  @override
  Widget build(BuildContext context) {
    final credit = entry.points > 0;
    final colour = credit ? AppColors.success : AppColors.warning;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            credit ? Icons.add_circle_outline : Icons.remove_circle_outline,
            size: 18,
            color: colour,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.kind.label,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 1),
                Text(
                  entry.note,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55)),
                ),
              ],
            ),
          ),
          // What a job earned is the admin's to see: the balance shows the
          // total and this row that the job paid out, but not by how much.
          // Spending keeps its figure — that is the user's own choice.
          if (!entry.kind.isCredit) ...[
            const SizedBox(width: 8),
            Text(
              '−${formatPoints(entry.points.abs())}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colour),
            ),
          ],
        ],
      ),
    );
  }
}
