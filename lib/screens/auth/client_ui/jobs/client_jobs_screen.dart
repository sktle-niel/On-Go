import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../data/job_photo_store.dart';
import '../../../../data/mechanic_contact_store.dart';
import '../../../../data/motorcycle_problem.dart';
import '../../../../data/quote_store.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/auth_widgets.dart';
import '../../../../widgets/chat_icon_button.dart';
import '../../../../widgets/common_widgets.dart';
import '../../../../widgets/job_photo_preview.dart';
import '../../../shared/job_chat_screen.dart';
import '../active/active_request_screen.dart';
import '../home/quotes_screen.dart';

/// The client's bookings, in the three states one passes through: waiting
/// for quotes, booked with a mechanic, and under way.
///
/// Each is a card with the problem's picture, what was booked and when, a
/// status chip, the place, the mechanic once there is one, and the one or
/// two things the client can do about it — the shape of a ride-hailing
/// app's activity list rather than a form's summary.
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
          padding: EdgeInsets.fromLTRB(layout.gutter, 16, layout.gutter, 4),
          child: _SegmentBar(
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
                  text: 'Book a mechanic from Home. It shows here while quotes come in.',
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
//  The segment bar
// ═══════════════════════════════════════════════════════════════════════════

/// The three states as one rounded bar, the chosen one filled in the brand
/// colour, each with its count.
class _SegmentBar extends StatelessWidget {
  final int index;
  final List<String> labels;
  final List<int> counts;
  final ValueChanged<int> onChanged;

  const _SegmentBar({
    required this.index,
    required this.labels,
    required this.counts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppHairline.of(c.textmedium)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: _Segment(
                label: labels[i],
                count: counts[i],
                selected: i == index,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _Segment({required this.label, required this.count, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final ink = selected ? c.textlight : c.textmedium;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.enter,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? c.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ink),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected ? c.textlight.withValues(alpha: 0.22) : c.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selected ? c.textlight : c.primary),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
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
    return ListView.separated(
      padding: context.layout.listInsets(top: 12),
      itemCount: cards.length,
      separatorBuilder: (_, _) => const SizedBox(height: jobCardSpacing),
      itemBuilder: (context, index) => cards[index],
    );
  }
}

/// What a list shows when there is nothing in it: the bike, a line, and on
/// the first tab the way to change that.
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
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              MotorcycleProblem.motorcyclePicture,
              width: 96,
              height: 96,
              errorBuilder: (_, _, _) => const SizedBox(width: 96, height: 96),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textdark),
            ),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4, color: c.textmedium),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: 220,
                child: AuthPrimaryButton(label: actionLabel!, onPressed: onAction),
              ),
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
  return request.isEmergency ? 'To be agreed' : 'To be quoted';
}

/// The card every state shares: the problem's picture and name, when it was
/// booked, a status chip, the place, and whatever the state adds.
class _JobCard extends StatelessWidget {
  final HelpRequest request;
  final String status;
  final Color statusColor;
  final String? amount;

  /// The mechanic's row, once there is one.
  final Widget? mechanic;

  /// Notices between the place and the actions: a lock, a cancellation.
  final List<Widget> notes;
  final Widget actions;
  final VoidCallback? onTap;

  const _JobCard({
    required this.request,
    required this.status,
    required this.statusColor,
    required this.actions,
    this.amount,
    this.mechanic,
    this.notes = const [],
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final problem = _splitProblem(request.problem);
    final picture =
        (MotorcycleProblem.forLabel(problem.issue) ?? MotorcycleProblem.somethingElse).picture;
    final urgencyColor = _urgencyColor(request.urgency);
    final photos = JobPhotoStore.instance.pathsFor(request.id);

    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.borderLg,
        side: AppHairline.side(c.textmedium),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: jobCardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(
                    picture,
                    width: 44,
                    height: 44,
                    errorBuilder: (_, _, _) => const SizedBox(width: 44, height: 44),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                problem.issue,
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.textdark),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusChip(label: status, color: statusColor),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text.rich(
                          TextSpan(
                            text: _bookedLabel(request.createdAt),
                            children: [
                              const TextSpan(text: '  ·  '),
                              TextSpan(
                                text: request.urgency,
                                style: TextStyle(fontWeight: FontWeight.w600, color: urgencyColor),
                              ),
                            ],
                          ),
                          style: TextStyle(fontSize: 12, color: c.textmedium),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (problem.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  problem.description,
                  style: TextStyle(fontSize: 13, height: 1.35, color: c.textmedium),
                ),
              ],
              if (photos.isNotEmpty) ...[
                const SizedBox(height: 10),
                JobPhotoPreview(photoPaths: photos, maxHeight: 150),
              ],
              if (mechanic != null) ...[
                const SizedBox(height: 12),
                Divider(height: 1, color: AppHairline.of(c.textmedium)),
                const SizedBox(height: 12),
                mechanic!,
              ],
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(Icons.location_on_outlined, size: 16, color: c.textmedium),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(request.location, style: TextStyle(fontSize: 13, height: 1.3, color: c.textdark)),
                  ),
                  if (amount != null) ...[
                    const SizedBox(width: 12),
                    Text(amount!, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.textdark)),
                  ],
                ],
              ),
              for (final note in notes) ...[const SizedBox(height: 10), note],
              const SizedBox(height: 14),
              actions,
            ],
          ),
        ),
      ),
    );
  }
}

/// A small pill naming the state, with a dot in its colour.
class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

/// A notice on a card: a line of explanation in the state's colour.
class _CardNote extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _CardNote({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: AppRadii.borderMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, height: 1.35, fontWeight: FontWeight.w500, color: color)),
          ),
        ],
      ),
    );
  }
}

/// The mechanic on a booked or ongoing job: who, how far off, how rated,
/// and the call and chat buttons.
class _MechanicRow extends StatelessWidget {
  final String requestId;
  final String mechanicName;
  final MechanicQuote? quote;

  const _MechanicRow({required this.requestId, required this.mechanicName, this.quote});

  void _openChat(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => JobChatScreen(requestId: requestId, otherPartyName: mechanicName)),
      );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final initials = mechanicName.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    final detail = quote == null ? 'Your mechanic' : 'ETA ${quote!.eta}  ·  ${quote!.rating.toStringAsFixed(1)} ★';

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.primary.withValues(alpha: 0.10)),
          child: Text(
            initials.isEmpty ? 'M' : initials,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.primary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mechanicName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.textdark),
              ),
              const SizedBox(height: 2),
              Text(detail, style: TextStyle(fontSize: 12, color: c.textmedium)),
            ],
          ),
        ),
        CircleIconButton(
          icon: Icons.call,
          color: c.success,
          tooltip: 'Call $mechanicName',
          onTap: () => showContactSheet(
            context,
            name: mechanicName,
            phone: MechanicContactStore.instance.contactFor(mechanicName).phone,
            onMessage: () => _openChat(context),
          ),
        ),
        ChatIconButton(requestId: requestId, onTap: () => _openChat(context)),
      ],
    );
  }
}

/// A card's button: filled in the brand colour for the main thing to do,
/// an outline for the other. Both 44 tall, so a pair always lines up.
class _CardButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback? onTap;
  final int badge;

  const _CardButton({required this.label, required this.onTap, this.filled = true, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final shape = RoundedRectangleBorder(borderRadius: AppRadii.borderMd);
    final textStyle = TextStyle(fontFamily: AppTextStyles.fontFamily, fontSize: 14, fontWeight: FontWeight.w600);
    final Widget button = SizedBox(
      height: 44,
      width: double.infinity,
      child: filled
          ? ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(shape: shape, padding: EdgeInsets.zero, textStyle: textStyle),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                shape: shape,
                padding: EdgeInsets.zero,
                side: BorderSide(color: AppHairline.outline(c.textmedium)),
                foregroundColor: c.textdark,
                textStyle: textStyle,
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
    );
    if (badge <= 0) return button;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          right: -4,
          top: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            constraints: const BoxConstraints(minWidth: 20),
            decoration: BoxDecoration(
              color: c.textdark,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.surface, width: 2),
            ),
            child: Text(
              '$badge',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c.textlight),
            ),
          ),
        ),
      ],
    );
  }
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
    final Color statusColor;
    if (request.isEmergency) {
      status = 'Finding a mechanic';
      statusColor = c.error;
    } else if (quoteCount == 0) {
      status = 'Waiting for quotes';
      statusColor = c.warning;
    } else {
      status = '$quoteCount quote${quoteCount == 1 ? '' : 's'}';
      statusColor = c.info;
    }

    return _JobCard(
      request: request,
      status: status,
      statusColor: statusColor,
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
      actions: Row(
        children: [
          Expanded(child: _CardButton(label: 'Cancel', filled: false, onTap: onCancel)),
          const SizedBox(width: 10),
          Expanded(
            child: _CardButton(
              label: request.isEmergency ? 'Details' : 'View quotes',
              onTap: onQuotes,
              badge: unseen,
            ),
          ),
        ],
      ),
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
    final locked = clientCancelLockedByEta(request, quote);

    return _JobCard(
      request: request,
      status: 'Booked',
      statusColor: c.success,
      amount: _paymentDisplay(request, quote),
      onTap: onOpen,
      mechanic: _MechanicRow(requestId: request.id, mechanicName: quote?.mechanicName ?? 'Mechanic', quote: quote),
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
                '${quote?.mechanicName ?? 'your mechanic'} is still within their ${quote?.eta ?? 'ETA'}.',
          ),
      ],
      actions: Row(
        children: [
          Expanded(child: _CardButton(label: 'Cancel', filled: false, onTap: onCancel)),
          const SizedBox(width: 10),
          Expanded(child: _CardButton(label: 'Details', onTap: onOpen)),
        ],
      ),
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

    final String status;
    final Color statusColor;
    final String action;
    if (!request.arrived) {
      status = 'On the way';
      statusColor = c.info;
      action = 'Track mechanic';
    } else if (!request.workStarted) {
      status = 'Arrived';
      statusColor = c.success;
      action = 'Mechanic arrived';
    } else if (!request.serviceCompleted) {
      status = 'Working';
      statusColor = c.success;
      action = 'Work in progress';
    } else {
      status = 'Pay now';
      statusColor = c.primary;
      action = 'Pay now';
    }

    return _JobCard(
      request: request,
      status: status,
      statusColor: statusColor,
      amount: _paymentDisplay(request, quote),
      onTap: onOpen,
      mechanic: _MechanicRow(requestId: request.id, mechanicName: quote?.mechanicName ?? 'Mechanic', quote: quote),
      actions: _CardButton(label: action, onTap: onOpen),
    );
  }
}
