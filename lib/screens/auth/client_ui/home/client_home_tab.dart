import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../data/client_account_store.dart';
import '../../../../data/motorcycle_problem.dart';
import '../../../../data/points_wallet_store.dart';
import '../../../../data/quote_store.dart';
import '../../../../services/backend/mobile_backend.dart';
import '../../../../theme/app_theme.dart';
import '../rewards/client_rewards_screen.dart';
import 'book_help_screen.dart';

/// The client's home, laid out like a ride-hailing app's: a band in the
/// brand colour with the wordmark, a search-shaped prompt and the points
/// balance, then a white sheet with the services as a grid of pictures and
/// a pair of promo cards.
///
/// A service tile is the start of a booking, not a form: the details, the
/// place and the urgency come afterwards in [BookHelpScreen].
class ClientHomeTab extends StatelessWidget {
  /// Called once a booking has been taken, so the shell can show it.
  final ValueChanged<ServiceRequest>? onBooked;

  /// The bell in the band.
  final VoidCallback? onOpenNotifications;

  /// The shell's notice that a finished job still wants an evaluation. It
  /// sits at the top of the sheet here, since the band takes the top edge.
  final Widget? banner;

  const ClientHomeTab({super.key, this.onBooked, this.onOpenNotifications, this.banner});

  Future<void> _book(BuildContext context, MotorcycleProblem problem) async {
    final booked = await Navigator.push<ServiceRequest>(
      context,
      MaterialPageRoute(builder: (_) => BookHelpScreen(problem: problem)),
    );
    if (booked != null) onBooked?.call(booked);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final layout = context.layout;
    // How much larger than written the tile names come out.
    final labelScale = MediaQuery.textScalerOf(context).scale(11.5) / 11.5;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The clock sits on the band, so it is drawn light on every theme.
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: ColoredBox(
        color: c.primary,
        child: Column(
          children: [
            _HomeBand(
              onOpenNotifications: onOpenNotifications,
              onSearch: () => _book(context, MotorcycleProblem.somethingElse),
              onPoints: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ClientRewardsScreen()),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: ColoredBox(
                  color: c.surface,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(layout.gutter, 8, layout.gutter, 24),
                    children: [
                      ?banner,
                      const SizedBox(height: 12),
                      // Four across, the way a service grid reads: a picture
                      // on a soft tile, a word under it, nothing boxing them.
                      GridView(
                        // Explicit, or the grid would take the window's
                        // status-bar inset as its own top padding.
                        padding: EdgeInsets.zero,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          // The tile: a 56 square, a gap, and a two-line name
                          // at whatever size the reader has set text to.
                          mainAxisExtent: 74 + 28 * labelScale,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                        ),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          for (final problem in MotorcycleProblem.values)
                            _ServiceTile(problem: problem, onTap: () => _book(context, problem)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _PromoCard(
                                picture: MotorcycleProblem.motorcyclePicture,
                                tint: c.primary,
                                title: 'Help comes to you',
                                text: 'Mechanics ride out to wherever you are.',
                                onTap: () => _book(context, MotorcycleProblem.wontStart),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _PromoCard(
                                picture: MotorcycleProblem.tuneUp.picture,
                                tint: c.info,
                                title: 'Quotes first, pay after',
                                text: 'Compare offers and pay when the job is done.',
                                onTap: () => _book(context, MotorcycleProblem.tuneUp),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The band across the top: menu, wordmark and bell, a search-shaped prompt
/// that starts a free-form booking, and the points balance.
class _HomeBand extends StatelessWidget {
  final VoidCallback? onOpenNotifications;
  final VoidCallback onSearch;
  final VoidCallback onPoints;

  const _HomeBand({required this.onOpenNotifications, required this.onSearch, required this.onPoints});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final top = MediaQuery.paddingOf(context).top;
    final layout = context.layout;

    return Padding(
      padding: EdgeInsets.fromLTRB(layout.gutter - 8, top + 4, layout.gutter - 8, 20),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.menu, color: c.textlight),
                tooltip: 'Menu',
                onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
              ),
              Expanded(
                child: Text(
                  'On Go',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.textlight,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: QuoteNotificationStore.instance,
                builder: (context, _) => NotificationBell(
                  count: QuoteNotificationStore.instance.clientUnreadNotificationCount,
                  onTap: onOpenNotifications,
                  iconColor: c.textlight,
                  badgeColor: c.textdark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Shaped like a search box, because that is what a thumb
                // expects here; it opens a booking to be described in words.
                Material(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onSearch,
                    child: SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          const SizedBox(width: 14),
                          Icon(Icons.search, size: 22, color: c.textmedium),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'What is wrong with your motorcycle?',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, color: c.textmedium),
                            ),
                          ),
                          const SizedBox(width: 14),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _PointsPill(onTap: onPoints),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The client's points, as a small white pill: what a ride-hailing band
/// shows for the wallet. Opens the rewards screen.
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
        return Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: c.surface,
            borderRadius: BorderRadius.circular(999),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.stars_rounded, size: 18, color: c.primary),
                    const SizedBox(width: 6),
                    Text(
                      '${points.toStringAsFixed(0)} pts',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.textdark),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, size: 18, color: c.textmedium),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One service: its picture on a soft tile, a word under it.
class _ServiceTile extends StatelessWidget {
  final MotorcycleProblem problem;
  final VoidCallback onTap;

  const _ServiceTile({required this.problem, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    return Semantics(
      button: true,
      label: 'Book a mechanic: ${problem.label}',
      child: PressScale(
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.borderMd,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Image.asset(
                    problem.picture,
                    width: 36,
                    height: 36,
                    errorBuilder: (_, _, _) => const SizedBox(width: 36, height: 36),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  problem.shortLabel,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, height: 1.2, fontWeight: FontWeight.w600, color: c.textdark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A promo card: a tinted panel with a picture, a line and a word under it.
class _PromoCard extends StatelessWidget {
  final String picture;
  final Color tint;
  final String title;
  final String text;
  final VoidCallback onTap;

  const _PromoCard({
    required this.picture,
    required this.tint,
    required this.title,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    return PressScale(
      child: Material(
        color: tint.withValues(alpha: 0.08),
        borderRadius: AppRadii.borderLg,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset(
                  picture,
                  width: 56,
                  height: 56,
                  errorBuilder: (_, _, _) => const SizedBox(width: 56, height: 56),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.2, color: c.textdark),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: TextStyle(fontSize: 12, height: 1.35, color: c.textmedium),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
