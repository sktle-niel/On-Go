import 'package:flutter/material.dart';
import '../../../../data/points_wallet_store.dart';
import '../../../../data/quote_store.dart';
import '../../../../services/backend/mobile_backend.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/common_widgets.dart';
import '../rank/mechanic_rankings_screen.dart';
import 'points_offers_screen.dart';

class EarningScreen extends StatefulWidget {
  const EarningScreen({super.key, this.onViewAll});

  final VoidCallback? onViewAll;

  @override
  State<EarningScreen> createState() => _EarningScreenState();
}

class _EarningScreenState extends State<EarningScreen> {
  bool _showBalance = true;
  final _store = QuoteNotificationStore.instance;
  final _wallet = PointsWalletStore.instance;

  String get _mechanicName => QuoteNotificationStore.currentMechanicName;

  // Both halves of what this screen shows: the jobs store (earnings, history)
  // and the points wallet (points, and the balance conversions add). This tab
  // stays alive behind View Offer, so a conversion made there only reaches
  // this header if the header is listening to the wallet it was written to.
  late final Listenable _sources = Listenable.merge([_store, _wallet]);

  @override
  void initState() {
    super.initState();
    _sources.addListener(_onChange);
  }

  @override
  void dispose() {
    _sources.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _toggleBalance() => setState(() => _showBalance = !_showBalance);

  _ProblemText _splitProblem(String problem) {
    final idx = problem.indexOf(':');
    if (idx == -1 || idx > 40) return _ProblemText('Reported Issue', problem);
    final rest = problem.substring(idx + 1).trim();
    return _ProblemText(problem.substring(0, idx).trim(), rest.isEmpty ? problem : rest);
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    // The shared definition, not a sum made here — see availableBalanceFor.
    final balance = _store.availableBalanceFor(_mechanicName);
    // Spendable, not lifetime: converting draws this down.
    final points = _wallet.balanceFor(_mechanicName);
    final paidJobs = _store.completedJobsFor(_mechanicName)
      ..sort((a, b) => (b.paymentCompletedAt ?? b.createdAt).compareTo(a.paymentCompletedAt ?? a.createdAt));

    return ListView(
      padding: context.layout.pageInsets,
      children: [
        _EarningsHeader(
          showBalance: _showBalance,
          onToggle: _toggleBalance,
          balance: balance,
          points: points,
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // The heading yields to the action beside it rather than pushing
            // it off the row on a narrow phone.
            const Expanded(
              child: Text(
                'Top Mechanics',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2),
              ),
            ),
            TextButton(
              onPressed: widget.onViewAll ?? () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MechanicRankingsScreen()),
                  ),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(48, 44)),
              child: Text('View All',
                  style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppCard(
          color: AppColors.surface,
          padding: const EdgeInsets.all(16),
          // Todo: there's no multi-mechanic backend yet, so this is always
          // just the current mechanic — same single-entry source as
          // the Rankings list's own mechanic. Capped at 5 for when that changes.
          child: Row(
            children: [_mechanicName]
                .take(5)
                .map((name) => Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: CircleAvatar(
                        radius: 26,
                        backgroundColor: AppColors.background,
                        child: Icon(Icons.person, color: AppColors.textdark.withValues(alpha: 0.55)),
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Service History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
        const SizedBox(height: 12),
        if (paidJobs.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('Completed and paid jobs will show up here.', style: TextStyle(color: AppColors.textdark.withValues(alpha: 0.55), fontSize: 12)),
            ),
          )
        else
          ...paidJobs.map((job) {
            final quote = _store.acceptedQuoteFor(job.id);
            // What the mechanic was actually paid. Emergency jobs carry a
            // placeholder price on their accept record — the real figure is
            // the amount agreed in person — so this goes through the same
            // rule the balance above is summed from, never quote.price.
            final amount = effectivePaymentAmount(job, quote);
            final problem = _splitProblem(job.problem);
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(job.clientName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(problem.issue, style: TextStyle(fontSize: 12, color: AppColors.textdark)),
                        const SizedBox(height: 2),
                        Text(_formatDate(job.paymentCompletedAt), style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55))),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                          child: Text('Paid', style: TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(amount == null ? '—' : '₱${amount.toStringAsFixed(0)}',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.success)),
                      // No per-job points: what a job awards is the admin's
                      // to see. The Points total above still counts them.
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class _ProblemText {
  final String issue;
  final String description;
  const _ProblemText(this.issue, this.description);
}

/// The balance-and-points panel at the top of Earnings.
///
/// Two figures that want to sit side by side, and cannot on a narrow phone.
/// Half of a 320-point screen is about 110 points once the card's padding is
/// taken out, and "Available Balance" alone is wider than that — which is
/// what used to push this header off the right edge.
///
/// So the two halves stack below a threshold instead of being squeezed. The
/// threshold is measured against the room the header actually has, not the
/// width of the device, so the same panel behaves correctly if it is ever put
/// somewhere narrower.
class _EarningsHeader extends StatelessWidget {
  const _EarningsHeader({
    required this.showBalance,
    required this.onToggle,
    required this.balance,
    required this.points,
  });

  final bool showBalance;
  final VoidCallback onToggle;
  final double balance;
  final double points;

  /// Below this much room, side by side stops working: each column would get
  /// less than ~150 points, which is not enough for the label above a figure
  /// at this type size.
  static const double _sideBySideMin = 320;

  @override
  Widget build(BuildContext context) {
    final layout = context.layout;
    final divider = AppColors.surface.withValues(alpha: 0.3);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(layout.scale(18)),
      decoration: BoxDecoration(
        color: AppColors.primarydark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack = constraints.maxWidth < _sideBySideMin;

          final balanceHalf = _Figure(
            label: 'Available Balance',
            value: showBalance ? '₱${balance.toStringAsFixed(2)}' : '••••',
            trailing: InkWell(
              onTap: onToggle,
              child: Icon(
                showBalance ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: AppColors.textlight,
                size: 16,
              ),
            ),
          );

          final pointsHalf = _Figure(
            label: 'Points',
            leading: Icon(Icons.card_giftcard, color: AppColors.textlight, size: 16),
            value: showBalance ? formatPoints(points) : '••••',
            footer: const _ViewOfferButton(),
          );

          if (stack) {
            // Stacked, the rule between them turns from a vertical bar into a
            // horizontal one — it is still separating the two figures, just
            // along the other axis.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                balanceHalf,
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Container(height: 1, color: divider),
                ),
                pointsHalf,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: balanceHalf),
              Container(width: 1, height: 48, color: divider),
              const SizedBox(width: 20),
              Expanded(child: pointsHalf),
            ],
          );
        },
      ),
    );
  }
}

/// A label, a large figure, and optionally something after each.
///
/// The figure scales itself down rather than overflowing: a mechanic with a
/// six-figure balance should see the number get smaller, not get cut off.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.leading,
    this.trailing,
    this.footer,
  });

  final String label;
  final String value;
  final Widget? leading;
  final Widget? trailing;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 4)],
            // Flexible so a long label ellipses inside its column instead of
            // pushing the row wider than the card.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textlight,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 4), trailing!],
          ],
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              color: AppColors.textlight,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (footer != null) ...[const SizedBox(height: 8), footer!],
      ],
    );
  }
}
/// Opens the offers a mechanic can spend points on.
///
/// Its own widget so the earnings header stays a layout, and so the button
/// reads the same wherever it is put next.
class _ViewOfferButton extends StatelessWidget {
  const _ViewOfferButton();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PointsOffersScreen()),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          minimumSize: const Size(0, 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: AppColors.textlight.withValues(alpha: 0.18),
        ),
        icon: Icon(Icons.local_offer_outlined, size: 14, color: AppColors.textlight),
        label: Text(
          'View Offer',
          style: TextStyle(
            color: AppColors.textlight,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
