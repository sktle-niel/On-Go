import 'package:flutter/material.dart';

import '../data/mechanic_performance_store.dart';
import '../data/mechanic_rank_store.dart';
import '../theme/app_theme.dart';

/// A mechanic's measurable performance, in place of marketing text.
///
/// Every figure comes from their recorded job outcomes and job evaluations. A
/// rate is only shown once there is something behind it — no completion rate
/// before a job was taken on, no on-time rate before an arrival was timed —
/// and the rating always says how many ratings it rests on.
class MechanicPerformanceSection extends StatelessWidget {
  const MechanicPerformanceSection({super.key, required this.mechanicName});

  final String mechanicName;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: MechanicRankStore.instance.changes,
      builder: (context, _) {
        final performance = MechanicPerformanceStore.instance.performanceFor(mechanicName);
        final rating = performance.rating;
        // The job-evaluation rating — per completed job. The profile rating
        // and review count are the profile reviews, shown with the reviews.
        final metrics = <(String, String)>[
          rating.isEmpty
              ? ('—', 'No job evaluations yet')
              : ('★ ${rating.average.toStringAsFixed(1)}',
                  'Job evaluations · ${rating.count} job${rating.count == 1 ? '' : 's'}'),
          ('${performance.completedJobs}', 'Jobs completed'),
          if (performance.completionRate != null) (_percent(performance.completionRate!), 'Completion rate'),
          if (performance.onTimeRate != null) (_percent(performance.onTimeRate!), 'On-time arrival'),
          if (performance.satisfactionRate != null) (_percent(performance.satisfactionRate!), 'Rated 4★ or higher'),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Performance', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textdark)),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 8.0;
                final width = (constraints.maxWidth - gap) / 2;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final (value, label) in metrics)
                      SizedBox(width: width, child: _Metric(value: value, label: label)),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  static String _percent(double share) => '${(share * 100).round()}%';
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.textdark.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AppColors.textdark)),
        ],
      ),
    );
  }
}
