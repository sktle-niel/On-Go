import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../data/app_session.dart';
import '../../../../data/chat_store.dart';
import '../../../../data/job_photo_store.dart';
import '../../../../data/mechanic_contact_store.dart';
import '../../../../data/motorcycle_problem.dart';
import '../../../../data/quote_store.dart';
import '../../../../theme/app_theme.dart';
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
class ClientJobsScreen extends StatefulWidget {
  /// Where "Book a mechanic" on an empty list goes: the home tab.
  final VoidCallback? onBook;

  const ClientJobsScreen({super.key, this.onBook});

  @override
  State<ClientJobsScreen> createState() => _ClientJobsScreenState();
}

class _ClientJobsScreenState extends State<ClientJobsScreen> {
  final _store = QuoteNotificationStore.instance;
  int _tabIndex = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChange);
    // Catches up on any job whose deadline passed while the client wasn't
    // looking, so this screen opens showing the truth.
    _store.expireOverdueJobs();
    // And raise the "running late" notice for any mechanic whose ETA ran out
    // while the client was elsewhere in the app.
    _store.notifyLateArrivals();
    // Keeps the "cancelling unlocks in …" countdown moving, and flips the
    // card to cancellable the moment the ETA runs out.
    _ticker = Timer.periodic(const Duration(seconds: 1), _onTick);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _store.removeListener(_onChange);
    super.dispose();
  }

  void _onTick(Timer _) {
    // Notifies on its own if an ETA just ran out; the setState is for the
    // ticking numbers on the cards.
    _store.notifyLateArrivals();
    if (!mounted) return;
    final counting = _store.myActiveJobs
        .any((r) => timeUntilArrival(r, _store.acceptedQuoteFor(r.id)) != null);
    if (counting) setState(() {});
  }

  void _onChange() => setState(() {});

  void _openJob(HelpRequest request) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ActiveRequestScreen(requestId: request.id)),
    );
  }

  void _openQuotes(HelpRequest request) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => QuotesScreen(requestId: request.id)),
    );
  }

  Future<void> _deleteUploaded(HelpRequest request) async {
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

    final ok = _store.clientDeleteRequest(request.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Booking cancelled.' : 'Could not cancel this booking.'), duration: AppDurations.snackBar),
    );
  }

  Future<void> _cancelMatched(HelpRequest request) async {
    final quote = _store.acceptedQuoteFor(request.id);
    final remaining = timeUntilArrival(request, quote);

    // The mechanic is still inside the ETA they committed to. Say so, with the
    // time left and when cancelling opens up, rather than offering options
    // that would be refused.
    if (clientCancelLockedByEta(request, quote)) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("You can't cancel yet"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${quote?.mechanicName ?? 'Your mechanic'} committed to arriving within '
                '${quote?.eta ?? 'their ETA'} and is still on the way.',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Text(
                'Cancelling is unavailable for another ${formatTimeRemaining(remaining!)}. '
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
      final ok = _store.clientRevertToPending(request.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Back in the queue: mechanics can quote on it again.' : 'Could not reopen this job.'),
          duration: AppDurations.snackBar,
        ),
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
      if (!mounted) return;
      if (confirmed == true) {
        final ok = _store.clientDeleteRequest(request.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'Job removed.' : 'Could not remove this job.'), duration: AppDurations.snackBar),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.layout;
    final uploaded = _store.myPendingRequests;
    final all = _store.myActiveJobs;
    final pending = all.where((r) => !r.isEmergency && !r.navigating).toList();
    final active = all.where((r) => r.isEmergency || r.navigating).toList()
      ..sort((a, b) {
        if (a.isEmergency != b.isEmergency) return a.isEmergency ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(layout.gutter, 8, layout.gutter, 4),
          child: GlassSegmented(
            index: _tabIndex,
            labels: const ['Quotes', 'Booked', 'Ongoing'],
            counts: [uploaded.length, pending.length, active.length],
            onChanged: (i) => setState(() => _tabIndex = i),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tabIndex,
            children: [
              _JobList(
                empty: _EmptyState(
                  title: 'Nothing booked yet',
                  text: 'Pick a service on Home. It shows here while quotes come in.',
                  actionLabel: 'Book a mechanic',
                  onAction: widget.onBook,
                ),
                cards: [
                  for (final r in uploaded)
                    _QuotesStageCard(
                      request: r,
                      store: _store,
                      onQuotes: () => _openQuotes(r),
                      onCancel: () => _deleteUploaded(r),
                    ),
                ],
              ),
              _JobList(
                empty: const _EmptyState(
                  title: 'No booked jobs',
                  text: 'Once you accept a quote, the job and your mechanic show here.',
                ),
                cards: [
                  for (final r in pending)
                    _BookedStageCard(
                      request: r,
                      store: _store,
                      onOpen: () => _openJob(r),
                      onCancel: () => _cancelMatched(r),
                    ),
                ],
              ),
              _JobList(
                empty: const _EmptyState(
                  title: 'Nothing under way',
                  text: 'A job moves here when your mechanic sets off.',
                ),
                cards: [
                  for (final r in active)
                    _OngoingStageCard(request: r, store: _store, onOpen: () => _openJob(r)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
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

/// What a list shows when there is nothing in it: a bike glowing on glass,
/// a line, and on the first tab the way to change that.
class _EmptyState extends StatelessWidget {
  final String title;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({required this.title, required this.text, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(32, 24, 32, MediaQuery.paddingOf(context).bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: c.primary.withValues(alpha: 0.35), blurRadius: 40)],
              ),
              child: const GlassPanel(
                radius: 52,
                padding: EdgeInsets.zero,
                child: Center(child: GlassGlyph(Icons.two_wheeler_rounded, size: 48)),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: c.textdark),
            ),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4, color: c.textmedium),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              GlassPillButton(label: actionLabel!, onPressed: onAction, style: GlassPillStyle.brand),
            ],
          ],
        ),
      ),
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

/// A request's line is "problem" or "problem: details".
_ProblemText _splitProblem(String problem) {
  final idx = problem.indexOf(':');
  if (idx == -1 || idx > 40) return _ProblemText(problem, '');
  return _ProblemText(problem.substring(0, idx).trim(), problem.substring(idx + 1).trim());
}

Color _urgencyColor(String urgency) {
  switch (urgency) {
    case 'Emergency':
      return AppColors.error;
    case 'Urgent':
      return AppColors.warning;
    default:
      return AppColors.success;
  }
}

/// "Booked 6:35 PM", or with the date once it is not today.
String _bookedLabel(DateTime at) {
  final now = DateTime.now();
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final minute = at.minute.toString().padLeft(2, '0');
  final time = '$hour:$minute ${at.hour < 12 ? 'AM' : 'PM'}';
  if (at.year == now.year && at.month == now.month && at.day == now.day) return 'Booked $time';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return 'Booked ${months[at.month - 1]} ${at.day}, $time';
}

String _paymentDisplay(HelpRequest request, MechanicQuote? quote) {
  // Once paid this is the recorded amount; before that it is the agreed
  // Emergency price or the accepted quote. Never a fixed fallback figure.
  final amount = settledPaymentAmount(request, quote);
  if (amount != null) return '₱${amount.toStringAsFixed(0)}';
  return request.isEmergency ? 'PRICE TO BE AGREED' : 'PRICE TO BE QUOTED';
}

/// The card every state shares: the words on the left, the problem's glyph
/// glowing in the state's colour on the right.
class _JobCard extends StatelessWidget {
  final HelpRequest request;
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
    final problem = _splitProblem(request.problem);
    final glyph = (MotorcycleProblem.forLabel(problem.issue) ?? MotorcycleProblem.somethingElse).icon;
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
            child: _CardArt(icon: glyph, color: accent, contact: contact),
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
                        text: request.urgency,
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

/// The right-hand panel of a card: the problem's glyph lit by a glow in the
/// state's colour, and the call and chat buttons at its foot.
class _CardArt extends StatelessWidget {
  final IconData icon;
  final Color color;
  final List<Widget> contact;

  const _CardArt({required this.icon, required this.color, required this.contact});

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
            GlassGlyph(icon, size: 46),
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
  final String name;
  final MechanicQuote? quote;

  const _MechanicLine({required this.name, this.quote});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final initials =
        name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    final detail = quote == null ? null : 'ETA ${quote!.eta}  ·  ${quote!.rating.toStringAsFixed(1)} ★';
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
List<Widget> _contactButtons(BuildContext context, HelpRequest request, String mechanicName) {
  void openChat() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => JobChatScreen(requestId: request.id, otherPartyName: mechanicName)),
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
        final unread = ChatStore.instance.unreadCountFor(request.id, AppSession.instance.currentRole);
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
  final HelpRequest request;
  final QuoteNotificationStore store;
  final VoidCallback onQuotes;
  final VoidCallback onCancel;

  const _QuotesStageCard({required this.request, required this.store, required this.onQuotes, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final quoteCount = store.quotesForRequest(request.id).length;
    final unseen = store.unseenQuoteCountForRequest(request.id);

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
  final HelpRequest request;
  final QuoteNotificationStore store;
  final VoidCallback onOpen;
  final VoidCallback onCancel;

  const _BookedStageCard({required this.request, required this.store, required this.onOpen, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final quote = store.acceptedQuoteFor(request.id);
    final name = quote?.mechanicName ?? 'Mechanic';
    final locked = clientCancelLockedByEta(request, quote);

    return _JobCard(
      request: request,
      status: 'Booked',
      accent: c.success,
      accentLine: _paymentDisplay(request, quote),
      onTap: onOpen,
      mechanic: _MechanicLine(name: name, quote: quote),
      contact: _contactButtons(context, request, name),
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
            text: 'Cancelling unlocks in ${formatTimeRemaining(timeUntilArrival(request, quote)!)}: '
                '$name is still within their ${quote?.eta ?? 'ETA'}.',
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
  final HelpRequest request;
  final QuoteNotificationStore store;
  final VoidCallback onOpen;

  const _OngoingStageCard({required this.request, required this.store, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final quote = store.acceptedQuoteFor(request.id);
    final name = quote?.mechanicName ?? 'Mechanic';

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
      accentLine: _paymentDisplay(request, quote),
      onTap: onOpen,
      mechanic: _MechanicLine(name: name, quote: quote),
      contact: _contactButtons(context, request, name),
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
