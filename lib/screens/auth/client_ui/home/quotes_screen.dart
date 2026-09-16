import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/common_widgets.dart';
// Todo: adjust this path to wherever quote_store.dart lives in your project
import '../../../../data/quote_store.dart';
import '../profile/mechanic_profile_view_screen.dart';

class QuotesScreen extends StatefulWidget {
  /// When set, only this request's quotes are shown (used by the "Quotes"
  /// button on each Uploaded job card). When null, every pending request is
  /// listed — kept for backward compatibility, though nothing wires the
  /// bell to this anymore.
  final String? requestId;

  /// The quote a notification pointed at. When set, that row is highlighted
  /// and scrolled into view, so the client lands on the offer they were told
  /// about rather than having to find it among the job's other quotes.
  final String? focusQuoteId;

  const QuotesScreen({super.key, this.requestId, this.focusQuoteId});

  @override
  State<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends State<QuotesScreen> {
  final _focusKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.requestId != null) {
        QuoteNotificationStore.instance.markRequestQuotesSeen(widget.requestId!);
      } else {
        QuoteNotificationStore.instance.markSeen();
      }
      final focused = _focusKey.currentContext;
      if (focused != null) {
        Scrollable.ensureVisible(
          focused,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.3,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textmedium,
        title: const Text('Quotes'),
      ),
      body: AnimatedBuilder(
        animation: QuoteNotificationStore.instance,
        builder: (context, _) {
          final store = QuoteNotificationStore.instance;

          List<HelpRequest> pending;
          if (widget.requestId != null) {
            final single = store.requestFor(widget.requestId!);
            pending = (single != null && single.status == RequestStatus.pending) ? [single] : [];
          } else {
            pending = store.myPendingRequests;
          }

          if (pending.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.hourglass_empty, size: 48, color: AppColors.textdark.withValues(alpha: 0.55)),
                  const SizedBox(height: 12),
                  Text(
                    widget.requestId != null ? 'No quotes for this job yet' : 'No quotes yet',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.requestId != null
                        ? 'This job has either already been matched or is still waiting on mechanics.'
                        : 'Upload a problem from the Need Help tab and mechanic quotes will show up here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: context.layout.pageInsets,
            children: [
              // The app bar already says Quotes, so the page opens on what
              // matters: how many requests are waiting on the client.
              Text('${pending.length} request${pending.length == 1 ? '' : 's'} awaiting your decision',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textdark.withValues(alpha: 0.55))),
              const SizedBox(height: 16),
              ...pending.map((request) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _RequestQuoteCard(
                      request: request,
                      store: store,
                      focusQuoteId: widget.focusQuoteId,
                      focusKey: _focusKey,
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}

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

class _RequestQuoteCard extends StatelessWidget {
  final HelpRequest request;
  final QuoteNotificationStore store;
  final String? focusQuoteId;
  final GlobalKey? focusKey;

  const _RequestQuoteCard({
    required this.request,
    required this.store,
    this.focusQuoteId,
    this.focusKey,
  });

  /// Turning a quote down is final for that mechanic — they are told, and they
  /// cannot re-quote this job — so it is confirmed rather than one stray tap
  /// away.
  Future<void> _reject(BuildContext context, MechanicQuote quote) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject this quote?'),
        content: Text(
          '${quote.mechanicName} will be told you turned down their ${quote.price} quote, '
          'and will not be able to quote this job again.\n\n'
          'Your request stays open, and other mechanics can still send quotes.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text('Reject', style: TextStyle(color: AppColors.textlight)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final name = quote.mechanicName;
    if (store.clientRejectQuote(quote.id) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Quote rejected. $name has been notified.'),
          duration: AppDurations.snackBar,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final problem = _splitProblem(request.problem);
    final urgencyColor = _urgencyColor(request.urgency);
    final quotes = store.quotesForRequest(request.id);
    final hasAccepted = quotes.any((q) => q.accepted);

    return AppCard(
      padding: const EdgeInsets.all(14),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(problem.issue, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: urgencyColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                child: Text(request.urgency, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: urgencyColor)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(problem.description, style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55))),
          const SizedBox(height: 12),
          if (quotes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                request.isEmergency ? 'Waiting for a mechanic to accept this emergency.' : 'Waiting for mechanics to send quotes...',
                style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                    flex: 3,
                    child: Text('Mechanic',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textdark.withValues(alpha: 0.55)))),
                Expanded(
                    flex: 2,
                    child:
                        Text('Price', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textdark.withValues(alpha: 0.55)))),
                Expanded(
                    flex: 2,
                    child: Text('ETA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textdark.withValues(alpha: 0.55)))),
                Expanded(
                    flex: 2,
                    child: Text('Rating',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textdark.withValues(alpha: 0.55)))),
                SizedBox(width: 74),
              ],
            ),
            const Divider(height: 16),
            ...quotes.map((q) => _QuoteRow(
                  key: q.id == focusQuoteId ? focusKey : null,
                  spotlight: q.id == focusQuoteId,
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: _MechanicNameLink(name: q.mechanicName)),
                      Expanded(flex: 2, child: Text(q.price, style: const TextStyle(fontSize: 13))),
                      Expanded(flex: 2, child: Text(q.eta, style: const TextStyle(fontSize: 13))),
                      Expanded(
                        flex: 2,
                        // On a 320-point phone this column is about 42 points
                        // wide, a little less than the star and the figure
                        // need, so the pair ran past the column into the next.
                        // Scale-down only: wherever it already fits it is
                        // drawn exactly as before, and where it does not it
                        // shrinks slightly rather than clipping the rating.
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star, size: 14, color: AppColors.warning),
                                const SizedBox(width: 2),
                                Text(q.rating.toStringAsFixed(1), style: const TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 74,
                        child: q.accepted
                            ? Text('Accepted',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.success))
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ElevatedButton(
                                    onPressed: hasAccepted ? null : () => store.clientAcceptQuote(q.id),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      shape: const StadiumBorder(),
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(70, 32),
                                      textStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textmedium),
                                    ),
                                    child: Text('Accept', style: TextStyle(color: AppColors.textlight)),
                                  ),
                                  // The other half of the decision. Says no to
                                  // one mechanic and tells them so, rather than
                                  // leaving the quote sitting unanswered.
                                  TextButton(
                                    onPressed: hasAccepted ? null : () => _reject(context, q),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppColors.error,
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(70, 26),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                                    ),
                                    child: const Text('Reject'),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}
/// One quote's row, tinted when it is the one a notification pointed at.
///
/// The tint is painted behind the row without adding padding, so a
/// highlighted row keeps its columns lined up with the header above it.
class _QuoteRow extends StatelessWidget {
  const _QuoteRow({super.key, required this.spotlight, required this.child});

  final bool spotlight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: spotlight,
      label: spotlight ? 'The quote from your notification' : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: spotlight ? AppColors.info.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(10),
        ),
        position: DecorationPosition.background,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: spotlight ? Border.all(color: AppColors.info.withValues(alpha: 0.55)) : null,
          ),
          position: DecorationPosition.foreground,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A mechanic's name in a quote row, and the way into their profile.
///
/// Before deciding on a quote a client wants to know who is behind it — their
/// reviews, their certifications, how many jobs they have done. The name is
/// the obvious thing to tap for that, so the name is what opens it.
///
/// It looks as it did — same size, weight and colour — with a faint underline
/// added so it reads as something that can be tapped rather than a label. The
/// tap area covers the whole name column and extends above and below the text,
/// because 13-point text on its own is too small a target for a thumb. That
/// extra height never shows: every row on this screen is already as tall as
/// its Accept/Reject buttons, which are taller than the padded name.
class _MechanicNameLink extends StatelessWidget {
  const _MechanicNameLink({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: "View $name's profile",
      excludeSemantics: true,
      child: InkWell(
        onTap: () => MechanicProfileViewScreen.open(context, name),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            name,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.textdark.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
    );
  }
}
