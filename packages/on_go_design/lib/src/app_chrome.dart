import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'design_tokens.dart';

/// The product's app bar: a menu button that opens the drawer, the "On Go"
/// wordmark with a subtitle naming the shell, an optional secondary action,
/// and a notification bell.
///
/// It sits on the page's own surface with a hairline under it. The brand
/// colour appears once, in the wordmark; the icons are ink, so the bar reads
/// as part of the page rather than a band across the top of it.
///
/// Shared by the mobile app and, on a phone-sized window, the admin console —
/// so an admin opening the console on their phone gets the same bar a client
/// gets in the app, not a lookalike.
class OnGoAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// The line under "On Go" — 'Service Anywhere', 'Admin Panel',
  /// 'Moderator Panel'.
  final String subtitle;

  final bool showMenuButton;

  /// An extra action left of the bell (the client's "Uploaded" button).
  final Widget? secondaryAction;

  /// The bell. Null renders no bell at all — every caller that wants one
  /// passes it, because what the count means and where the tap goes is the
  /// caller's business, not this widget's.
  final Widget? notificationAction;

  const OnGoAppBar({
    super.key,
    this.subtitle = 'Service Anywhere',
    this.showMenuButton = true,
    this.secondaryAction,
    this.notificationAction,
  });

  static const double height = 60;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppBar(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: height,
      centerTitle: false,
      automaticallyImplyLeading: false,
      shape: Border(bottom: AppHairline.side(AppColors.textmedium)),
      leading: showMenuButton
          ? IconButton(
              icon: Icon(Icons.menu, color: AppColors.textdark),
              tooltip: 'Menu',
              onPressed: () => Scaffold.of(context).openDrawer(),
            )
          : null,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'On Go',
            style: textTheme.titleLarge?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              height: 1.1,
            ),
          ),
          Text(
            subtitle,
            style: textTheme.bodySmall?.copyWith(color: AppColors.textmedium, height: 1.2),
          ),
        ],
      ),
      actions: [
        ?secondaryAction,
        ?notificationAction,
        const SizedBox(width: 4),
      ],
    );
  }
}

/// The bell, with a count badge once there is something to count.
class NotificationBell extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;

  // Null means "use the active theme's color", resolved at build time so a
  // theme change repaints the bell.
  final Color? badgeColor;
  final Color? iconColor;

  const NotificationBell({
    super.key,
    required this.count,
    this.onTap,
    this.badgeColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(Icons.notifications_none, color: iconColor ?? AppColors.textdark),
          tooltip: 'Notifications',
          onPressed: onTap,
        ),
        if (count > 0)
          Positioned(
            right: 6,
            top: 8,
            // The badge sits over the middle of the icon, and an opaque
            // Container would swallow a tap there instead of letting the
            // IconButton behind it fire. It is decoration, not a target.
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                decoration: BoxDecoration(
                  color: badgeColor ?? AppColors.primary,
                  borderRadius: BorderRadius.circular(9),
                  // A ring in the bar's own colour lifts the badge off the
                  // icon without a shadow.
                  border: Border.all(color: AppColors.surface, width: 1.5),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: AppColors.textlight,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
