import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The app bar and the notification bell now live in `package:on_go_design`,
/// shared with the admin console so a phone-sized console window wears the
/// same chrome the app does. Re-exported so every screen keeps importing this
/// one file.
export 'package:on_go_design/on_go_design.dart' show NotificationBell, OnGoAppBar;

/// Small "★ 4.8" style rating display.
class RatingStars extends StatelessWidget {
  final double rating;
  final double size;
  const RatingStars({super.key, required this.rating, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star, color: AppColors.warning, size: size),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(fontSize: size - 1, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Colored rank pill (Platinum / Gold / Silver / Bronze / Iron).
class TierBadge extends StatelessWidget {
  final String tier;
  const TierBadge({super.key, required this.tier});

  Color get _color {
    switch (tier) {
      case 'Platinum':
        return const Color(0xFF8E9AAF);
      case 'Gold':
        return const Color(0xFFD4A017);
      case 'Silver':
        return const Color(0xFF9E9E9E);
      case 'Bronze':
        return const Color(0xFFB0703C);
      default:
        return AppColors.textdark.withValues(alpha: 0.55);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        tier,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _color,
        ),
      ),
    );
  }
}

/// 5★→1★ rating breakdown bars with a big average score on the side.
class RatingSummaryBars extends StatelessWidget {
  final double average;
  final Map<int, double> distribution;
  final int reviewCount;

  const RatingSummaryBars({
    super.key,
    required this.average,
    required this.distribution,
    required this.reviewCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            children: List.generate(5, (i) {
              final star = 5 - i;
              final value = distribution[star] ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Text('$star',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55))),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: value,
                          minHeight: 6,
                          backgroundColor:
                              AppColors.textdark.withValues(alpha: 0.2),
                          valueColor:
                              AlwaysStoppedAnimation(AppColors.warning),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: 20),
        Column(
          children: [
            Text(
              average.toStringAsFixed(1),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                5,
                (i) => Icon(
                  i < average.round() ? Icons.star : Icons.star_border,
                  color: AppColors.warning,
                  size: 14,
                ),
              ),
            ),
            Text('$reviewCount reviews',
                style: TextStyle(fontSize: 10, color: AppColors.textdark.withValues(alpha: 0.55))),
          ],
        ),
      ],
    );
  }
}