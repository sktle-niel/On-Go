import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_go_shared/on_go_shared.dart';

import '../../../../services/location/location_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/chat_icon_button.dart';
import '../../../../widgets/common_widgets.dart';
import '../../../../data/quote_store.dart';
import '../../../shared/job_chat_screen.dart';

class MechanicActiveJobScreen extends StatefulWidget {
  final String requestId;
  const MechanicActiveJobScreen({super.key, required this.requestId});

  @override
  State<MechanicActiveJobScreen> createState() => _MechanicActiveJobScreenState();
}

class _MechanicActiveJobScreenState extends State<MechanicActiveJobScreen> {
  final _store = QuoteNotificationStore.instance;

  // Arrival detection reads the shared LocationService rather than GPS
  // directly: one set of permission, services and error handling for the
  // whole app, and live updates that pause when the app is in the background.
  final _location = LocationService.instance;
  bool _tracking = false;
  DateTime? _trackingSince;
  LocationUpdate? _lastHandled;
  double? _initialDistance;
  String? _trackingError;

  static const _arrivalRadiusMeters = 100.0;
  static const _movementThresholdMeters = 20.0;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChange);
    _location.addListener(_onLocation);
    final request = _store.requestFor(widget.requestId);
    if (request != null && request.navigating) {
      _startTracking(request);
    }
  }

  @override
  void dispose() {
    _store.removeListener(_onChange);
    _location.removeListener(_onLocation);
    _stopTracking();
    super.dispose();
  }

  void _onChange() => setState(() {});

  void _beginNavigating(HelpRequest request) {
    _store.mechanicStartNavigating(request.id);
    _startTracking(request);
  }

  Future<void> _startTracking(HelpRequest request) async {
    if (_tracking) return;
    if (request.arrived) return;
    if (!request.hasClientCoordinates) return;

    // Heading to a job is a moment the mechanic plainly needs location, so a
    // prompt here is warranted — the service only shows one if asking can
    // still change anything.
    final access = await _location.requestAccess();
    if (!mounted) return;
    if (access != LocationAccess.granted) {
      setState(() => _trackingError = access == LocationAccess.servicesDisabled
          ? 'Location services are off — arrival must be confirmed manually.'
          : 'Location permission denied — arrival must be confirmed manually.');
      return;
    }

    _tracking = true;
    _trackingSince = DateTime.now();
    final live = await _location.startTracking();
    if (!mounted) return;
    setState(() => _trackingError =
        live ? null : 'Could not start location tracking — arrival must be confirmed manually.');
    _onLocation();
  }

  void _stopTracking() {
    if (!_tracking) return;
    _tracking = false;
    _location.stopTracking();
  }

  void _onLocation() {
    if (!_tracking || !mounted) return;

    // Tracking stopped underneath us — services switched off, GPS lost.
    if (!_location.isTracking && _location.failure != null) {
      setState(() => _trackingError = '${_location.failure!.message} Arrival must be confirmed manually.');
      return;
    }

    final request = _store.requestFor(widget.requestId);
    final update = _location.current;
    if (request == null || update == null || identical(update, _lastHandled)) return;
    if (!request.hasClientCoordinates) return;
    // A fix from before this job's tracking began says nothing about the trip.
    final since = _trackingSince;
    if (since != null && update.recordedAt.isBefore(since.subtract(const Duration(seconds: 5)))) return;

    _lastHandled = update;
    _handlePosition(request, update.point);
  }

  void _handlePosition(HelpRequest request, GeoPoint position) {
    final distance = position.distanceTo(GeoPoint(request.clientLat!, request.clientLng!));
    _initialDistance ??= distance;

    if (!request.enRoute && distance < _initialDistance! - _movementThresholdMeters) {
      _store.mechanicMarkEnRoute(request.id);
    }
    if (!request.arrived && distance <= _arrivalRadiusMeters) {
      _store.mechanicMarkArrived(request.id);
      _stopTracking();
    }
  }

  void _confirmArrivalManually(HelpRequest request) {
    if (!request.enRoute) _store.mechanicMarkEnRoute(request.id);
    _store.mechanicMarkArrived(request.id);
  }

  Future<void> _setEmergencyPaymentAmount(HelpRequest request) async {
    final controller = TextEditingController(
      text: request.agreedPaymentAmount != null ? request.agreedPaymentAmount!.toStringAsFixed(0) : '',
    );

    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(request.agreedPaymentAmount == null ? 'Set Payment Amount' : 'Update Payment Amount'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Emergency jobs have no fixed quote — enter the price you and the client agreed on.',
              style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(prefixText: '₱ ', hintText: '0'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value == null || value <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Enter a valid amount.'), duration: AppDurations.snackBar));
                return;
              }
              Navigator.pop(ctx, value);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (amount == null) return;

    _store.mechanicSetPaymentAmount(request.id, amount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textmedium,
        title: const Text('Active Job'),
      ),
      body: Builder(
        builder: (context) {
          final request = _store.requestFor(widget.requestId);
          if (request == null) {
            return Center(child: Text('This job is no longer active.', style: TextStyle(color: AppColors.textdark.withValues(alpha: 0.55))));
          }
          final quote = _store.acceptedQuoteFor(widget.requestId);

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: context.layout.panelHeight(190),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.info.withValues(alpha: 0.22), AppColors.info.withValues(alpha: 0.08)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.location_on_outlined, color: AppColors.primary, size: 40),
                          const SizedBox(height: 8),
                          Text(
                            request.arrived
                                ? "You've arrived"
                                : (request.navigating ? 'Heading to client' : 'Ready to head out'),
                            style: TextStyle(color: AppColors.textdark, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          if (_trackingError != null) ...[
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(_trackingError!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppColors.textdark.withValues(alpha: 0.7), fontSize: 11)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: -46,
                      child: AppCard(
                        color: AppColors.surface,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: AppColors.background,
                                  child: Icon(Icons.person, color: AppColors.textdark.withValues(alpha: 0.55)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(request.clientName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                      Text(request.urgency, style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55))),
                                    ],
                                  ),
                                ),
                                _CircleIconButton(icon: Icons.call, color: AppColors.success, onTap: () {}),
                                const SizedBox(width: 8),
                                ChatIconButton(
                                  requestId: request.id,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => JobChatScreen(requestId: request.id, otherPartyName: request.clientName)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                              child: request.isEmergency
                                  ? Row(
                                      children: [
                                        _InfoColumn(label: 'ETA', value: quote?.eta ?? '15 mins'),
                                        const _VerticalDivider(),
                                        const _InfoColumn(label: 'Distance', value: '20 km'),
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        _InfoColumn(label: 'ETA', value: quote?.eta ?? '20 mins'),
                                        const _VerticalDivider(),
                                        const _InfoColumn(label: 'Distance', value: '20 km'),
                                        const _VerticalDivider(),
                                        _InfoColumn(label: 'Quote', value: quote?.price ?? '—', valueColor: AppColors.success),
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 62, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Service Status', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      if (request.isEmergency) ...[
                        _StatusStep(title: 'Navigate', done: request.navigating, isFirst: true),
                        _StatusStep(title: 'Mechanic En Route', done: request.enRoute),
                        _StatusStep(title: 'Mechanic Arrived', done: request.arrived),
                        _StatusStep(title: 'Work in Progress', done: request.workStarted),
                        _StatusStep(title: 'Service Complete', done: request.serviceCompleted),
                        _StatusStep(title: 'Payment Complete', done: request.paymentCompleted, isLast: true),
                      ] else ...[
                        const _StatusStep(title: 'Request Accepted', done: true, isFirst: true),
                        _StatusStep(title: 'Navigating', done: request.navigating),
                        _StatusStep(title: 'Mechanic En Route', done: request.enRoute),
                        _StatusStep(title: 'Mechanic Arrived', done: request.arrived),
                        _StatusStep(title: 'Work in Progress', done: request.workStarted),
                        _StatusStep(title: 'Service Complete', done: request.serviceCompleted),
                        _StatusStep(title: 'Payment Complete', done: request.paymentCompleted, isLast: true),
                      ],
                      const SizedBox(height: 16),
                      _buildAction(request, quote),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAction(HelpRequest request, MechanicQuote? quote) {
    if (request.paymentCompleted) {
      final amount = effectivePaymentAmount(request, quote) ?? 0;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.success),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Payment received — ₱${amount.toStringAsFixed(0)} · +${request.pointsAwarded ?? 0} points',
                style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    if (request.serviceCompleted) {
      // ── Emergency: negotiated price, must be set before any code exists ──
      if (request.isEmergency) {
        if (request.agreedPaymentAmount == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  'Emergency jobs have no set price. Agree on a price with the client, then set it here to generate a payment code.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _setEmergencyPaymentAmount(request),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textlight,
                  minimumSize: const Size(double.infinity, 46),
                  shape: const StadiumBorder(),
                ),
                child: const Text('Set Payment Amount'),
              ),
            ],
          );
        }

        final amount = request.agreedPaymentAmount!;
        final qrData = buildPaymentQrData(
          requestId: request.id,
          mechanicName: quote?.mechanicName ?? QuoteNotificationStore.currentMechanicName,
          amount: amount,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
              child: Text('Waiting for Client Payment',
                  textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.warning)),
            ),
            const SizedBox(height: 8),
            Text('Agreed price: ₱${amount.toStringAsFixed(0)}',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.success)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.textlight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(data: qrData, size: 200),
            ),
            const SizedBox(height: 10),
            Text('Have the client scan this to pay ₱${amount.toStringAsFixed(0)}',
                style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55))),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
              child: SelectableText(
                qrData,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55), fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: qrData));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment code copied'), duration: AppDurations.snackBar));
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy Code'),
                ),
                TextButton.icon(
                  onPressed: () => _setEmergencyPaymentAmount(request),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit Amount'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'If the client disagrees with this price, tap Edit Amount to agree on a new one.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55)),
            ),
          ],
        );
      }

      // ── Normal/Urgent: fixed quote price, no negotiation, no set step ──
      final amount = quote != null ? parsePesoAmount(quote.price) : 0.0;
      final qrData = buildPaymentQrData(
        requestId: request.id,
        mechanicName: quote?.mechanicName ?? QuoteNotificationStore.currentMechanicName,
        amount: amount,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: Text('Waiting for Client Payment',
                textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.warning)),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.textlight,
              border: Border.all(color: AppColors.textdark.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(data: qrData, size: 200),
          ),
          const SizedBox(height: 10),
          Text('Have the client scan this to pay ${quote?.price ?? ''}',
              style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55))),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
            child: SelectableText(
              qrData,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55), fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: qrData));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment code copied'), duration: AppDurations.snackBar));
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Code'),
          ),
        ],
      );
    }

    if (request.workStarted) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => _store.mechanicCompleteService(request.id),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textlight,
            minimumSize: const Size(double.infinity, 46),
            shape: const StadiumBorder(),
          ),
          child: const Text('Service Complete'),
        ),
      );
    }

    if (request.arrived) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => _store.mechanicStartWork(request.id),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: AppColors.textlight,
            minimumSize: const Size(double.infinity, 46),
            shape: const StadiumBorder(),
          ),
          child: const Text('Start Work'),
        ),
      );
    }

    if (request.navigating) {
      if (!request.hasClientCoordinates) {
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _confirmArrivalManually(request),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: AppColors.textlight,
              minimumSize: const Size(double.infinity, 46),
              shape: const StadiumBorder(),
            ),
            child: const Text('Confirm Arrival'),
          ),
        );
      }
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
        child: Text(
          'Tracking your location — En Route and Arrived will be detected automatically as you travel.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textdark.withValues(alpha: 0.55), fontSize: 12),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _beginNavigating(request),
        icon: Icon(Icons.navigation_outlined, size: 18, color: AppColors.textlight),
        label: const Text('Navigate'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.success,
          foregroundColor: AppColors.textlight,
          minimumSize: const Size(double.infinity, 46),
          shape: const StadiumBorder(),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CircleIconButton({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 28, color: AppColors.textdark.withValues(alpha: 0.2));
  }
}

class _InfoColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoColumn({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55))),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: valueColor ?? AppColors.textdark)),
        ],
      ),
    );
  }
}

class _StatusStep extends StatelessWidget {
  final String title;
  final bool done;
  final bool isFirst;
  final bool isLast;

  const _StatusStep({
    required this.title,
    required this.done,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.success : AppColors.textdark.withValues(alpha: 0.2);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, color: color, size: 20),
              if (!isLast)
                Expanded(child: Container(width: 2, color: color.withValues(alpha: 0.4))),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(title,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: done ? AppColors.textdark : AppColors.textdark.withValues(alpha: 0.55))),
            ),
          ),
        ],
      ),
    );
  }
}