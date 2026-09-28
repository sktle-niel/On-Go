import 'package:flutter/material.dart';

import '../../../../data/client_account_store.dart';
import '../../../../data/motorcycle_problem.dart';
import '../../../../data/quote_store.dart';
import '../../../../services/backend/mobile_backend.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/auth_widgets.dart' show AuthHero;
import '../../../../widgets/glass.dart';
import 'book_help_screen.dart';

/// The client's home, drawn in glass: a greeting and a search-shaped way to
/// describe a problem, the booking under way if there is one, the services
/// as glass tiles, and a card for an emergency.
///
/// A service tile is the start of a booking, not a form: the details, the
/// place and the urgency come afterwards in [BookHelpScreen].
class ClientHomeTab extends StatelessWidget {
  /// Called once a booking has been taken, so the shell can show it.
  final ValueChanged<ServiceRequest>? onBooked;

  /// The booking card opens the Jobs tab.
  final VoidCallback? onOpenJobs;

  const ClientHomeTab({super.key, this.onBooked, this.onOpenJobs});

  Future<void> _book(BuildContext context, MotorcycleProblem problem, {String urgency = 'Normal'}) async {
    final booked = await Navigator.push<ServiceRequest>(
      context,
      MaterialPageRoute(builder: (_) => BookHelpScreen(problem: problem, initialUrgency: urgency)),
    );
    if (booked != null) onBooked?.call(booked);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final layout = context.layout;
    // How much larger than written the tile names come out.
    final labelScale = MediaQuery.textScalerOf(context).scale(11.5) / 11.5;

    return ListView(
      // The last row stays clear of the floating tab bar.
      padding: EdgeInsets.fromLTRB(layout.gutter, 8, layout.gutter, MediaQuery.paddingOf(context).bottom + 16),
      children: [
        // The greeting follows the account, so registering mid-session
        // changes it without a restart.
        AnimatedBuilder(
          animation: ClientAccountStore.instance,
          builder: (context, _) {
            final first = ClientAccountStore.instance.firstName.trim();
            return Text(
              first.isEmpty ? 'Hi there' : 'Hi, $first',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: c.textdark),
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          'What is wrong with your motorcycle?',
          style: TextStyle(fontSize: 15, color: c.textmedium),
        ),
        const SizedBox(height: 16),
        GlassSearchField(
          hint: 'Describe it in your own words',
          onTap: () => _book(context, MotorcycleProblem.somethingElse),
        ),
        const SizedBox(height: 20),
        _BookingUnderWay(onTap: onOpenJobs),
        Text(
          'Services',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.textdark),
        ),
        const SizedBox(height: 14),
        GridView(
          // Explicit, or the grid would take the window's status-bar inset
          // as its own top padding.
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: layout.isTablet ? 6 : 4,
            // The tile: a 62 pane, a gap, and a two-line name at whatever
            // size the reader has set text to.
            mainAxisExtent: 74 + 28 * labelScale,
            mainAxisSpacing: 8,
            crossAxisSpacing: 6,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final problem in MotorcycleProblem.values)
              _ServiceTile(problem: problem, onTap: () => _book(context, problem)),
          ],
        ),
        const SizedBox(height: 16),
        _EmergencyCard(onTap: () => _book(context, MotorcycleProblem.somethingElse, urgency: 'Emergency')),
      ],
    );
  }
}

/// One service: its glyph on a pane of glass, a word under it.
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
      excludeSemantics: true,
      child: PressScale(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            children: [
              GlassPanel(
                radius: 20,
                padding: EdgeInsets.zero,
                child: SizedBox(
                  width: 62,
                  height: 62,
                  child: Center(child: GlassGlyph(problem.icon, size: 28)),
                ),
              ),
              const SizedBox(height: 7),
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
    );
  }
}

/// The booking under way, when there is one: what it is, where it has got
/// to, and a bar for how far. Opens the Jobs tab.
class _BookingUnderWay extends StatelessWidget {
  final VoidCallback? onTap;

  const _BookingUnderWay({this.onTap});

  @override
  Widget build(BuildContext context) {
    final store = QuoteNotificationStore.instance;
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final active = store.myActiveJobs;
        final waiting = store.myPendingRequests;
        final request = active.isNotEmpty ? active.first : (waiting.isNotEmpty ? waiting.first : null);
        if (request == null) return const SizedBox.shrink();

        final c = AppColors.palette;
        final quote = store.acceptedQuoteFor(request.id);
        final mechanic = quote?.mechanicName ?? 'Your mechanic';
        final quotes = store.quotesForRequest(request.id).length;

        final (int stage, String status, String hint, Color accent) = switch (request) {
          _ when request.paymentCompleted => (4, 'Done', 'Paid. Thanks for riding with On Go.', c.success),
          _ when request.serviceCompleted => (4, 'Pay now', 'The work is done. Pay $mechanic to close the job.', c.primary),
          _ when request.workStarted => (3, 'Working', '$mechanic is on it.', c.success),
          _ when request.arrived => (3, 'Arrived', '$mechanic is with you.', c.success),
          _ when request.navigating => (3, 'On the way', '$mechanic is heading to you.', c.info),
          _ when quote != null => (2, 'Booked', '$mechanic will set off soon.', c.success),
          _ when request.isEmergency => (1, 'Finding a mechanic', 'The nearest free mechanic is being asked.', c.error),
          _ when quotes > 0 => (1, '$quotes quote${quotes == 1 ? '' : 's'} in', 'Choose the offer you like.', c.info),
          _ => (1, 'Waiting for quotes', 'Mechanics near you are looking at it.', c.warning),
        };

        return Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: GlassPanel(
            onTap: onTap,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'YOUR BOOKING',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: c.textmedium),
                    ),
                    const Spacer(),
                    Text(status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: accent)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  request.problem.split(':').first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.textdark),
                ),
                const SizedBox(height: 12),
                // Four steps: booked, a mechanic chosen, the work, paid.
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 6,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: Glass.edge),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: stage / 4,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [c.primarydark, c.primary]),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(hint, style: TextStyle(fontSize: 12.5, color: c.textmedium)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The card for when the bike has stopped on the road: a line, a button, and
/// the photo of the trade fading in from the right.
class _EmergencyCard extends StatelessWidget {
  final VoidCallback onTap;

  const _EmergencyCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    return GlassPanel(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          // The photo on the right, fading into the glass towards the words.
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: 170,
            child: ClipRRect(
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(21)),
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.transparent, Colors.black],
                  stops: [0, 0.6],
                ).createShader(bounds),
                child: Image.asset(
                  AuthHero.defaultPhoto,
                  fit: BoxFit.cover,
                  alignment: const Alignment(0.3, 0),
                  color: c.primary,
                  colorBlendMode: BlendMode.multiply,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 128, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'STUCK ON THE ROAD?',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: c.primary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Emergency help',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: c.textdark),
                ),
                const SizedBox(height: 4),
                Text(
                  'The nearest free mechanic comes to you first.',
                  style: TextStyle(fontSize: 12.5, height: 1.35, color: c.textmedium),
                ),
                const SizedBox(height: 14),
                GlassPillButton(label: 'Get help now', onPressed: onTap),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
