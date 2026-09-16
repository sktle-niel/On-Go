import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/common_widgets.dart';
import '../../../../widgets/job_photo_preview.dart';
import '../../../../data/mechanic_contact_store.dart';
import '../../../../data/quote_store.dart';
import '../home/quotes_screen.dart';
import '../active/active_request_screen.dart';
import '../../../../widgets/chat_icon_button.dart';
import '../../../shared/job_chat_screen.dart';

class ClientJobsScreen extends StatefulWidget {
  const ClientJobsScreen({super.key});

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
        title: const Text('Delete this request?'),
        content: const Text('This removes it permanently and can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    final ok = _store.clientDeleteRequest(request.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Request deleted.' : 'Could not delete this request.'), duration: AppDurations.snackBar),
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
          title: const Text('You can\'t cancel yet'),
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
                'If they haven\'t arrived by then, you can cancel this job at any time.',
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
        title: const Text('Cancel this request?'),
        content: const Text('You can put this back in the queue for another mechanic, or remove it completely.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Keep Job')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'revert'),
            child: const Text('Revert to Pending'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (choice == 'revert') {
      final ok = _store.clientRevertToPending(request.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Request reverted to Pending — open to mechanics again.' : 'Could not revert this request.'), duration: AppDurations.snackBar),
      );
    } else if (choice == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete permanently?'),
          content: const Text('This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (confirmed == true) {
        final ok = _store.clientDeleteRequest(request.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'Request deleted.' : 'Could not delete this request.'), duration: AppDurations.snackBar),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
        _JobTabBar(
          currentIndex: _tabIndex,
          onChanged: (i) => setState(() => _tabIndex = i),
          counts: [uploaded.length, pending.length, active.length],
        ),
        Expanded(
          child: IndexedStack(
            index: _tabIndex,
            children: [
              _UploadedJobList(
                requests: uploaded,
                store: _store,
                onQuotes: _openQuotes,
                onCancel: _deleteUploaded,
              ),
              _PendingJobList(
                requests: pending,
                store: _store,
                onOpen: _openJob,
                onCancel: _cancelMatched,
              ),
              _ActiveJobList(
                requests: active,
                store: _store,
                onOpen: _openJob,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Tab bar
// ---------------------------------------------------------------------

class _JobTabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onChanged;
  final List<int> counts;

  const _JobTabBar({required this.currentIndex, required this.onChanged, required this.counts});

  static const _labels = ['Uploaded', 'Pending', 'Active'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: List.generate(3, (i) {
          final selected = i == currentIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: selected ? AppColors.primary : AppColors.textdark.withValues(alpha: 0.2)),
                ),
                child: Text('${_labels[i]} ${counts[i]}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? AppColors.textlight : AppColors.textmedium)),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------

class _ProblemText {
  final String issue;
  final String description;
  const _ProblemText(this.issue, this.description);
}

_ProblemText _splitProblem(String problem) {
  final idx = problem.indexOf(':');
  if (idx == -1 || idx > 40) return _ProblemText('Reported Issue', problem);
  final rest = problem.substring(idx + 1).trim();
  return _ProblemText(problem.substring(0, idx).trim(), rest.isEmpty ? problem : rest);
}

Color _urgencyColor(String urgency) {
  switch (urgency) {
    case 'Emergency':
      return AppColors.primary;
    case 'Urgent':
      return AppColors.warning;
    default:
      return AppColors.success;
  }
}

String _paymentDisplay(HelpRequest request, MechanicQuote? quote) {
  // Once paid this is the recorded amount; before that it is the agreed
  // Emergency price or the accepted quote. Never a fixed fallback figure.
  final amount = settledPaymentAmount(request, quote);
  if (amount != null) return '₱${amount.toStringAsFixed(0)}';
  return request.isEmergency ? 'To be agreed' : 'To be quoted';
}

Widget _locationBlock(String location) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(Icons.location_on_outlined, size: 14, color: AppColors.textdark.withValues(alpha: 0.55)),
          const SizedBox(width: 4),
          Text('Location', style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55))),
        ],
      ),
      const SizedBox(height: 2),
      Text(location, style: TextStyle(fontSize: 13, color: AppColors.textdark)),
    ],
  );
}

/// The mechanic's name with the call and chat buttons beside it, as both the
/// Pending and the Active card show it.
class _MechanicContactRow extends StatelessWidget {
  final String requestId;
  final String mechanicName;

  const _MechanicContactRow({required this.requestId, required this.mechanicName});

  void _openChat(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => JobChatScreen(requestId: requestId, otherPartyName: mechanicName)),
      );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            mechanicName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.2),
          ),
        ),
        CircleIconButton(
          icon: Icons.call,
          color: AppColors.success,
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

/// Every action button on every job card (Quotes, Pending pill, Cancel,
/// Navigate, Send Payment, etc.) renders through this ONE widget with a
/// hard-fixed height and identical padding/text style — so two buttons
/// sitting side-by-side in a Row can never end up different sizes again,
/// regardless of whether one of them happens to carry a badge overlay.
class _JobActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final Widget? badge;

  const _JobActionButton({required this.label, required this.color, required this.onTap, this.badge});

  static const double _height = 44;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      height: _height,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color,
          foregroundColor: AppColors.textlight,
          disabledForegroundColor: AppColors.textlight,
          shape: const StadiumBorder(),
          padding: EdgeInsets.zero,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );

    if (badge == null) return button;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(right: -4, top: -4, child: badge!),
      ],
    );
  }
}

Widget _countBadge(int count) {
  return Container(
    padding: const EdgeInsets.all(4),
    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
    decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
    child: Text(
      '$count',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 10, color: AppColors.textlight, fontWeight: FontWeight.w700),
    ),
  );
}

// ---------------------------------------------------------------------
// Uploaded tab — still awaiting a decision (no mechanic accepted yet)
// ---------------------------------------------------------------------

class _UploadedJobList extends StatelessWidget {
  final List<HelpRequest> requests;
  final QuoteNotificationStore store;
  final void Function(HelpRequest) onQuotes;
  final void Function(HelpRequest) onCancel;

  const _UploadedJobList({required this.requests, required this.store, required this.onQuotes, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nothing uploaded yet — problems you submit from Need Help will show up here while they\'re awaiting quotes.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textdark.withValues(alpha: 0.55)),
          ),
        ),
      );
    }
    return ListView(
      padding: context.layout.listInsets(),
      children: requests
          .map((r) => Padding(
                padding: const EdgeInsets.only(bottom: jobCardSpacing),
                child: _UploadedJobCard(request: r, store: store, onQuotes: () => onQuotes(r), onCancel: () => onCancel(r)),
              ))
          .toList(),
    );
  }
}

class _UploadedJobCard extends StatelessWidget {
  final HelpRequest request;
  final QuoteNotificationStore store;
  final VoidCallback onQuotes;
  final VoidCallback onCancel;

  const _UploadedJobCard({required this.request, required this.store, required this.onQuotes, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final problem = _splitProblem(request.problem);
    final urgencyColor = _urgencyColor(request.urgency);
    final quoteCount = store.quotesForRequest(request.id).length;
    final unseen = store.unseenQuoteCountForRequest(request.id);

    return AppCard(
      padding: jobCardPadding,
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('UPLOADED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.success, letterSpacing: 0.5)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: urgencyColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                child: Text(request.urgency, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: urgencyColor)),
              ),
            ],
          ),
          if (request.expiredAt != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.timer_off_outlined, size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${request.expiredByMechanic ?? 'The mechanic'} didn\'t complete this job within the allowed time. '
                      'Your request is open to mechanics again.',
                      style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(problem.issue, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 2),
          Text(problem.description, style: TextStyle(fontSize: 13, color: AppColors.textdark.withValues(alpha: 0.55))),
          if (request.photoPaths.isNotEmpty) ...[
            const SizedBox(height: 10),
            JobPhotoPreview(photoPaths: request.photoPaths),
          ],
          const SizedBox(height: 10),
          _locationBlock(request.location),
          const SizedBox(height: 4),
          Text(
            // Emergencies skip quoting entirely — a mechanic claims them
            // directly — so they never sit "waiting for quotes".
            request.isEmergency
                ? 'Waiting for a mechanic to accept this emergency.'
                : (quoteCount == 0 ? 'Waiting for quotes...' : '$quoteCount quote${quoteCount == 1 ? '' : 's'} received'),
            style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _JobActionButton(
                  label: 'Quotes',
                  color: AppColors.success,
                  onTap: onQuotes,
                  badge: unseen > 0 ? _countBadge(unseen) : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _JobActionButton(label: 'Cancel', color: AppColors.primary, onTap: onCancel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Pending tab — matched, mechanic hasn't started navigating yet
// ---------------------------------------------------------------------

class _PendingJobList extends StatelessWidget {
  final List<HelpRequest> requests;
  final QuoteNotificationStore store;
  final void Function(HelpRequest) onOpen;
  final void Function(HelpRequest) onCancel;

  const _PendingJobList({required this.requests, required this.store, required this.onOpen, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No pending jobs — accepted Normal or Urgent requests will show up here before your mechanic starts heading over.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textdark.withValues(alpha: 0.55)),
          ),
        ),
      );
    }
    return ListView(
      padding: context.layout.listInsets(),
      children: requests
          .map((r) => Padding(
                padding: const EdgeInsets.only(bottom: jobCardSpacing),
                child: _PendingJobCard(request: r, store: store, onOpen: () => onOpen(r), onCancel: () => onCancel(r)),
              ))
          .toList(),
    );
  }
}

class _PendingJobCard extends StatelessWidget {
  final HelpRequest request;
  final QuoteNotificationStore store;
  final VoidCallback onOpen;
  final VoidCallback onCancel;

  const _PendingJobCard({required this.request, required this.store, required this.onOpen, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final quote = store.acceptedQuoteFor(request.id);
    final problem = _splitProblem(request.problem);

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(16),
      child: AppCard(
        padding: jobCardPadding,
        color: AppColors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('PENDING', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.success, letterSpacing: 0.5)),
              ],
            ),
            if (request.lastCancelReason != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                child: Text(
                  '${request.lastCancelledBy ?? 'Mechanic'} cancelled: ${request.lastCancelReason}',
                  style: TextStyle(fontSize: 11, color: AppColors.primary),
                ),
              ),
            ],
            const SizedBox(height: 8),
            _MechanicContactRow(requestId: request.id, mechanicName: quote?.mechanicName ?? 'Mechanic'),
            const SizedBox(height: 8),
            Text(problem.issue, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Text(problem.description, style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55))),
            if (request.photoPaths.isNotEmpty) ...[
              const SizedBox(height: 10),
              JobPhotoPreview(photoPaths: request.photoPaths),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _locationBlock(request.location)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Payment', style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55))),
                    const SizedBox(height: 2),
                    Text(_paymentDisplay(request, quote), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.success)),
                  ],
                ),
              ],
            ),
            // While the mechanic is inside their ETA the client can't cancel,
            // so say so on the card rather than only when Cancel is tapped.
            if (clientCancelLockedByEta(request, quote)) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.lock_clock, size: 14, color: AppColors.textdark.withValues(alpha: 0.55)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Cancelling unlocks in '
                      '${formatTimeRemaining(timeUntilArrival(request, quote)!)} — '
                      '${quote?.mechanicName ?? 'your mechanic'} is still within their '
                      '${quote?.eta ?? 'ETA'}.',
                      style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55)),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _JobActionButton(label: 'Pending', color: AppColors.success, onTap: null)),
                const SizedBox(width: 10),
                Expanded(child: _JobActionButton(label: 'Cancel', color: AppColors.primary, onTap: onCancel)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Active tab — no Cancel, single button whose label tracks phase
// ---------------------------------------------------------------------

class _ActiveJobList extends StatelessWidget {
  final List<HelpRequest> requests;
  final QuoteNotificationStore store;
  final void Function(HelpRequest) onOpen;

  const _ActiveJobList({required this.requests, required this.store, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return Center(child: Text('No active jobs right now.', style: TextStyle(color: AppColors.textdark.withValues(alpha: 0.55))));
    }
    return ListView(
      padding: context.layout.listInsets(),
      children: requests
          .map((r) => Padding(
                padding: const EdgeInsets.only(bottom: jobCardSpacing),
                child: _ActiveJobCard(request: r, store: store, onOpen: () => onOpen(r)),
              ))
          .toList(),
    );
  }
}

class _ActiveJobCard extends StatelessWidget {
  final HelpRequest request;
  final QuoteNotificationStore store;
  final VoidCallback onOpen;

  const _ActiveJobCard({required this.request, required this.store, required this.onOpen});

  String get _statusLabel {
    if (!request.arrived) return 'Navigate';
    if (!request.workStarted) return 'Mechanic Arrived';
    if (!request.serviceCompleted) return 'Work in Progress';
    return 'Send Payment';
  }

  Color get _statusColor => _statusLabel == 'Send Payment' ? AppColors.primary : AppColors.success;

  @override
  Widget build(BuildContext context) {
    final quote = store.acceptedQuoteFor(request.id);
    final problem = _splitProblem(request.problem);

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(16),
      child: AppCard(
        padding: jobCardPadding,
        color: AppColors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: request.isEmergency ? AppColors.primary : AppColors.success, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(request.isEmergency ? 'ACTIVE · EMERGENCY' : 'ACTIVE',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: request.isEmergency ? AppColors.primary : AppColors.success,
                        letterSpacing: 0.5)),
              ],
            ),
            const SizedBox(height: 8),
            _MechanicContactRow(requestId: request.id, mechanicName: quote?.mechanicName ?? 'Mechanic'),
            const SizedBox(height: 8),
            Text(problem.issue, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Text(problem.description, style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55))),
            if (request.photoPaths.isNotEmpty) ...[
              const SizedBox(height: 10),
              JobPhotoPreview(photoPaths: request.photoPaths),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _locationBlock(request.location)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Payment', style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55))),
                    const SizedBox(height: 2),
                    // Same rule the Mechanic UI shows: an Emergency job has no
                    // price until the mechanic sets the agreed one, so it reads
                    // "To be agreed" rather than a stand-in amount.
                    Text(_paymentDisplay(request, quote),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.success)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            _JobActionButton(label: _statusLabel, color: _statusColor, onTap: onOpen),
          ],
        ),
      ),
    );
  }
}