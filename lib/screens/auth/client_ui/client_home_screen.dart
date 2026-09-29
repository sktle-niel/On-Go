import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/app_session.dart';
import '../../../data/quote_store.dart';
import '../../../data/review_store.dart';
import '../../../services/backend/mobile_backend.dart' show GeoPoint;
import '../../../services/location/location_service.dart';
import '../../../services/location/place_sources.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/evaluation_widgets.dart';
import '../../../widgets/glass.dart';
import 'history/service_history_screen.dart';
import 'home/client_home_tab.dart';
import 'jobs/client_jobs_screen.dart';
import 'menu/client_menu_drawer.dart';
import 'notifications/client_notifications_screen.dart';
import 'rank/rankings_screen.dart';

/// The client's app: a header with the menu, the client's place and the bell,
/// four tabs, and a tab bar floating above the bottom edge.
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
              _AppHeader(onOpenNotifications: _openNotifications),
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

//// The header over every tab, laid out the way a ride-hailing app has it: the
/// menu on the left, the client's place in the middle, the bell on the right.
class _AppHeader extends StatelessWidget {
  final VoidCallback onOpenNotifications;

  const _AppHeader({required this.onOpenNotifications});

  @override
  Widget build(BuildContext context) {
    final layout = context.layout;
    final top = MediaQuery.paddingOf(context).top;

    return Padding(
      padding: EdgeInsets.fromLTRB(layout.gutter - 6, top + 6, layout.gutter - 6, 6),
      child: Row(
        children: [
          Builder(
            builder: (context) => GlassIconButton(
              icon: Icons.menu_rounded,
              tooltip: 'Menu',
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          const Expanded(child: Center(child: _LocationPill())),
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
        ],
      ),
    );
  }
}

/// Where the client is, as a pill: the town from the phone's last fix, named
/// by the phone's own geocoder. Tapping it takes a fresh fix, asking for
/// location access first if the client has not given it.
class _LocationPill extends StatefulWidget {
  const _LocationPill();

  @override
  State<_LocationPill> createState() => _LocationPillState();
}

class _LocationPillState extends State<_LocationPill> {
  final _location = LocationService.instance;

  /// The fix [_place] was named for, so a new fix is named once.
  GeoPoint? _namedPoint;
  String? _place;

  @override
  void initState() {
    super.initState();
    _location.addListener(_onLocation);
    _onLocation();
  }

  @override
  void dispose() {
    _location.removeListener(_onLocation);
    super.dispose();
  }

  void _onLocation() {
    if (mounted) setState(() {});
    final point = _location.bestKnown?.point;
    final geocoder = PlaceSources.geocoder;
    if (point == null || geocoder == null || point == _namedPoint) return;
    _namedPoint = point;
    geocoder.placeAt(point).then((place) {
      if (!mounted || place == null || _namedPoint != point) return;
      final town = [place.cityMunicipality, place.province].whereType<String>().where((s) => s.trim().isNotEmpty);
      setState(() => _place = town.isEmpty ? place.name : town.join(', '));
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final label = _place ??
        (_location.isLocating
            ? 'Locating…'
            : (_location.bestKnown != null ? 'Current location' : 'Set your location'));

    return Semantics(
      button: true,
      label: 'Your location: $label',
      excludeSemantics: true,
      child: PressScale(
        // The shadow sits outside the Material, whose ink is clipped to a
        // rectangle.
        child: DecoratedBox(
          decoration: ShapeDecoration(shape: const StadiumBorder(), shadows: Glass.lift),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => _location.locate(),
              customBorder: const StadiumBorder(),
              child: Ink(
                height: 40,
                padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
                decoration: ShapeDecoration(
                  shape: StadiumBorder(side: BorderSide(color: Glass.edge)),
                  color: Glass.card,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_on_rounded, size: 18, color: c.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.textdark),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: c.textmedium),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// A count in the brand colour on the corner of a round button.
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
