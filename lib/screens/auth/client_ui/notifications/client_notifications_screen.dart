import 'package:flutter/material.dart';

import '../../../../data/quote_store.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/notification_card.dart';
import '../active/active_request_screen.dart';
import '../home/quotes_screen.dart';
import '../../../../widgets/glass.dart';

/// What the client's bell opens: quotes that arrived and the progress the
/// mechanic reported on their job.
///
/// The list comes straight from [QuoteNotificationStore], which records an
/// entry at each of the four moments the client cares about. Opening this
/// screen is what marks them read and clears the badge — see
/// `ClientHomeScreen._openNotifications`.
class ClientNotificationsScreen extends StatelessWidget {
  const ClientNotificationsScreen({super.key});

  IconData _iconFor(ClientNotificationKind kind) {
    switch (kind) {
      case ClientNotificationKind.quoteReceived:
        return Icons.request_quote_outlined;
      case ClientNotificationKind.jobAccepted:
        return Icons.handshake_outlined;
      case ClientNotificationKind.workStarted:
        return Icons.build_outlined;
      case ClientNotificationKind.awaitingPayment:
        return Icons.payments_outlined;
      case ClientNotificationKind.etaPassed:
        return Icons.schedule_outlined;
      case ClientNotificationKind.jobCancelled:
        return Icons.cancel_outlined;
    }
  }

  Color _accentFor(ClientNotificationKind kind) {
    switch (kind) {
      case ClientNotificationKind.quoteReceived:
        return AppColors.info;
      case ClientNotificationKind.jobAccepted:
        return AppColors.success;
      case ClientNotificationKind.workStarted:
        return AppColors.primary;
      case ClientNotificationKind.awaitingPayment:
        return AppColors.warning;
      case ClientNotificationKind.etaPassed:
        return AppColors.error;
      case ClientNotificationKind.jobCancelled:
        return AppColors.error;
    }
  }

  String _formatWhen(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  /// Follows [notification] to what it is about. Where that is, is the store's
  /// call — made now, from the job's current state — so a notification for a
  /// job that has since finished explains itself instead of opening a stale
  /// quote.
  void _open(BuildContext context, ClientNotification notification) {
    final route = QuoteNotificationStore.instance.routeForClientNotification(notification);
    switch (route) {
      case OpenJobQuotes(:final requestId, :final quoteId):
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => QuotesScreen(requestId: requestId, focusQuoteId: quoteId)),
        );
      case OpenClientJob(:final requestId):
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ActiveRequestScreen(requestId: requestId)),
        );
      case NotificationUnavailable(:final message):
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message), duration: AppDurations.snackBar));
      case OpenMechanicJob() || OpenJobInList() || OpenMechanicTab():
        // Mechanic-side routes; never produced for a client notification.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
      ),
      body: AnimatedBuilder(
        animation: QuoteNotificationStore.instance,
        builder: (context, _) {
          final notifications = QuoteNotificationStore.instance.clientNotifications;

          if (notifications.isEmpty) {
            return const GlassEmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'No notifications yet',
              text: 'Quotes and updates on your job will appear here once a mechanic responds.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: notifications.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final n = notifications[index];
              final accent = _accentFor(n.kind);

              return NotificationCard(
                onTap: () => _open(context, n),
                semanticsLabel: '${n.title}. ${n.message}',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_iconFor(n.kind), size: 20, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  n.title,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                ),
                              ),
                              Text(
                                _formatWhen(n.createdAt),
                                style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            n.message,
                            style: TextStyle(fontSize: 13, color: AppColors.textdark.withValues(alpha: 0.55)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            n.problem,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
