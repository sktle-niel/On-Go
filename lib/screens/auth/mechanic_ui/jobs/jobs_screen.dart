import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../data/job_photo_store.dart';
import '../../../../data/mechanic_account_store.dart';
import '../../../../data/mechanic_settings_store.dart';
import '../../../../services/backend/mobile_backend.dart';
import '../../../../data/quote_store.dart';
import '../../../../data/review_store.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/chat_icon_button.dart';
import '../../../../widgets/common_widgets.dart';
import '../../../shared/job_chat_screen.dart';
import 'send_quote_sheet.dart';
import 'mechanic_active_job_screen.dart';
import '../../../../widgets/job_photo_preview.dart';

/// A request to bring one open job into view — raised when the mechanic taps a
/// notification about it, so they land on THAT job rather than on a list they
/// then have to search.
///
/// Deliberately not `==`-comparable: tapping the same notification twice is
/// two requests, and each must move the screen again.
class JobFocusRequest {
  final String requestId;

  /// Which list the job lives in: Emergency, or Available.
  final bool emergency;

  JobFocusRequest(this.requestId, {required this.emergency});
}

/// How long a job brought into view by a notification stays outlined — long
/// enough to find it on a busy list, short enough not to linger as if it were
/// a state of the job.
const Duration _spotlightDuration = Duration(seconds: 5);

/// Outlines a job card that a notification pointed at.
///
/// The outline is painted OVER the card rather than around it, so turning it
/// on and off never nudges the list by the width of a border.
class _Spotlight extends StatelessWidget {
  const _Spotlight({super.key, required this.on, required this.child});

  final bool on;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      foregroundDecoration: BoxDecoration(
        borderRadius: AppRadii.borderLg,
        border: Border.all(
          color: on ? AppColors.primary : AppColors.primary.withValues(alpha: 0),
          width: 2.5,
        ),
      ),
      child: child,
    );
  }
}

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key, this.focus});

  /// Set by the mechanic shell when a notification should open a specific job
  /// here. The screen consumes each request and clears it back to null.
  final ValueNotifier<JobFocusRequest?>? focus;

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  int _tabIndex = 0;
  bool? _wasApproved;
  Timer? _ticker;

  // What a notification needs in order to open one job on this screen: a way
  // to scroll each open-jobs list, a handle on each card, and which card is
  // currently spotlighted.
  final _availableScroll = ScrollController();
  final _emergencyScroll = ScrollController();
  final Map<String, GlobalKey> _cardKeys = {};
  String? _spotlightId;
  Timer? _spotlightTimer;

  GlobalKey _cardKeyFor(String requestId) => _cardKeys.putIfAbsent(requestId, GlobalKey.new);

  String get _mechanicName => QuoteNotificationStore.currentMechanicName;

  @override
  void initState() {
    super.initState();
    MechanicAccountStore.instance.addListener(_onAccountChange);
    _wasApproved = MechanicAccountStore.instance.canPerformJobActions;
    // Drives the Accepted tab's live countdown and hands back any job that
    // ran past its completion deadline. Both read that deadline off the
    // request itself, so the clock is unaffected by this timer starting,
    // stopping or restarting.
    _ticker = Timer.periodic(const Duration(seconds: 1), _onTick);
    widget.focus?.addListener(_onFocusRequested);
    // A request made before this screen existed is still waiting to be served.
    if (widget.focus?.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onFocusRequested());
    }
  }

  @override
  void didUpdateWidget(covariant JobsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focus != widget.focus) {
      oldWidget.focus?.removeListener(_onFocusRequested);
      widget.focus?.addListener(_onFocusRequested);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _spotlightTimer?.cancel();
    widget.focus?.removeListener(_onFocusRequested);
    _availableScroll.dispose();
    _emergencyScroll.dispose();
    MechanicAccountStore.instance.removeListener(_onAccountChange);
    super.dispose();
  }

  void _onFocusRequested() {
    final request = widget.focus?.value;
    if (request == null || !mounted) return;
    // Consumed, so the same notification tapped again raises a fresh request.
    // After the frame: clearing it synchronously would notify from inside the
    // notification that got us here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.focus?.value == request) widget.focus?.value = null;
    });
    _focusJob(request);
  }

  /// Switches to the list [request] lives in, scrolls its card into view and
  /// outlines it for a few seconds.
  Future<void> _focusJob(JobFocusRequest request) async {
    _onTabChanged(request.emergency ? _JobTabBar.emergencyIndex : _JobTabBar.availableIndex);
    setState(() => _spotlightId = request.requestId);
    _spotlightTimer?.cancel();
    _spotlightTimer = Timer(_spotlightDuration, () {
      if (mounted) setState(() => _spotlightId = null);
    });

    // The same filter the tab itself applies, so the index is the card's
    // position in the list on screen.
    final list = QuoteNotificationStore.instance.availableJobs
        .where((r) => r.isEmergency == request.emergency)
        .toList();
    final index = list.indexWhere((r) => r.id == request.requestId);
    if (index < 0) return;
    final controller = request.emergency ? _emergencyScroll : _availableScroll;

    // A long list only builds the cards near the viewport, so the card may not
    // exist yet. Each pass either finds it and scrolls it into view, or moves
    // the list toward where it will be and tries again once that has built.
    for (var attempt = 0; attempt < 6; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final cardContext = _cardKeys[request.requestId]?.currentContext;
      if (cardContext != null && cardContext.mounted) {
        await Scrollable.ensureVisible(
          cardContext,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          alignment: 0.1,
        );
        return;
      }
      if (controller.hasClients) {
        final position = controller.position;
        final target = position.maxScrollExtent * index / list.length;
        controller.jumpTo(target.clamp(position.minScrollExtent, position.maxScrollExtent));
      }
    }
  }

  void _onTick(Timer _) {
    final store = QuoteNotificationStore.instance;
    // Notifies (and so rebuilds) by itself only when something actually
    // expired; the setState below is just for the ticking numbers.
    store.expireOverdueJobs();
    if (!mounted) return;
    final counting = store
        .matchedJobsFor(_mechanicName)
        .any((r) => jobCountdown(r, store.acceptedQuoteFor(r.id)) != null);
    if (counting) setState(() {});
  }

  /// Opening the Emergency tab is what "viewing the Emergency Jobs list"
  /// means, so that is where the pulse stops.
  void _onTabChanged(int index) {
    if (index == _JobTabBar.emergencyIndex) {
      QuoteNotificationStore.instance.markEmergencyJobsSeen();
    }
    setState(() => _tabIndex = index);
  }

  void _onAccountChange() {
    final account = MechanicAccountStore.instance;
    final nowApproved = account.canPerformJobActions;
    if (nowApproved && _wasApproved == false && !account.isDemo) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your mechanic account has been approved. You can now send quotes and accept jobs.'), duration: AppDurations.snackBar),
        );
      });
    }
    _wasApproved = nowApproved;
  }

  Future<void> _sendQuote(HelpRequest request) async {
    if (!MechanicAccountStore.instance.canPerformJobActions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your account must be approved before you can send quotes.'), duration: AppDurations.snackBar),
      );
      return;
    }

    final input = await showModalBottomSheet<QuoteInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SendQuoteSheet(request: request),
    );
    if (input == null) return;

    try {
      QuoteNotificationStore.instance.mechanicSendQuote(
        request.id,
        mechanicName: _mechanicName,
        price: '₱${input.total.toStringAsFixed(0)}',
        eta: input.eta,
        rating: ReviewStore.instance.averageRatingFor(_mechanicName),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), duration: AppDurations.snackBar));
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Quote sent — the client will compare offers and choose.'), duration: AppDurations.snackBar),
    );
  }

  /// Takes back an offer the client hasn't accepted yet.
  ///
  /// Confirmed first, because the client stops seeing the quote the moment it
  /// happens — and unlike a rejection, this one is the mechanic's own doing,
  /// so they can quote the job again afterwards.
  Future<void> _withdrawQuote(HelpRequest request) async {
    final quote = QuoteNotificationStore.instance.mechanicLiveQuoteFor(request.id, _mechanicName);
    if (quote == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw your quote?'),
        content: Text(
          '${request.clientName} will no longer see your ${quote.price} quote or your '
          '${quote.eta} arrival time, and cannot accept it.\n\n'
          'You can send this job a new quote afterwards.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Quote')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text('Withdraw', style: TextStyle(color: AppColors.textlight)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final withdrawn =
        QuoteNotificationStore.instance.mechanicWithdrawQuote(request.id, mechanicName: _mechanicName);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(withdrawn
            ? 'Quote withdrawn. The client can no longer see it.'
            : 'That quote has already been accepted, so it can no longer be withdrawn.'),
        duration: AppDurations.snackBar,
      ),
    );
  }

  Future<void> _acceptEmergency(HelpRequest request) async {
    if (!MechanicAccountStore.instance.canPerformJobActions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your account must be approved before you can accept jobs.'), duration: AppDurations.snackBar),
      );
      return;
    }

    final store = QuoteNotificationStore.instance;

    if (store.mechanicHasActiveEmergency(_mechanicName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finish your current emergency job before accepting another.'), duration: AppDurations.snackBar),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.primary),
            SizedBox(width: 8),
            Expanded(child: Text('Emergency Job')),
          ],
        ),
        content: const Text(
          'This is an emergency request. Once accepted, you must head to the client\'s location right away — there\'s no time to spare. Are you ready to respond ASAP?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not Now')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Accept & Go ASAP'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final won = store.mechanicAcceptEmergency(
      request.id,
      mechanicName: _mechanicName,
      // No price on purpose — an emergency's amount is agreed with the client
      // in person and set via Set Payment Amount, so there is nothing to
      // record here yet.
      eta: const Duration(minutes: 15),
      rating: ReviewStore.instance.averageRatingFor(_mechanicName),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(won
            ? 'Job accepted! Head to the client now.'
            : 'Too late — another mechanic already took this emergency.'),
        duration: AppDurations.snackBar,
      ),
    );
  }

  Future<void> _openActiveJob(HelpRequest request) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MechanicActiveJobScreen(requestId: request.id)),
    );
  }

  Future<void> _cancelAccepted(HelpRequest request) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Cancel this job?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Let ${request.clientName} know why you can\'t continue with this job.'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                autofocus: true,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(hintText: 'Reason for cancelling (required)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Keep Job')),
            TextButton(
              onPressed: controller.text.trim().isEmpty ? null : () => Navigator.pop(ctx, controller.text.trim()),
              child: Text('Cancel Job', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      ),
    );
    if (reason == null || reason.isEmpty || !mounted) return;

    try {
      final ok = QuoteNotificationStore.instance.mechanicCancelJob(request.id, reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Job cancelled — the client has been notified.' : 'Could not cancel this job.'), duration: AppDurations.snackBar),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), duration: AppDurations.snackBar));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        QuoteNotificationStore.instance,
        MechanicAccountStore.instance,
        MechanicSettingsStore.instance,
      ]),
      builder: (context, _) {
        final store = QuoteNotificationStore.instance;
        final account = MechanicAccountStore.instance;
        final canAct = account.canPerformJobActions;

        // Sitting on the Emergency tab counts as viewing the list, so a job
        // that arrives while it is open is already seen and never pulses.
        // Deferred to after the frame — this notifies, and we are in build.
        if (_tabIndex == _JobTabBar.emergencyIndex && store.hasUnseenEmergencyJobs) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) QuoteNotificationStore.instance.markEmergencyJobsSeen();
          });
        }

        // The toggle wins outright: off means never pulse.
        final pulseEmergency = MechanicSettingsStore.instance.emergencyPulseEnabled &&
            _tabIndex != _JobTabBar.emergencyIndex &&
            store.hasUnseenEmergencyJobs;

        final allAvailable = store.availableJobs;
        final available = allAvailable.where((r) => !r.isEmergency).toList();
        final emergency = allAvailable.where((r) => r.isEmergency).toList();
        final accepted = store.matchedJobsFor(_mechanicName);
        final hasActiveEmergency = store.mechanicHasActiveEmergency(_mechanicName);

        return Column(
          children: [
            if (account.isDemo) const _DemoModeBanner(),
            if (account.isRegistered && account.status != ApprovalStatus.approved)
              _ApprovalBanner(status: account.status),
            _JobTabBar(
              currentIndex: _tabIndex,
              onChanged: _onTabChanged,
              counts: [available.length, emergency.length, accepted.length],
              pulseEmergency: pulseEmergency,
            ),
            Expanded(
              child: IndexedStack(
                index: _tabIndex,
                children: [
                  _AvailableTab(
                    requests: available,
                    canAct: canAct,
                    onSendQuote: _sendQuote,
                    onWithdrawQuote: _withdrawQuote,
                    controller: _availableScroll,
                    cardKeyFor: _cardKeyFor,
                    spotlightId: _spotlightId,
                  ),
                  _EmergencyTab(
                    requests: emergency,
                    onAccept: _acceptEmergency,
                    blocked: hasActiveEmergency,
                    canAct: canAct,
                    controller: _emergencyScroll,
                    cardKeyFor: _cardKeyFor,
                    spotlightId: _spotlightId,
                  ),
                  _AcceptedTab(
                    requests: accepted,
                    store: store,
                    onOpen: _openActiveJob,
                    onCancel: (r) {
                      _cancelAccepted(r);
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------
// Approval / demo banners
// ---------------------------------------------------------------------

class _DemoModeBanner extends StatelessWidget {
  const _DemoModeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.science_outlined, size: 14, color: AppColors.info),
          SizedBox(width: 6),
          // Flexible so the banner shortens rather than overflowing on a
          // narrow screen or at a large system text scale.
          Flexible(
            child: Text(
              'DEMO MODE — for testing only',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AppColors.info, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalBanner extends StatelessWidget {
  final ApprovalStatus? status;
  const _ApprovalBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final rejected = status == ApprovalStatus.rejected;
    final color = rejected ? AppColors.primary : AppColors.warning;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (rejected ? AppColors.primary : AppColors.warning).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (rejected ? AppColors.primary : AppColors.warning).withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(rejected ? Icons.cancel_outlined : Icons.hourglass_top, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              rejected
                  ? 'Your mechanic account was rejected. You can browse jobs, but job actions remain locked.'
                  // No request on this device: signed in from the API, which
                  // does not serve verification yet. Unknown is not pending.
                  : status == null
                      ? "Your account's verification status isn't available in the app yet. You can browse jobs, but job actions are locked until your account is approved."
                      : 'Your mechanic account is awaiting approval. You can browse jobs, but job actions are locked until approval.',
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Small display helpers
// ---------------------------------------------------------------------

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

String _timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min${diff.inMinutes == 1 ? '' : 's'} ago';
  if (diff.inHours < 24) return '${diff.inHours} hr${diff.inHours == 1 ? '' : 's'} ago';
  return '${time.month.toString().padLeft(2, '0')}/${time.day.toString().padLeft(2, '0')}/${time.year}';
}

class _ProblemText {
  final String issue;
  final String description;
  const _ProblemText(this.issue, this.description);
}

_ProblemText _splitProblem(String problem) {
  final idx = problem.indexOf(':');
  if (idx == -1 || idx > 40) {
    return _ProblemText('Reported Issue', problem);
  }
  final rest = problem.substring(idx + 1).trim();
  return _ProblemText(problem.substring(0, idx).trim(), rest.isEmpty ? problem : rest);
}

// ---------------------------------------------------------------------
// Tab bar
// ---------------------------------------------------------------------

class _JobTabBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onChanged;
  final List<int> counts;

  /// Whether the Emergency pill should be pulsing right now. The screen works
  /// this out from unviewed emergency jobs AND the mechanic's alert toggle, so
  /// this widget just plays or stops the animation.
  final bool pulseEmergency;

  const _JobTabBar({
    required this.currentIndex,
    required this.onChanged,
    required this.counts,
    this.pulseEmergency = false,
  });

  static const _labels = ['Available', 'Emergency', 'Accepted'];

  /// The index of the Available pill in [_labels].
  static const int availableIndex = 0;

  /// The index of the Emergency pill in [_labels].
  static const int emergencyIndex = 1;

  @override
  State<_JobTabBar> createState() => _JobTabBarState();
}

class _JobTabBarState extends State<_JobTabBar> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    if (widget.pulseEmergency) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _JobTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulseEmergency == oldWidget.pulseEmergency) return;
    if (widget.pulseEmergency) {
      _pulse.repeat(reverse: true);
    } else {
      // Back to the pill's normal, unanimated look.
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// The pill exactly as it has always looked. [glow] is 0 when nothing is
  /// pulsing, which leaves the original decoration untouched.
  Widget _pill(int i, {double glow = 0}) {
    final selected = i == widget.currentIndex;
    return Semantics(
      button: true,
      selected: selected,
      child: Container(
        margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
        // 12 above and below brings the pill up to a comfortable thumb height.
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: selected ? AppColors.primary : AppColors.textdark.withValues(alpha: 0.2)),
          boxShadow: glow == 0
              ? null
              : [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.45 * glow),
                    blurRadius: 14 * glow,
                    spreadRadius: 2 * glow,
                  ),
                ],
        ),
        child: Text('${_JobTabBar._labels[i]} ${widget.counts[i]}',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.textlight : AppColors.textmedium)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: List.generate(3, (i) {
          final pulsing = widget.pulseEmergency && i == _JobTabBar.emergencyIndex;

          return Expanded(
            child: GestureDetector(
              onTap: () => widget.onChanged(i),
              child: pulsing
                  ? AnimatedBuilder(
                      // Present only while the pill is actually pulsing.
                      key: const ValueKey('emergencyPulse'),
                      animation: _pulse,
                      builder: (context, _) {
                        // Curved so the pill swells and settles rather than
                        // ticking linearly between the two extremes.
                        final t = Curves.easeInOut.transform(_pulse.value);
                        // Transform, not layout — the row never reflows, so
                        // the other two pills stay exactly where they are.
                        return Transform.scale(
                          scale: 1 + 0.05 * t,
                          child: _pill(i, glow: t),
                        );
                      },
                    )
                  : _pill(i),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------

class _TipCard extends StatelessWidget {
  const _TipCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: 'Tip: ', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.info)),
            TextSpan(
              text: 'Send competitive quotes to win more jobs! Clients compare multiple mechanics before choosing.',
              style: TextStyle(color: AppColors.info),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

class _LocationBlock extends StatelessWidget {
  final String location;
  const _LocationBlock({required this.location});

  @override
  Widget build(BuildContext context) {
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
}

class _DeadlineRow extends StatelessWidget {
  final HelpRequest request;
  const _DeadlineRow({required this.request});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 13, color: AppColors.textdark.withValues(alpha: 0.55)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(request.durationLabel, style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55))),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Available tab (non-emergency, quote-based jobs)
// ---------------------------------------------------------------------

class _AvailableTab extends StatelessWidget {
  final List<HelpRequest> requests;
  final bool canAct;
  final void Function(HelpRequest) onSendQuote;
  final void Function(HelpRequest) onWithdrawQuote;
  final ScrollController controller;
  final GlobalKey Function(String requestId) cardKeyFor;
  final String? spotlightId;

  const _AvailableTab({
    required this.requests,
    required this.canAct,
    required this.onSendQuote,
    required this.onWithdrawQuote,
    required this.controller,
    required this.cardKeyFor,
    this.spotlightId,
  });

  @override
  Widget build(BuildContext context) {
    final mechanicName = QuoteNotificationStore.currentMechanicName;

    return ListView(
      controller: controller,
      padding: context.layout.listInsets(),
      children: [
        const _TipCard(),
        const SizedBox(height: 16),
        if (requests.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text('No available jobs right now', style: TextStyle(color: AppColors.textdark.withValues(alpha: 0.55))),
            ),
          ),
        ...requests.map((request) {
          final store = QuoteNotificationStore.instance;
          // Three states, in order of precedence: an offer of theirs is
          // standing (they can take it back), the client already turned one
          // down (nothing more to do here), or the job is open to them.
          final live = store.mechanicLiveQuoteFor(request.id, mechanicName);
          final rejected = store.mechanicQuoteWasRejected(request.id, mechanicName);
          return Padding(
            padding: const EdgeInsets.only(bottom: jobCardSpacing),
            child: _Spotlight(
              key: cardKeyFor(request.id),
              on: spotlightId == request.id,
              child: _JobCard(
                request: request,
                actionLabel: live != null
                    ? 'Withdraw Quote'
                    : (rejected ? 'Quote Rejected' : 'Send Quote'),
                actionEnabled: live != null ? !live.accepted : (canAct && !rejected),
                actionIsDestructive: live != null,
                onAction: () => live != null ? onWithdrawQuote(request) : onSendQuote(request),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _JobCard extends StatelessWidget {
  final HelpRequest request;
  final String actionLabel;
  final bool actionEnabled;

  /// Draws the action as an undo rather than a commitment — Withdraw Quote
  /// sits in the same place as Send Quote and must not look like it.
  final bool actionIsDestructive;
  final VoidCallback onAction;

  const _JobCard({
    required this.request,
    required this.actionLabel,
    required this.onAction,
    this.actionEnabled = true,
    this.actionIsDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final problem = _splitProblem(request.problem);
    final urgencyColor = _urgencyColor(request.urgency);

    return AppCard(
      padding: jobCardPadding,
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request.clientName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    Text(_timeAgo(request.createdAt),
                        style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55))),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: urgencyColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                child: Text(request.urgency,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: urgencyColor)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(problem.issue, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 2),
          Text(problem.description, style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55))),
          if (JobPhotoStore.instance.hasPhotos(request.id)) ...[
            const SizedBox(height: 10),
            JobPhotoPreview(photoPaths: JobPhotoStore.instance.pathsFor(request.id)),
          ],
          const SizedBox(height: 10),
          _LocationBlock(location: request.location),
          _DeadlineRow(request: request),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: actionIsDestructive
                ? OutlinedButton(
                    onPressed: actionEnabled ? onAction : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(color: AppColors.error),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(actionLabel),
                  )
                : ElevatedButton(
                    onPressed: actionEnabled ? onAction : null,
                    style: ElevatedButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(vertical: 12)),
                    child: Text(actionLabel),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Emergency tab
// ---------------------------------------------------------------------

class _EmergencyTab extends StatelessWidget {
  final List<HelpRequest> requests;
  final void Function(HelpRequest) onAccept;
  final bool blocked;
  final bool canAct;
  final ScrollController controller;
  final GlobalKey Function(String requestId) cardKeyFor;
  final String? spotlightId;

  const _EmergencyTab({
    required this.requests,
    required this.onAccept,
    required this.blocked,
    required this.canAct,
    required this.controller,
    required this.cardKeyFor,
    this.spotlightId,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      padding: context.layout.listInsets(),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                    text: blocked ? 'You\'re on a job: ' : 'Heads up: ',
                    style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                TextSpan(
                  text: blocked
                      ? 'Finish your current emergency job before accepting another one.'
                      : 'Emergencies are first come, first served — once accepted there\'s no backing out, you\'ll need to respond ASAP.',
                  style: TextStyle(color: AppColors.primary),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 16),
        if (requests.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text('No emergency jobs right now', style: TextStyle(color: AppColors.textdark.withValues(alpha: 0.55))),
            ),
          ),
        ...requests.map((request) => Padding(
              padding: const EdgeInsets.only(bottom: jobCardSpacing),
              child: _Spotlight(
                key: cardKeyFor(request.id),
                on: spotlightId == request.id,
                child: _JobCard(
                  request: request,
                  actionLabel: 'Accept',
                  actionEnabled: canAct && !blocked,
                  onAction: () => onAccept(request),
                ),
              ),
            )),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Accepted tab
// ---------------------------------------------------------------------

/// Sort options for the Accepted list. [urgency] is the default — the order
/// dispatch actually cares about (Emergency → Urgent → Normal).
enum _AcceptedSort { urgency, dateAccepted, timeRemaining }

extension on _AcceptedSort {
  String get label => switch (this) {
        _AcceptedSort.urgency => 'Urgency Level',
        _AcceptedSort.dateAccepted => 'Date Accepted',
        _AcceptedSort.timeRemaining => 'Time Remaining',
      };
}

class _AcceptedTab extends StatefulWidget {
  final List<HelpRequest> requests;
  final QuoteNotificationStore store;
  final void Function(HelpRequest) onOpen;
  final void Function(HelpRequest) onCancel;

  const _AcceptedTab({required this.requests, required this.store, required this.onOpen, required this.onCancel});

  @override
  State<_AcceptedTab> createState() => _AcceptedTabState();
}

class _AcceptedTabState extends State<_AcceptedTab> {
  _AcceptedSort _sort = _AcceptedSort.urgency;
  bool _sortOpen = false;

  static DateTime _acceptedAt(HelpRequest r) => r.matchedAt ?? r.createdAt;

  List<HelpRequest> get _sorted {
    final list = [...widget.requests];
    switch (_sort) {
      case _AcceptedSort.urgency:
        list.sort((a, b) {
          final byUrgency = urgencyPriority(a.urgency).compareTo(urgencyPriority(b.urgency));
          return byUrgency != 0 ? byUrgency : _acceptedAt(b).compareTo(_acceptedAt(a));
        });
      case _AcceptedSort.dateAccepted:
        list.sort((a, b) => _acceptedAt(b).compareTo(_acceptedAt(a)));
      case _AcceptedSort.timeRemaining:
        final store = QuoteNotificationStore.instance;
        list.sort((a, b) {
          // Whatever each job is actually counting down to — a completion
          // deadline for Urgent and Emergency, the quoted arrival for Normal.
          final left = jobCountdown(a, store.acceptedQuoteFor(a.id))?.remaining;
          final right = jobCountdown(b, store.acceptedQuoteFor(b.id))?.remaining;
          // Jobs already under way have no clock left to run, so they sit
          // below the ones still waiting to be started.
          if (left == null && right == null) return _acceptedAt(b).compareTo(_acceptedAt(a));
          if (left == null) return 1;
          if (right == null) return -1;
          return left.compareTo(right);
        });
    }
    return list;
  }

  Widget _sortPill(_AcceptedSort value) {
    final selected = _sort == value;
    return GestureDetector(
      onTap: () => setState(() {
        _sort = value;
        _sortOpen = false;
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.primary : AppColors.textdark.withValues(alpha: 0.2)),
        ),
        child: Text(value.label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? AppColors.textlight : AppColors.textdark)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.requests.isEmpty) {
      return Center(child: Text('No active jobs', style: TextStyle(color: AppColors.textdark.withValues(alpha: 0.55))));
    }

    return Stack(
      children: [
        ListView(
          padding: context.layout.listInsets(),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Sorted by ${_sort.label}',
                      style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55), fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  tooltip: 'Sort accepted jobs',
                  onPressed: () => setState(() => _sortOpen = !_sortOpen),
                ),
              ],
            ),
            ..._sorted.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: jobCardSpacing),
                  child: _ActiveJobCard(
                    request: r,
                    quote: widget.store.acceptedQuoteFor(r.id),
                    onOpen: () => widget.onOpen(r),
                    onCancel: () => widget.onCancel(r),
                  ),
                )),
          ],
        ),
        if (_sortOpen) ...[
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _sortOpen = false),
              child: Container(color: Colors.transparent),
            ),
          ),
          Positioned(
            top: 46,
            right: 16,
            width: 170,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('Sort by', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  _sortPill(_AcceptedSort.urgency),
                  _sortPill(_AcceptedSort.dateAccepted),
                  _sortPill(_AcceptedSort.timeRemaining),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

String _mechanicStatusLabel(HelpRequest request) {
  if (!request.navigating) return 'Navigate';
  if (!request.arrived) return 'En Route';
  if (!request.workStarted) return 'Mechanic Arrived';
  if (!request.serviceCompleted) return 'Work in Progress';
  return 'Awaiting Payment';
}

class _ActiveJobCard extends StatelessWidget {
  final HelpRequest request;
  final MechanicQuote? quote;
  final VoidCallback onOpen;
  final VoidCallback onCancel;

  const _ActiveJobCard({required this.request, required this.quote, required this.onOpen, required this.onCancel});

  void _openChat(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => JobChatScreen(requestId: request.id, otherPartyName: request.clientName)),
      );

  @override
  Widget build(BuildContext context) {
    final problem = _splitProblem(request.problem);
    final label = _mechanicStatusLabel(request);
    final statusColor = label == 'Awaiting Payment' ? AppColors.primary : AppColors.success;
    final showCancel = !request.isEmergency && !request.navigating;

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
                  decoration: BoxDecoration(
                      color: request.isEmergency ? AppColors.primary : AppColors.success, shape: BoxShape.circle),
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.clientName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.2),
                  ),
                ),
                CircleIconButton(
                  icon: Icons.call,
                  color: AppColors.success,
                  tooltip: 'Call ${request.clientName}',
                  onTap: () => showContactSheet(
                    context,
                    name: request.clientName,
                    // Clients' numbers aren't shared with mechanics yet, so
                    // the sheet leads with the chat.
                    phone: '',
                    onMessage: () => _openChat(context),
                  ),
                ),
                ChatIconButton(requestId: request.id, onTap: () => _openChat(context)),
              ],
            ),
            const SizedBox(height: 8),
            Text(problem.issue, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Text(problem.description, style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55))),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _LocationBlock(location: request.location)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Payment', style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55))),
                    const SizedBox(height: 2),
                    Text(_paymentDisplay(request, quote),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.success)),
                  ],
                ),
              ],
            ),
            // No "Completed within …" line here: once the job is accepted the
            // live countdown below is the only deadline that matters.
            _TimeRemainingRow(request: request),
            const SizedBox(height: 14),
            showCancel
                ? Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: onOpen,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: statusColor,
                            foregroundColor: AppColors.textlight,
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(label),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: onCancel,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.textlight,
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ],
                  )
                : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onOpen,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: statusColor,
                        foregroundColor: AppColors.textlight,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(label),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

/// Live countdown line for an accepted job. Which clock it shows is
/// [jobCountdown]'s decision, not this widget's:
///
///   - Urgent and Emergency count down to the job's completion deadline —
///     accept time plus the urgency's window — labelled "Time Remaining".
///   - Normal has no completion deadline, so it counts down to the arrival
///     time the mechanic quoted, labelled "Arriving in".
///
/// Either way the value is derived from a stored timestamp, so it keeps
/// running across rebuilds, navigation and app reopens instead of restarting,
/// and is never a stored or hard-coded figure. Renders nothing once the
/// countdown stops — Work in Progress for a completion clock, arrival for an
/// ETA clock — which stops the expiry too rather than just hiding it.
class _TimeRemainingRow extends StatelessWidget {
  final HelpRequest request;

  const _TimeRemainingRow({required this.request});

  @override
  Widget build(BuildContext context) {
    final countdown = jobCountdown(request, QuoteNotificationStore.instance.acceptedQuoteFor(request.id));
    if (countdown == null) return const SizedBox.shrink();
    final remaining = countdown.remaining;

    // Runs hot in the final hour, so a job about to be handed back reads as
    // urgent rather than as just another grey line.
    final color = remaining <= const Duration(hours: 1) ? AppColors.primary : AppColors.textdark.withValues(alpha: 0.55);

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 13, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text('${countdown.label}: ${formatTimeRemaining(remaining)}',
                style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
