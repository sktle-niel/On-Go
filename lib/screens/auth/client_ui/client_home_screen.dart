import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/app_session.dart';
import '../../../data/client_account_store.dart';
import '../../../data/points_wallet_store.dart';
import '../../../data/quote_store.dart';
import '../../../data/review_store.dart';
import '../../../services/location/location_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/evaluation_widgets.dart';
import '../../../widgets/glass.dart';
import 'history/service_history_screen.dart';
import 'home/client_home_tab.dart';
import 'jobs/client_jobs_screen.dart';
import 'menu/client_menu_drawer.dart';
import 'notifications/client_notifications_screen.dart';
import 'rank/rankings_screen.dart';
import 'rewards/client_rewards_screen.dart';

/// The client's app: a glass header, four tabs over a glowing page, and a
/// glass tab bar floating above the bottom edge.
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

  void _openRewards() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ClientRewardsScreen()),
      );

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      // Drawn for glass: they keep their own last row clear of the tab bar.
      ClientHomeTab(onBooked: (_) => _goToTab(1), onOpenJobs: () => _goToTab(1)),
      ClientJobsScreen(onBook: () => _goToTab(0), visible: _currentIndex == 1),
      // Not redrawn yet: held above the tab bar instead.
      const _ClearOfTabBar(child: ServiceHistoryScreen()),
      // Mechanic Rankings — discovery by rank, rating and reviews. The
      // competitive seasonal leaderboard is a separate, future feature.
      const _ClearOfTabBar(child: RankingsScreen()),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Glass.overlay,
      child: Scaffold(
        backgroundColor: AppColors.background,
        // The page runs on under the floating tab bar.
        extendBody: true,
        drawer: const ClientMenuDrawer(),
        body: GlassBackdrop(
          child: Column(
            children: [
              _GlassHeader(onOpenNotifications: _openNotifications, onOpenRewards: _openRewards),
              // Stays until every completed job is evaluated — on every tab,
              // across restarts, without ever blocking the app.
              const PendingEvaluationBanner(),
              Expanded(child: IndexedStack(index: _currentIndex, children: tabs)),
            ],
          ),
        ),
        bottomNavigationBar: GlassNavBar(
          currentIndex: _currentIndex,
          onTap: _goToTab,
          items: const [
            GlassNavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
            GlassNavItem(icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long_rounded, label: 'Jobs'),
            GlassNavItem(icon: Icons.history_rounded, label: 'History'),
            GlassNavItem(icon: Icons.emoji_events_outlined, activeIcon: Icons.emoji_events_rounded, label: 'Rankings'),
          ],
        ),
      ),
    );
  }
}

/// A tab not yet drawn for glass, held above the floating tab bar so its
/// last row is never under it.
class _ClearOfTabBar extends StatelessWidget {
  final Widget child;

  const _ClearOfTabBar({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: MediaQuery.removePadding(context: context, removeBottom: true, child: child),
    );
  }
}

/// The header over every tab: the wordmark, the points, the bell and the
/// account, which opens the menu.
class _GlassHeader extends StatelessWidget {
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenRewards;

  const _GlassHeader({required this.onOpenNotifications, required this.onOpenRewards});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final layout = context.layout;
    final top = MediaQuery.paddingOf(context).top;

    return Padding(
      padding: EdgeInsets.fromLTRB(layout.gutter, top + 6, layout.gutter - 6, 6),
      child: Row(
        children: [
          // "On" in ink, "Go" in the brand colour. A logo, so on a narrow
          // phone with large text it shrinks to fit rather than pushing the
          // buttons off the edge.
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    text: 'On ',
                    children: [TextSpan(text: 'Go', style: TextStyle(color: c.primary))],
                  ),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    letterSpacing: -0.6,
                    color: c.textdark,
                  ),
                ),
              ),
            ),
          ),
          _PointsPill(onTap: onOpenRewards),
          const SizedBox(width: 2),
          AnimatedBuilder(
            animation: QuoteNotificationStore.instance,
            builder: (context, _) => _Badged(
              count: QuoteNotificationStore.instance.clientUnreadNotificationCount,
              child: GlassIconButton(
                icon: Icons.notifications_none_rounded,
                tooltip: 'Notifications',
                onPressed: onOpenNotifications,
              ),
            ),
          ),
          Builder(
            builder: (context) => _AccountButton(onTap: () => Scaffold.of(context).openDrawer()),
          ),
        ],
      ),
    );
  }
}

/// The client's points as a white pill, the way a ride-hailing header shows
/// the wallet. Opens the rewards.
class _PointsPill extends StatelessWidget {
  final VoidCallback onTap;

  const _PointsPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    return AnimatedBuilder(
      animation: Listenable.merge([PointsWalletStore.instance, ClientAccountStore.instance]),
      builder: (context, _) {
        final points = PointsWalletStore.instance.balanceFor(ClientAccountStore.instance.name);
        return Semantics(
          button: true,
          label: 'Rewards, ${points.toStringAsFixed(0)} points',
          excludeSemantics: true,
          child: PressScale(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                customBorder: const StadiumBorder(),
                child: Ink(
                  padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
                  decoration: ShapeDecoration(shape: const StadiumBorder(), color: Glass.contrast),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: c.primary),
                        child: Icon(Icons.star_rounded, size: 15, color: c.textlight),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        points.toStringAsFixed(0),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Glass.onContrast),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The client's initials on glass. Opens the menu.
class _AccountButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AccountButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    return AnimatedBuilder(
      animation: ClientAccountStore.instance,
      builder: (context, _) {
        final account = ClientAccountStore.instance;
        final initials = [account.firstName, account.lastName]
            .map((w) => w.trim())
            .where((w) => w.isNotEmpty)
            .map((w) => w[0].toUpperCase())
            .join();
        return Tooltip(
          message: 'Menu',
          child: Semantics(
            button: true,
            label: 'Menu',
            excludeSemantics: true,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: onTap,
                    customBorder: const CircleBorder(),
                    child: Ink(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color.lerp(c.primary, Colors.white, 0.2)!, c.primarydark],
                        ),
                        border: Border.all(color: Glass.edge, width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          initials.isEmpty ? '?' : initials,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c.textlight),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A count in the brand colour on the corner of a round button.
class _Badged extends StatelessWidget {
  final int count;
  final Widget child;

  const _Badged({required this.count, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    if (count <= 0) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: 2,
          top: 2,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 18),
              decoration: BoxDecoration(
                color: c.primary,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.background, width: 1.5),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: c.textlight),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
