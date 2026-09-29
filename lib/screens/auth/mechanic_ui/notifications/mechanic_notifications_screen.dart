import 'package:flutter/material.dart';

import '../../../../data/mechanic_notification_store.dart';
import '../../../../data/quote_store.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/notification_card.dart';
import '../jobs/mechanic_active_job_screen.dart';

/// What the mechanic's bell opens — the mechanic-side twin of
/// `ClientNotificationsScreen`, using the same card, icon and timestamp
/// treatment so both shells read the same way.
///
/// The list comes from [MechanicNotificationStore], which records an entry at
/// each of the five moments the mechanic cares about. Opening this screen is
/// what marks them read and clears the badge — see
/// `MechanicHomeScreen._openNotifications`.
class MechanicNotificationsScreen extends StatelessWidget {
  const MechanicNotificationsScreen({super.key});

  IconData _iconFor(MechanicNotificationKind kind) {
    switch (kind) {
      case MechanicNotificationKind.quoteAccepted:
        return Icons.handshake_outlined;
      case MechanicNotificationKind.quoteRejected:
        return Icons.do_not_disturb_on_outlined;
      case MechanicNotificationKind.rated:
        return Icons.star_outline;
      case MechanicNotificationKind.paymentReceived:
        return Icons.payments_outlined;
      case MechanicNotificationKind.emergencyPosted:
        return Icons.warning_amber_rounded;
      case MechanicNotificationKind.accountApproved:
        return Icons.verified_outlined;
    }
  }

  Color _accentFor(MechanicNotificationKind kind) {
    switch (kind) {
      case MechanicNotificationKind.quoteAccepted:
        return AppColors.success;
      case MechanicNotificationKind.quoteRejected:
        return AppColors.error;
      case MechanicNotificationKind.rated:
        return AppColors.info;
      case MechanicNotificationKind.paymentReceived:
        return AppColors.warning;
      case MechanicNotificationKind.emergencyPosted:
        return AppColors.primary;
      case MechanicNotificationKind.accountApproved:
        return AppColors.success;
    }
  }

  String _formatWhen(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  /// Follows [notification] to what it is about, as the store decides from
  /// the job's current state.
  ///
  /// Screens of their own — an assigned job — are pushed from here, so Back
  /// returns to this list. Places inside the mechanic shell — a job card on
  /// the Jobs screen, the Earning or Profile tab — cannot be pushed; this
  /// screen closes and hands the route to the shell, which switches to it.
  void _open(BuildContext context, MechanicNotification notification) {
    final route = QuoteNotificationStore.instance.routeForMechanicNotification(
      notification,
      QuoteNotificationStore.currentMechanicName,
    );
    switch (route) {
      case OpenMechanicJob(:final requestId):
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MechanicActiveJobScreen(requestId: requestId)),
        );
      case OpenJobInList() || OpenMechanicTab():
        if (Navigator.of(context).canPop()) Navigator.pop(context, route);
      case NotificationUnavailable(:final message):
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message), duration: AppDurations.snackBar));
      case OpenJobQuotes() || OpenClientJob():
        // Client-side routes; never produced for a mechanic notification.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
      ),
      body: AnimatedBuilder(
        animation: MechanicNotificationStore.instance,
        builder: (context, _) {
          final notifications = MechanicNotificationStore.instance
              .notificationsFor(QuoteNotificationStore.currentMechanicName);

          if (notifications.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 48, color: AppColors.textdark.withValues(alpha: 0.55)),
                  const SizedBox(height: 12),
                  const Text(
                    'No notifications yet',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Accepted quotes, ratings, payments and emergency jobs will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
                  ),
                ],
              ),
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
                            n.detail,
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
