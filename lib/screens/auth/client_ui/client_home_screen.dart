import 'package:flutter/material.dart';
import '../../../data/app_session.dart';
import '../../../data/quote_store.dart';
import '../../../data/review_store.dart';
import '../../../services/location/location_service.dart';
import '../../../theme/app_theme.dart';
import 'home/need_help_screen.dart';
import 'notifications/client_notifications_screen.dart';
import 'jobs/client_jobs_screen.dart';
import 'history/service_history_screen.dart';
import 'rank/leaderboard_screen.dart';
import 'menu/client_menu_drawer.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    AppSession.instance.setRole(AppRole.client, viewerName: ReviewStore.currentClientName);
    // The one-time location prompt — the operating system's own dialog, shown
    // after the first frame so it lands over the app rather than a blank
    // screen, and never again once the user has decided either way.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) LocationService.instance.promptOnFirstUse();
    });
  }

  void _goToTab(int index) => setState(() => _currentIndex = index);

  /// Opening the list is what counts as "viewing" them, so the badge clears
  /// here — same as the Mechanic bell.
  Future<void> _openNotifications() async {
    QuoteNotificationStore.instance.markClientNotificationsSeen();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ClientNotificationsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      NeedHelpScreen(onRequestUploaded: () => _goToTab(1)),
      const ClientJobsScreen(),
      const ServiceHistoryScreen(),
      const LeaderboardScreen(),
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: OnGoAppBar(
        notificationAction: AnimatedBuilder(
          animation: QuoteNotificationStore.instance,
          builder: (context, _) => NotificationBell(
            count: QuoteNotificationStore.instance.clientUnreadNotificationCount,
            onTap: _openNotifications,
            badgeColor: AppColors.warning,
          ),
        ),
      ),
      drawer: const ClientMenuDrawer(),
      body: IndexedStack(index: _currentIndex, children: tabs),
      bottomNavigationBar: OnGoBottomNav(
        currentIndex: _currentIndex,
        onTap: _goToTab,
        items: const [
          OnGoNavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
          OnGoNavItem(icon: Icons.work_outline, activeIcon: Icons.work, label: 'Jobs'),
          OnGoNavItem(icon: Icons.history, label: 'History'),
          OnGoNavItem(icon: Icons.emoji_events_outlined, activeIcon: Icons.emoji_events, label: 'Leaderboard'),
        ],
      ),
    );
  }
}