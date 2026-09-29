import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glass.dart';

/// One entry in either bell's list — the card both notification screens draw,
/// and a single tap target that follows the notification to its content.
///
/// Looks as the cards always have: same surface, radius, border and padding.
/// The whole card is the target, not a link inside it, so it is as easy to hit
/// with a thumb on a phone as with a finger on a tablet, and a chevron marks it
/// as something that goes somewhere.
class NotificationCard extends StatelessWidget {
  const NotificationCard({
    super.key,
    required this.onTap,
    required this.semanticsLabel,
    required this.child,
  });

  final VoidCallback onTap;
  final String semanticsLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: AppColors.isDark ? Glass.edge : AppColors.textdark.withValues(alpha: 0.2)),
    );

    return Semantics(
      button: true,
      label: semanticsLabel,
      hint: 'Opens what this notification is about',
      excludeSemantics: true,
      child: Material(
        color: Glass.card,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(child: child),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, size: 20, color: AppColors.textdark.withValues(alpha: 0.4)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
