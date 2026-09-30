import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../data/app_session.dart';
import '../../../../data/chat_store.dart';
import '../../../../data/job_photo_store.dart';
import '../../../../data/mechanic_contact_store.dart';
import '../../../../data/motorcycle_problem.dart';
import '../../../../data/quote_store.dart'
    show
        QuoteNotificationStore,
        acceptedQuoteOf,
        clientCancelLockedOf,
        formatEtaDuration,
        formatTimeRemaining,
        settledPaymentAmountOf,
        timeUntilArrivalOf;
import '../../../../services/backend/mobile_backend.dart';
import '../../../../theme/app_theme.dart';
import '../../../../utils/coalesced_load.dart';
import '../../../../widgets/common_widgets.dart';
import '../../../../widgets/glass.dart';
import '../../../shared/job_chat_screen.dart';
import '../active/active_request_screen.dart';
import '../home/quotes_screen.dart';

/// The client's bookings, drawn in glass, in the three states one passes
/// through: waiting for quotes, booked with a mechanic, and under way.
///
/// A glass segmented control picks the state; each booking is a glass card
/// with its words on the left — the state in its colour, the problem, when,
/// the mechanic, the amount, the one or two things to do — and the problem's
/// glyph glowing on the right.
///
/// Every job here is read through [MobileBackend.serviceRequests], so the list
/// is the server's in an API build and the device's in a local one. The
/// backend owns every rule behind the buttons: the ETA lock, the cancel and
/// reopen refusals, the expiry sweep. This screen only mirrors the lock so it
/// can explain it before the client taps into a refusal.
class ClientJobsScreen extends StatefulWidget {
  /// Where "Book a mechanic" on an empty list goes: the home tab.
  final VoidCallback? onBook;

  /// Whether this is the tab on screen. The shell keeps every tab alive, and
  /// the event socket does not replay what it missed while it was down, so
  /// turning to this tab is when the jobs are read afresh.
  final bool visible;

  const ClientJobsScreen({super.key, this.onBook, this.visible = true});

  @override
  State<ClientJobsScreen> createState() => _ClientJobsScreenState();
}

class _ClientJobsScreenState extends State<ClientJobsScreen> with CoalescedLoad<ClientJobsScreen> {
  ServiceRequestApi get _api => MobileBackend.instance.serviceRequests;

  List<_Job> _jobs = const [];
  bool _loading = true;
  String? _error;

  int _tabIndex = 0;
  Timer? _ticker;
  final _watches = <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    reload();
    // A quote arriving, a job matched, cancelled, expired or back in the
    // pool: read the list again rather than patch it, so the cards always
    // show what the backend holds.
    _watches
      ..add(_api.watchRequests().listen((_) => reload()))
      ..add(_api.watchQuotes().listen((_) => reload()));
    // Keeps the "cancelling unlocks in …" countdown moving, and flips the
    // card to cancellable the moment the ETA runs out.
    _ticker = Timer.periodic(const Duration(seconds: 1), _onTick);
  }

  @override
  void didUpdateWidget(ClientJobsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) reload();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final watch in _watches) {
      watch.cancel();
    }
    super.dispose();
  }

  void _onTick(Timer _) {
    // The "running late" notice is the phone's own; the server sends none. It
    // reads the device's jobs, so only a local build has anything to raise.
    QuoteNotificationStore.instance.notifyLateArrivals();
    if (!mounted) return;
    final now = DateTime.now();
    if (_jobs.any((job) => job.arrivalCountdown(now) != null)) setState(() {});
  }

  /// Reads the client's open jobs and their quotes.
  @override
  Future<void> read() async {
    try {
      final open = (await _api.listMyRequests()).where(
        (request) => request.status == ServiceRequestStatus.pending || request.status == ServiceRequestStatus.matched,
      );
      // A client holds one active request at a time, so this is one or two
      // reads, not one per job in their history.
      final jobs = <_Job>[
        for (final request in open) _Job(request, await _api.listQuotes(request.id)),
      ];
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _openJob(_Job job) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ActiveRequestScreen(requestId: job.request.id)),
    );
    reload();
  }

  Future<void> _openQuotes(_Job job) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => QuotesScreen(requestId: job.request.id)),
    );
    // Accepting there matches the job; read it back rather than wait for the
    // event.
    reload();
  }

  /// Sends one change to the backend and says how it went: [done] when it
  /// went through, the backend's own words when it was refused. Reads the list
  /// again either way.
  Future<void> _change(Future<Object?> Function() call, {required String done}) async {
    var message = done;
    try {
      await call();
    } on ApiException catch (error) {
      message = error.message;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: AppDurations.snackBar),
      );
    }
    await reload();
  }

  Future<void> _deleteUploaded(_Job job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: const Text('It will be removed and mechanics will no longer see it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _change(() => _api.cancelRequest(job.request.id), done: 'Booking cancelled.');
  }

  Future<void> _cancelMatched(_Job job) async {
    final now = DateTime.now();

    // The mechanic is still inside the ETA they committed to. Say so, with the
    // time left and when cancelling opens up, rather than offering options
    // the backend would refuse.
    if (job.cancelLocked(now)) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("You can't cancel yet"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${job.request.mechanicName ?? 'Your mechanic'} committed to arriving within '
                '${job.eta ?? 'their ETA'} and is still on the way.',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Text(
                'Cancelling is unavailable for another ${formatTimeRemaining(job.arrivalCountdown(now)!)}. '
                "If they haven't arrived by then, you can cancel this job at any time.",
                style: TextStyle(fontSize: 13, color: AppColors.textmedium),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
          ],
        ),
      );
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this job?'),
        content: const Text('You can put it back in the queue for another mechanic, or remove it completely.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Keep job')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'revert'),
            child: const Text('Find another mechanic'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (choice == 'revert') {
      await _change(
        () => _api.reopenRequest(job.request.id),
        done: 'Back in the queue: mechanics can quote on it again.',
      );
    } else if (choice == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remove this job?'),
          content: const Text('This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      await _change(() => _api.cancelRequest(job.request.id), done: 'Job removed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.layout;
    final now = DateTime.now();
    final uploaded = _jobs.where((j) => j.request.status == ServiceRequestStatus.pending).toList()
      ..sort((a, b) => b.request.createdAt.compareTo(a.request.createdAt));
    final matched = _jobs.where((j) => j.request.status == ServiceRequestStatus.matched);
    final booked = matched.where((j) => !j.request.isEmergency && !j.request.navigating).toList();
    final ongoing = matched.where((j) => j.request.isEmergency || j.request.navigating).toList()
      ..sort((a, b) {
        if (a.request.isEmergency != b.request.isEmergency) return a.request.isEmergency ? -1 : 1;
        return b.request.createdAt.compareTo(a.request.createdAt);
      });

    final Widget body;
    final error = _error;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (error != null) {
      body = GlassEmptyState(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load your jobs",
        text: error,
        actionLabel: 'Try again',
        onAction: reload,
      );
    } else {
      body = IndexedStack(
        index: _tabIndex,
        children: [
          _JobList(
            empty: GlassEmptyState(
              icon: Icons.two_wheeler_rounded,
              title: 'Nothing booked yet',
              text: 'Pick a service on Home. It shows here while quotes come in.',
              actionLabel: 'Book a mechanic',
              onAction: widget.onBook,
            ),
            cards: [
              for (final job in uploaded)
                _QuotesStageCard(
                  job: job,
                  // Which quotes this phone has already shown the client is
                  // this phone's business, not the server's; the quotes
                  // screen marks them on the local store by their ids.
                  unseen: QuoteNotificationStore.instance.unseenQuoteCount(job.liveQuoteIds),
                  onQuotes: () => _openQuotes(job),
                  onCancel: () => _deleteUploaded(job),
                ),
            ],
          ),
          _JobList(
            empty: const GlassEmptyState(
              icon: Icons.two_wheeler_rounded,
              title: 'No booked jobs',
              text: 'Once you accept a quote, the job and your mechanic show here.',
            ),
            cards: [
              for (final job in booked)
                _BookedStageCard(
                  job: job,
                  now: now,
                  onOpen: () => _openJob(job),
                  onCancel: () => _cancelMatched(job),
                ),
            ],
          ),
          _JobList(
            empty: const GlassEmptyState(
              icon: Icons.two_wheeler_rounded,
              title: 'Nothing under way',
              text: 'A job moves here when your mechanic sets off.',
            ),
            cards: [
              for (final job in ongoing) _OngoingStageCard(job: job, onOpen: () => _openJob(job)),
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(layout.gutter, 8, layout.gutter, 4),
          child: GlassSegmented(
            index: _tabIndex,
            labels: const ['Quotes', 'Booked', 'Ongoing'],
            counts: [uploaded.length, booked.length, ongoing.length],
            onChanged: (i) => setState(() => _tabIndex = i),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  A job and what its card reads off it
// ═══════════════════════════════════════════════════════════════════════════

/// One of the client's open jobs, with the quotes its card needs: how many are
/// still on the table and which one the job was matched on.
class _Job {
  final ServiceRequest request;
  final List<JobQuote> quotes;

  const _Job(this.request, this.quotes);

  JobQuote? get accepted => acceptedQuoteOf(quotes);

  /// Offers still on the table: the ones the client can act on.
  Iterable<String> get liveQuoteIds => [
        for (final quote in quotes)
          if (quote.isLive) quote.id,
      ];

  int get liveQuotes => liveQuoteIds.length;

  String get mechanicName => request.mechanicName ?? accepted?.mechanicName ?? 'Mechanic';

  /// The arrival time the mechanic promised, as it reads on screen.
  String? get eta {
    final quote = accepted;
    return quote == null ? null : formatEtaDuration(Duration(minutes: quote.etaMinutes));
  }

  Duration? arrivalCountdown(DateTime now) => timeUntilArrivalOf(request, now);

  bool cancelLocked(DateTime now) => clientCancelLockedOf(request, now);

  double? get amount => settledPaymentAmountOf(request, accepted);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Lists and the empty state
// ═══════════════════════════════════════════════════════════════════════════

class _JobList extends StatelessWidget {
  final List<Widget> cards;
  final Widget empty;

  const _JobList({required this.cards, required this.empty});

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return empty;
    final layout = context.layout;
    return ListView.separated(
      // The last card stays clear of the floating tab bar.
      padding: EdgeInsets.fromLTRB(layout.gutter, 12, layout.gutter, MediaQuery.paddingOf(context).bottom + 16),
      itemCount: cards.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, index) => cards[index],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Shared pieces of a card
// ═══════════════════════════════════════════════════════════════════════════

class _ProblemText {
  final String issue;
  final String description;
  const _ProblemText(this.issue, this.description);
}

/// A job's headline and its details. The server keeps the two apart; a job
/// booked on this device carries them as one "problem: details" line.
_ProblemText _problemOf(ServiceRequest request) {
  final description = request.description.trim();
  if (description.isNotEmpty) return _ProblemText(request.problem, description);
  final problem = request.problem;
  final idx = problem.indexOf(':');
  if (idx == -1 || idx > 40) return _ProblemText(problem, '');
  return _ProblemText(problem.substring(0, idx).trim(), problem.substring(idx + 1).trim());
}

Color _urgencyColor(JobUrgency urgency) => switch (urgency) {
      JobUrgency.emergency => AppColors.error,
      JobUrgency.urgent => AppColors.warning,
      JobUrgency.normal => AppColors.success,
    };

/// "Booked 6:35 PM", or with the date once it is not today.
String _bookedLabel(DateTime at) {
  final local = at.toLocal();
  final now = DateTime.now();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final time = '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
  if (local.year == now.year && local.month == now.month && local.day == now.day) return 'Booked $time';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return 'Booked ${months[local.month - 1]} ${local.day}, $time';
}

/// The job's price as the card shows it: a real figure, or what it is still
/// waiting on. Never a fixed fallback figure.
String _paymentDisplay(_Job job) {
  final amount = job.amount;
  if (amount != null) return '₱${amount.toStringAsFixed(0)}';
  return job.request.isEmergency ? 'PRICE TO BE AGREED' : 'PRICE TO BE QUOTED';
}

/// The card every state shares: the words on the left, the problem's glyph
/// glowing in the state's colour on the right.
class _JobCard extends StatelessWidget {
  final ServiceRequest request;
  final String status;
  final Color accent;

  /// A line in the state's colour under the details: the amount, a fee.
  final String? accentLine;

  /// Who is doing the job, once someone is.
  final Widget? mechanic;

  /// Notices under the buttons: a lock, a cancellation, a missed deadline.
  final List<Widget> notes;
  final List<Widget> actions;

  /// Round buttons at the foot of the glowing panel: call and chat.
  final List<Widget> contact;
  final VoidCallback? onTap;

  const _JobCard({
    required this.request,
    required this.status,
    required this.accent,
    required this.actions,
    this.accentLine,
    this.mechanic,
    this.notes = const [],
    this.contact = const [],
    this.onTap,
  });

  static const double _artWidth = 100;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final problem = _problemOf(request);
    final picture = (MotorcycleProblem.forLabel(problem.issue) ?? MotorcycleProblem.somethingElse).picture;
    // The photos stay on this device, filed against the id the backend gave
    // the job; the server has nowhere to put them yet. See JobPhotoStore.
    final photos = JobPhotoStore.instance.pathsFor(request.id).length;

    return GlassPanel(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          // The glowing panel on the right runs the card's full height.
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: _artWidth,
            child: _CardArt(picture: picture, color: accent, contact: contact),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, _artWidth + 8, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.toUpperCase(),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: accent),
                ),
                const SizedBox(height: 4),
                Text(
                  problem.issue,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: c.textdark),
                ),
                const SizedBox(height: 3),
                Text.rich(
                  TextSpan(
                    text: _bookedLabel(request.createdAt),
                    children: [
                      const TextSpan(text: '  ·  '),
                      TextSpan(
                        text: request.urgency.label,
                        style: TextStyle(fontWeight: FontWeight.w700, color: _urgencyColor(request.urgency)),
                      ),
                    ],
                  ),
                  style: TextStyle(fontSize: 12, color: c.textmedium),
                ),
                if (problem.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    problem.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, height: 1.35, color: c.textmedium),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 14, color: c.textmedium),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        request.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textmedium),
                      ),
                    ),
                  ],
                ),
                if (photos > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.photo_camera_outlined, size: 14, color: c.textmedium),
                      const SizedBox(width: 4),
                      Text(
                        '$photos photo${photos == 1 ? '' : 's'}',
                        style: TextStyle(fontSize: 12, color: c.textmedium),
                      ),
                    ],
                  ),
                ],
                if (mechanic != null) ...[const SizedBox(height: 10), mechanic!],
                if (accentLine != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    accentLine!,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: accent),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
                for (final note in notes) ...[const SizedBox(height: 10), note],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The right-hand panel of a card: the problem's icon lit by a glow in the
/// state's colour, and the call and chat buttons at its foot.
class _CardArt extends StatelessWidget {
  final String picture;
  final Color color;
  final List<Widget> contact;

  const _CardArt({required this.picture, required this.color, required this.contact});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(21)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.1, -0.35),
            radius: 0.95,
            colors: [color.withValues(alpha: 0.42), color.withValues(alpha: 0)],
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 18),
            Image.asset(picture, width: 52, height: 52, excludeFromSemantics: true),
            const Spacer(),
            if (contact.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: contact),
              ),
          ],
        ),
      ),
    );
  }
}

/// A notice on a card: a line of explanation with its glyph.
class _CardNote extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _CardNote({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12, height: 1.35, fontWeight: FontWeight.w500, color: color)),
        ),
      ],
    );
  }
}

/// Who is doing the job: initials, the name, how soon and how rated.
class _MechanicLine extends StatelessWidget {
  final _Job job;

  const _MechanicLine({required this.job});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final name = job.mechanicName;
    final initials =
        name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    final quote = job.accepted;
    final detail = quote == null ? null : 'ETA ${job.eta}  ·  ${quote.rating.toStringAsFixed(1)} ★';
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color.lerp(c.primary, Colors.white, 0.2)!, c.primarydark],
            ),
          ),
          child: Text(
            initials.isEmpty ? 'M' : initials,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c.textlight),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.textdark),
              ),
              if (detail != null) Text(detail, style: TextStyle(fontSize: 11.5, color: c.textmedium)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Call and chat for a job with a mechanic, as round glass buttons; chat
/// carries the unread count.
List<Widget> _contactButtons(BuildContext context, _Job job) {
  final requestId = job.request.id;
  final mechanicName = job.mechanicName;
  void openChat() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => JobChatScreen(requestId: requestId, otherPartyName: mechanicName)),
      );
  return [
    GlassIconButton(
      icon: Icons.call_rounded,
      tooltip: 'Call $mechanicName',
      size: 36,
      onPressed: () => showContactSheet(
        context,
        name: mechanicName,
        phone: MechanicContactStore.instance.contactFor(mechanicName).phone,
        onMessage: openChat,
      ),
    ),
    AnimatedBuilder(
      animation: ChatStore.instance,
      builder: (context, _) {
        final unread = ChatStore.instance.unreadCountFor(requestId, AppSession.instance.currentRole);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            GlassIconButton(
              icon: Icons.chat_bubble_outline_rounded,
              tooltip: unread > 0 ? 'Messages, $unread unread' : 'Messages',
              size: 36,
              onPressed: openChat,
            ),
            if (unread > 0)
              Positioned(
                right: 2,
                top: 2,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 16),
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.textlight),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  ];
}

// ═══════════════════════════════════════════════════════════════════════════
//  The three states
// ═══════════════════════════════════════════════════════════════════════════

/// Booked, and waiting for mechanics to quote.
class _QuotesStageCard extends StatelessWidget {
  final _Job job;

  /// Quotes this phone has not shown the client yet.
  final int unseen;
  final VoidCallback onQuotes;
  final VoidCallback onCancel;

  const _QuotesStageCard({required this.job, required this.unseen, required this.onQuotes, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final request = job.request;
    final quoteCount = job.liveQuotes;

    // Emergencies skip quoting: a mechanic claims them directly.
    final String status;
    final Color accent;
    if (request.isEmergency) {
      status = 'Finding a mechanic';
      accent = c.error;
    } else if (quoteCount == 0) {
      status = 'Waiting for quotes';
      accent = c.warning;
    } else {
      status = '$quoteCount quote${quoteCount == 1 ? '' : 's'} in';
      accent = c.info;
    }

    return _JobCard(
      request: request,
      status: status,
      accent: accent,
      accentLine: request.surcharge > 0 ? 'PRIORITY FEE ₱${request.surcharge.toStringAsFixed(0)}' : null,
      onTap: onQuotes,
      notes: [
        if (request.expiredAt != null)
          _CardNote(
            icon: Icons.timer_off_outlined,
            color: c.error,
            text: "${request.expiredByMechanic ?? 'The mechanic'} didn't finish this job in the allowed time. "
                'It is open to mechanics again.',
          ),
      ],
      actions: [
        GlassPillButton(
          label: request.isEmergency ? 'Details' : (unseen > 0 ? 'View quotes ($unseen new)' : 'View quotes'),
          onPressed: onQuotes,
        ),
        GlassPillButton(label: 'Cancel', onPressed: onCancel, style: GlassPillStyle.ghost),
      ],
    );
  }
}

/// A quote accepted; the mechanic has not set off yet.
class _BookedStageCard extends StatelessWidget {
  final _Job job;
  final DateTime now;
  final VoidCallback onOpen;
  final VoidCallback onCancel;

  const _BookedStageCard({required this.job, required this.now, required this.onOpen, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final request = job.request;
    final locked = job.cancelLocked(now);

    return _JobCard(
      request: request,
      status: 'Booked',
      accent: c.success,
      accentLine: _paymentDisplay(job),
      onTap: onOpen,
      mechanic: _MechanicLine(job: job),
      contact: _contactButtons(context, job),
      notes: [
        if (request.lastCancelReason != null)
          _CardNote(
            icon: Icons.info_outline,
            color: c.error,
            text: '${request.lastCancelledBy ?? 'Mechanic'} cancelled: ${request.lastCancelReason}',
          ),
        // While the mechanic is inside their ETA the client can't cancel, so
        // say so on the card rather than only when Cancel is tapped.
        if (locked)
          _CardNote(
            icon: Icons.lock_clock,
            color: c.textmedium,
            text: 'Cancelling unlocks in ${formatTimeRemaining(job.arrivalCountdown(now)!)}: '
                '${job.mechanicName} is still within their ${job.eta ?? 'ETA'}.',
          ),
      ],
      actions: [
        GlassPillButton(label: 'Details', onPressed: onOpen),
        GlassPillButton(label: 'Cancel', onPressed: onCancel, style: GlassPillStyle.ghost),
      ],
    );
  }
}

/// The mechanic is on the way, there, working, or waiting to be paid.
class _OngoingStageCard extends StatelessWidget {
  final _Job job;
  final VoidCallback onOpen;

  const _OngoingStageCard({required this.job, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final request = job.request;

    final (String status, Color accent, String action) = switch (request) {
      _ when !request.arrived => ('On the way', c.info, 'Track mechanic'),
      _ when !request.workStarted => ('Arrived', c.success, 'See job'),
      _ when !request.serviceCompleted => ('Working', c.success, 'See job'),
      _ => ('Pay now', c.primary, 'Pay now'),
    };

    return _JobCard(
      request: request,
      status: status,
      accent: accent,
      accentLine: _paymentDisplay(job),
      onTap: onOpen,
      mechanic: _MechanicLine(job: job),
      contact: _contactButtons(context, job),
      actions: [
        GlassPillButton(
          label: action,
          onPressed: onOpen,
          style: action == 'Pay now' ? GlassPillStyle.brand : GlassPillStyle.contrast,
        ),
      ],
    );
  }
}
