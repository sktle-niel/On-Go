import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../data/client_account_store.dart';
import '../../../../data/motorcycle_problem.dart';
import '../../../../data/quote_store.dart' show acceptedQuoteOf;
import '../../../../services/backend/mobile_backend.dart';
import '../../../../services/location/location_service.dart';
import '../../../../theme/app_theme.dart';
import '../../../../utils/coalesced_load.dart';
import '../../../../widgets/glass.dart';
import 'book_help_screen.dart';

/// The client's home, laid out like a ride-hailing app's: a greeting, a card
/// with where the client is and what is wrong, the booking under way if there
/// is one, chips that sort the services, a card for an emergency, and the
/// services as cards to book from.
///
/// A service card is the start of a booking, not a form: the details, the
/// place and the urgency come afterwards in [BookHelpScreen].
class ClientHomeTab extends StatefulWidget {
  /// Called once a booking has been taken, so the shell can show it.
  final ValueChanged<ServiceRequest>? onBooked;

  /// The booking card opens the Jobs tab.
  final VoidCallback? onOpenJobs;

  const ClientHomeTab({super.key, this.onBooked, this.onOpenJobs});

  @override
  State<ClientHomeTab> createState() => _ClientHomeTabState();
}

class _ClientHomeTabState extends State<ClientHomeTab> {
  /// The chip picked; null is "All".
  ServiceKind? _kind;
  bool _showAllServices = false;

  /// Bumped after a booking, so the booking card reads the backend again
  /// rather than wait for the event.
  int _bookings = 0;

  /// Services listed before "View all".
  static const int _preview = 4;

  Future<void> _book(MotorcycleProblem problem, {String urgency = 'Normal'}) async {
    final booked = await Navigator.push<ServiceRequest>(
      context,
      MaterialPageRoute(builder: (_) => BookHelpScreen(problem: problem, initialUrgency: urgency)),
    );
    if (booked == null) return;
    if (mounted) setState(() => _bookings++);
    widget.onBooked?.call(booked);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final layout = context.layout;
    final services = [
      for (final problem in MotorcycleProblem.values)
        if (_kind == null || problem.kind == _kind) problem,
    ];
    final shown = _showAllServices ? services : services.take(_preview).toList();

    return ListView(
      // The last card stays clear of the floating tab bar.
      padding: EdgeInsets.fromLTRB(layout.gutter, 4, layout.gutter, MediaQuery.paddingOf(context).bottom + 16),
      children: [
        const _Greeting(),
        const SizedBox(height: 16),
        _RequestCard(onDescribe: () => _book(MotorcycleProblem.somethingElse)),
        const SizedBox(height: 16),
        _BookingUnderWay(refresh: _bookings, onTap: widget.onOpenJobs),
        _KindChips(
          selected: _kind,
          onSelected: (kind) => setState(() {
            _kind = kind;
            _showAllServices = false;
          }),
        ),
        const SizedBox(height: 18),
        _EmergencyCard(onTap: () => _book(MotorcycleProblem.somethingElse, urgency: 'Emergency')),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: Text(
                _kind == null ? 'Services' : _kind!.label,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.textdark),
              ),
            ),
            if (services.length > _preview)
              TextButton(
                onPressed: () => setState(() => _showAllServices = !_showAllServices),
                style: TextButton.styleFrom(
                  foregroundColor: c.textmedium,
                  minimumSize: const Size(48, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  _showAllServices ? 'Show less' : 'View all',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final problem in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ServiceCard(problem: problem, onBook: () => _book(problem)),
          ),
      ],
    );
  }
}

/// "Hello, Carla" and what the app is for, under it.
class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The greeting follows the account, so registering mid-session
        // changes it without a restart.
        AnimatedBuilder(
          animation: ClientAccountStore.instance,
          builder: (context, _) {
            final first = ClientAccountStore.instance.firstName.trim();
            return Text(
              first.isEmpty ? 'Hello there' : 'Hello, $first',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: c.textdark),
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          'Book a mechanic who comes to you.',
          style: TextStyle(fontSize: 14.5, color: c.textmedium),
        ),
      ],
    );
  }
}

/// Where the client is and what is wrong, one above the other and joined by a
/// dotted line, the way a ride app pairs a pickup with a destination. The
/// first row takes a fresh location fix; the second starts a booking.
class _RequestCard extends StatelessWidget {
  final VoidCallback onDescribe;

  const _RequestCard({required this.onDescribe});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final location = LocationService.instance;
    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: location,
            builder: (context, _) => _RequestRow(
              marker: _Marker.from,
              label: 'Your location',
              value: location.bestKnown != null
                  ? 'Current location'
                  : (location.isLocating ? 'Locating…' : 'Tap to share your location'),
              onTap: () => location.locate(),
              trailing: Icon(Icons.my_location_rounded, size: 20, color: c.textdark),
              trailingTooltip: 'Use my location',
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 48, right: 16),
            child: Divider(height: 1, thickness: 1, color: Glass.edge),
          ),
          _RequestRow(
            marker: _Marker.to,
            label: 'Problem',
            value: 'Describe what is wrong',
            muted: true,
            onTap: onDescribe,
            trailing: Icon(Icons.chevron_right_rounded, size: 22, color: c.textmedium),
          ),
        ],
      ),
    );
  }
}

/// Which end of the dotted line a row sits at.
enum _Marker { from, to }

class _RequestRow extends StatelessWidget {
  final _Marker marker;
  final String label;
  final String value;

  /// A prompt rather than a value: drawn in the quieter colour.
  final bool muted;
  final VoidCallback onTap;
  final Widget trailing;
  final String? trailingTooltip;

  const _RequestRow({
    required this.marker,
    required this.label,
    required this.value,
    required this.onTap,
    required this.trailing,
    this.muted = false,
    this.trailingTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    return Semantics(
      button: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 48,
                child: CustomPaint(
                  painter: _MarkerPainter(
                    marker: marker,
                    color: c.primary,
                    ring: c.textmedium,
                    line: c.textmedium.withValues(alpha: 0.45),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(label, style: TextStyle(fontSize: 11.5, color: c.textmedium)),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: muted ? FontWeight.w500 : FontWeight.w600,
                          color: muted ? c.textmedium : c.textdark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 48,
                child: Center(
                  child: trailingTooltip == null ? trailing : Tooltip(message: trailingTooltip!, child: trailing),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dot or ring at the row's centre, and its half of the dotted line that
/// joins the two rows across the divider.
class _MarkerPainter extends CustomPainter {
  final _Marker marker;
  final Color color;
  final Color ring;
  final Color line;

  const _MarkerPainter({required this.marker, required this.color, required this.ring, required this.line});

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final dots = Paint()..color = line;
    // The line runs down from the first marker and up into the second.
    final (double from, double to) =
        marker == _Marker.from ? (centre.dy + 11, size.height) : (0, centre.dy - 11);
    for (var y = from; y < to; y += 6) {
      canvas.drawCircle(Offset(centre.dx, y + 1), 1.2, dots);
    }
    if (marker == _Marker.from) {
      canvas.drawCircle(centre, 7, Paint()..color = color.withValues(alpha: 0.18));
      canvas.drawCircle(centre, 4, Paint()..color = color);
    } else {
      canvas.drawCircle(
        centre,
        5.5,
        Paint()
          ..color = ring
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_MarkerPainter old) =>
      old.marker != marker || old.color != color || old.ring != ring || old.line != line;
}

/// The chips that sort the services: All, then one per kind.
class _KindChips extends StatelessWidget {
  final ServiceKind? selected;
  final ValueChanged<ServiceKind?> onSelected;

  const _KindChips({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    const kinds = [ServiceKind.repair, ServiceKind.maintenance, ServiceKind.towing];
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        // Room for the chips' shadows at either end.
        clipBehavior: Clip.none,
        children: [
          _KindChip(
            label: 'All',
            picture: servicePicture('all'),
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final kind in kinds) ...[
            const SizedBox(width: 10),
            _KindChip(
              label: kind.label,
              picture: kind.picture,
              selected: selected == kind,
              onTap: () => onSelected(kind),
            ),
          ],
        ],
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  final String label;
  final String picture;
  final bool selected;
  final VoidCallback onTap;

  const _KindChip({required this.label, required this.picture, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final ink = selected ? c.textlight : c.textdark;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: selected ? BorderSide.none : BorderSide(color: Glass.edge),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: PressScale(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            customBorder: shape,
            child: AnimatedContainer(
              duration: AppMotion.fast,
              curve: AppMotion.enter,
              padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
              decoration: ShapeDecoration(
                shape: shape,
                color: selected ? c.primary : Glass.card,
                shadows: selected
                    ? [BoxShadow(color: c.primary.withValues(alpha: 0.28), blurRadius: 12, offset: const Offset(0, 4))]
                    : Glass.lift,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // A white disc keeps the icon's colours clear of the red.
                  AnimatedContainer(
                    duration: AppMotion.fast,
                    width: 30,
                    height: 30,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? Colors.white : c.primary.withValues(alpha: AppColors.isDark ? 0.18 : 0.08),
                    ),
                    child: Image.asset(picture, excludeFromSemantics: true),
                  ),
                  const SizedBox(width: 8),
                  Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: ink)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The card for when the bike has stopped on the road: in the brand tint,
/// with a line, a dark button, and a drawing of a mechanic at work on a
/// scooter on the right.
class _EmergencyCard extends StatelessWidget {
  final VoidCallback onTap;

  const _EmergencyCard({required this.onTap});

  /// A drawing on a white ground (see assets/images/README.md).
  static const String _emergencyPicture = 'assets/images/emergency_card.jpg';

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final radius = BorderRadius.circular(22);
    // The shadow sits outside the Material, whose ink is clipped to a
    // rectangle.
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: Glass.lift),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(c.primary.withValues(alpha: AppColors.isDark ? 0.30 : 0.14), c.surface),
                  Color.alphaBlend(c.primary.withValues(alpha: AppColors.isDark ? 0.14 : 0.05), c.surface),
                ],
              ),
            ),
            // The photo takes the height the words need; a list gives the card
            // no height of its own.
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 8, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Stuck on the road?',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.textdark),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Emergency help',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                              color: c.primarydark,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'The nearest free mechanic comes to you first.',
                            style: TextStyle(fontSize: 12.5, height: 1.35, color: c.textdark),
                          ),
                          const SizedBox(height: 14),
                          _ArrowPill(label: 'Get help now', onTap: onTap),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 132,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
                      // The drawing is on white. On a light card it is
                      // multiplied by the card's own tint, so its white turns
                      // into the card and the drawing sits on it with no box.
                      // A dark card cannot take that, so there it keeps a
                      // white tile.
                      child: AppColors.isDark
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: ColoredBox(
                                color: Colors.white,
                                child: Image.asset(
                                  _emergencyPicture,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                                ),
                              ),
                            )
                          : Image.asset(
                              _emergencyPicture,
                              fit: BoxFit.contain,
                              alignment: Alignment.bottomCenter,
                              color: Color.alphaBlend(c.primary.withValues(alpha: 0.08), c.surface),
                              colorBlendMode: BlendMode.multiply,
                              errorBuilder: (_, _, _) => const SizedBox.shrink(),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A dark pill with an arrow after its label: "Get help now →".
class _ArrowPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ArrowPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Ink(
            height: 38,
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
            decoration: ShapeDecoration(shape: const StadiumBorder(), color: Glass.contrast),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Glass.onContrast),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.arrow_forward_rounded, size: 16, color: Glass.onContrast),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One service to book: its icon on a tinted tile, what it is, what the
/// mechanic does about it, and the button.
class _ServiceCard extends StatelessWidget {
  final MotorcycleProblem problem;
  final VoidCallback onBook;

  const _ServiceCard({required this.problem, required this.onBook});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    return Semantics(
      container: true,
      label: 'Book a mechanic: ${problem.label}',
      child: GlassPanel(
        radius: 20,
        padding: const EdgeInsets.all(12),
        onTap: onBook,
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: AppColors.isDark ? 0.18 : 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(12),
              child: Image.asset(problem.picture, excludeFromSemantics: true),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    problem.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.textdark),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    problem.blurb,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, height: 1.3, color: c.textmedium),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            GlassPillButton(label: 'Book', onPressed: onBook, style: GlassPillStyle.brand),
          ],
        ),
      ),
    );
  }
}

/// The booking under way, when there is one: what it is, where it has got
/// to, and a bar for how far. Read from the backend, so it shows a job the
/// server holds as well as one on the device. Opens the Jobs tab.
class _BookingUnderWay extends StatefulWidget {
  /// A new value reads the backend again, as after a booking.
  final int refresh;
  final VoidCallback? onTap;

  const _BookingUnderWay({required this.refresh, this.onTap});

  @override
  State<_BookingUnderWay> createState() => _BookingUnderWayState();
}

class _BookingUnderWayState extends State<_BookingUnderWay> with CoalescedLoad<_BookingUnderWay> {
  ServiceRequestApi get _api => MobileBackend.instance.serviceRequests;

  ServiceRequest? _request;
  JobQuote? _accepted;
  int _liveQuotes = 0;
  final _watches = <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    reload();
    _watches
      ..add(_api.watchRequests().listen((_) => reload()))
      ..add(_api.watchQuotes().listen((_) => reload()));
  }

  @override
  void didUpdateWidget(_BookingUnderWay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refresh != oldWidget.refresh) reload();
  }

  @override
  void dispose() {
    for (final watch in _watches) {
      watch.cancel();
    }
    super.dispose();
  }

  @override
  Future<void> read() async {
    try {
      final mine = await _api.listMyRequests();
      // The job under way first; otherwise the newest one still waiting.
      final matched = mine.where((r) => r.status == ServiceRequestStatus.matched);
      final pending = mine.where((r) => r.status == ServiceRequestStatus.pending).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final request = matched.isNotEmpty ? matched.first : (pending.isEmpty ? null : pending.first);
      final quotes = request == null ? const <JobQuote>[] : await _api.listQuotes(request.id);
      if (!mounted) return;
      setState(() {
        _request = request;
        _accepted = acceptedQuoteOf(quotes);
        _liveQuotes = quotes.where((q) => q.isLive).length;
      });
    } on ApiException {
      // The home stays usable without the card; the Jobs tab says what failed.
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    if (request == null) return const SizedBox.shrink();

    final c = AppColors.palette;
    final mechanic = request.mechanicName ?? _accepted?.mechanicName ?? 'Your mechanic';
    final quotes = _liveQuotes;
    final matched = request.status == ServiceRequestStatus.matched;

    final (int stage, String status, String hint, Color accent) = switch (request) {
      _ when matched && request.serviceCompleted =>
        (4, 'Pay now', 'The work is done. Pay $mechanic to close the job.', c.primary),
      _ when matched && request.workStarted => (3, 'Working', '$mechanic is on it.', c.success),
      _ when matched && request.arrived => (3, 'Arrived', '$mechanic is with you.', c.success),
      _ when matched && request.navigating => (3, 'On the way', '$mechanic is heading to you.', c.info),
      _ when matched => (2, 'Booked', '$mechanic sets off soon.', c.success),
      _ when request.isEmergency => (1, 'Finding a mechanic', 'On Go is asking the nearest free mechanic.', c.error),
      _ when quotes > 0 => (1, '$quotes quote${quotes == 1 ? '' : 's'} in', 'Pick the offer you like.', c.info),
      _ => (1, 'Waiting for quotes', 'Mechanics near you can see it now.', c.warning),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: GlassPanel(
        radius: 20,
        onTap: widget.onTap,
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
              // A job booked on the device carries "problem: details".
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
  }
}
