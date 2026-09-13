import 'package:flutter/material.dart';
import '../../../data/app_session.dart';
import '../../../data/mechanic_notification_store.dart';
import '../../../data/quote_store.dart';
import '../../../data/mechanic_account_store.dart';
import 'package:on_go_shared/on_go_shared.dart';

import '../../../services/location/location_reporter.dart';
import '../../../services/location/location_service.dart';
import '../../../theme/app_theme.dart';
import 'jobs/jobs_screen.dart';
import 'notifications/mechanic_notifications_screen.dart';
import 'earning/earning_screen.dart';
import 'qr/qr_screen.dart';
import 'rank/mechanic_leaderboard_screen.dart';
import 'profile/mechanic_profile_screen.dart';
import 'menu/mechanic_menu_drawer.dart';

class MechanicHomeScreen extends StatefulWidget {
  const MechanicHomeScreen({super.key});

  @override
  State<MechanicHomeScreen> createState() => _MechanicHomeScreenState();
}

class _MechanicHomeScreenState extends State<MechanicHomeScreen> {
  int _currentIndex = 0;

  // Positions in [build]'s tab list.
  static const int _jobsTab = 0;
  static const int _earningTab = 1;
  static const int _profileTab = 4;

  /// How a notification asks the Jobs tab to open one particular job.
  final _jobFocus = ValueNotifier<JobFocusRequest?>(null);

  /// The mechanic's live location, reported onward so a backend can keep their
  /// last known position for nearby-job matching.
  late final LocationReporter _locationReporter = LocationReporter(
    role: LocationRole.mechanic,
    availability: () {
      final me = QuoteNotificationStore.currentMechanicName;
      if (!MechanicAccountStore.instance.canPerformJobActions) return MechanicAvailability.offline;
      return QuoteNotificationStore.instance.matchedJobsFor(me).isEmpty
          ? MechanicAvailability.available
          : MechanicAvailability.onJob;
    },
  );

  @override
  void initState() {
    super.initState();
    AppSession.instance.setRole(AppRole.mechanic, viewerName: QuoteNotificationStore.currentMechanicName);
    _locationReporter.start();
    // The one-time prompt, then live location while the app is open — live
    // updates pause by themselves whenever the app leaves the screen. Tracking
    // never prompts; if the mechanic declines, it simply stays off.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await LocationService.instance.promptOnFirstUse();
      if (mounted) LocationService.instance.startTracking();
    });
  }

  @override
  void dispose() {
    LocationService.instance.stopTracking();
    _locationReporter.stop();
    _jobFocus.dispose();
    super.dispose();
  }

  void _goToTab(int index) => setState(() => _currentIndex = index);

  /// Opening the list is what counts as "viewing" them, so the badge clears
  /// here — same as the Client bell.
  ///
  /// A notification about something inside this shell comes back as the
  /// route the list closed with, and is carried out here.
  Future<void> _openNotifications() async {
    MechanicNotificationStore.instance.markSeenFor(QuoteNotificationStore.currentMechanicName);
    final route = await Navigator.push<NotificationRoute>(
      context,
      MaterialPageRoute(builder: (_) => const MechanicNotificationsScreen()),
    );
    if (!mounted || route == null) return;

    switch (route) {
      case OpenJobInList(:final requestId, :final emergency):
        _goToTab(_jobsTab);
        _jobFocus.value = JobFocusRequest(requestId, emergency: emergency);
      case OpenMechanicTab(:final tab):
        _goToTab(switch (tab) {
          MechanicHomeTab.jobs => _jobsTab,
          MechanicHomeTab.earning => _earningTab,
          MechanicHomeTab.profile => _profileTab,
        });
      case OpenJobQuotes() || OpenClientJob() || OpenMechanicJob() || NotificationUnavailable():
        // Handled on the notifications screen itself, or not a mechanic route.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      JobsScreen(focus: _jobFocus),
      EarningScreen(onViewAll: () => _goToTab(3)),
      const QrScreen(),
      const MechanicLeaderboardScreen(),
      const MechanicProfileScreen(standalone: false),
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: OnGoAppBar(
        notificationAction: AnimatedBuilder(
          animation: MechanicNotificationStore.instance,
          builder: (context, _) => NotificationBell(
            count: MechanicNotificationStore.instance
                .unreadCountFor(QuoteNotificationStore.currentMechanicName),
            onTap: _openNotifications,
            badgeColor: AppColors.warning,
          ),
        ),
      ),
      drawer: const MechanicMenuDrawer(),
      body: IndexedStack(index: _currentIndex, children: tabs),
      bottomNavigationBar: OnGoBottomNav(
        currentIndex: _currentIndex,
        onTap: _goToTab,
        items: const [
          OnGoNavItem(icon: Icons.work_outline, activeIcon: Icons.work, label: 'Jobs'),
          OnGoNavItem(icon: Icons.payments_outlined, activeIcon: Icons.payments, label: 'Earning'),
          OnGoNavItem(icon: Icons.qr_code_scanner, label: 'QR'),
          OnGoNavItem(icon: Icons.emoji_events_outlined, activeIcon: Icons.emoji_events, label: 'Leaderboard'),
          OnGoNavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profile'),
        ],
      ),
    );
  }
}