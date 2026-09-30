import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../data/quote_store.dart'
    show QuoteNotificationStore, acceptedQuoteOf, buildPaymentQrData, formatEtaDuration, settledPaymentAmountOf;
import '../../../../services/backend/mobile_backend.dart';
import '../../../../services/location/location_service.dart';
import '../../../../theme/app_theme.dart';
import '../../../../utils/coalesced_load.dart';
import '../../../../widgets/chat_icon_button.dart';
import '../../../../widgets/common_widgets.dart';
import '../../../shared/job_chat_screen.dart';

/// The mechanic's job once they have it: heading out, the trip, the work, and
/// the payment code at the end.
///
/// The job is read through [MobileBackend.serviceRequests], and every step is
/// reported to it: the server in a normal build, the device's store in a local
/// one. The backend gates the order (work needs arrival, completion needs
/// work) and keeps the first time of a step reported twice; this screen shows
/// the job as the backend answered, never as it assumed.
class MechanicActiveJobScreen extends StatefulWidget {
  final String requestId;
  const MechanicActiveJobScreen({super.key, required this.requestId});

  @override
  State<MechanicActiveJobScreen> createState() => _MechanicActiveJobScreenState();
}

class _MechanicActiveJobScreenState extends State<MechanicActiveJobScreen>
    with CoalescedLoad<MechanicActiveJobScreen> {
  ServiceRequestApi get _api => MobileBackend.instance.serviceRequests;

  ServiceRequest? _request;
  JobQuote? _accepted;
  bool _loading = true;
  String? _error;
  StreamSubscription<ServiceRequest>? _watch;

  /// Steps sent and not answered yet. A button cannot send its step twice,
  /// and a burst of location fixes reports a step once.
  final _sending = <JobProgressStep>{};
  bool _savingAmount = false;

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
    _location.addListener(_onLocation);
    reload();
    // The job as others change it: the client paying, a cancel, the expiry
    // sweep taking it back to the pool.
    _watch = _api.watchRequests().where((request) => request.id == widget.requestId).listen((_) => reload());
  }

  @override
  void dispose() {
    _watch?.cancel();
    _location.removeListener(_onLocation);
    _stopTracking();
    super.dispose();
  }

  @override
  Future<void> read() async {
    try {
      final request = await _api.findRequest(widget.requestId);
      final quotes = request == null ? const <JobQuote>[] : await _api.listQuotes(request.id);
      if (!mounted) return;
      setState(() {
        _request = request;
        _accepted = acceptedQuoteOf(quotes);
        _loading = false;
        _error = null;
      });
      // A trip already under way when the screen opens is picked back up.
      if (request != null && request.navigating && !request.arrived) _startTracking(request);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: AppDurations.snackBar));
  }

  /// Reports [step] and shows the job as the backend answered. A refusal is
  /// told in the backend's own words, unless [quiet]: a step detected from
  /// location is tried again on the next fix rather than announced.
  Future<bool> _advance(JobProgressStep step, {bool quiet = false}) async {
    if (!_sending.add(step)) return false;
    setState(() {});
    try {
      final answer = await _api.advanceJob(widget.requestId, step);
      if (mounted) setState(() => _request = answer);
      return true;
    } on ApiException catch (error) {
      if (!quiet) _snack(error.message);
      return false;
    } finally {
      _sending.remove(step);
      if (mounted) setState(() {});
    }
  }

  void _openChat(ServiceRequest request) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => JobChatScreen(requestId: request.id, otherPartyName: request.clientName)),
      );

  /// How far the mechanic is from the client, from the latest location fix.
  /// A dash when either end is unknown, never a stand-in figure.
  String _distanceLabel(ServiceRequest request) {
    final here = _location.current;
    final client = request.point;
    if (here == null || client == null) return '—';
    final meters = here.point.distanceTo(client);
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  Future<void> _beginNavigating() async {
    if (!await _advance(JobProgressStep.navigating)) return;
    final request = _request;
    if (request != null) _startTracking(request);
  }

  /// Arrival, with En Route first if the trip never registered one.
  Future<void> _arrive({bool quiet = false}) async {
    final request = _request;
    if (request == null) return;
    if (!request.enRoute && !await _advance(JobProgressStep.enRoute, quiet: quiet)) return;
    if (await _advance(JobProgressStep.arrived, quiet: quiet)) _stopTracking();
  }

  Future<void> _startTracking(ServiceRequest request) async {
    if (_tracking) return;
    if (request.arrived) return;
    if (request.point == null) return;

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

    final request = _request;
    final update = _location.current;
    if (request == null || update == null || identical(update, _lastHandled)) return;
    final client = request.point;
    if (client == null) return;
    // A fix from before this job's tracking began says nothing about the trip.
    final since = _trackingSince;
    if (since != null && update.recordedAt.isBefore(since.subtract(const Duration(seconds: 5)))) return;

    _lastHandled = update;
    final distance = update.point.distanceTo(client);
    _initialDistance ??= distance;
    if (!request.enRoute && distance < _initialDistance! - _movementThresholdMeters) {
      _advance(JobProgressStep.enRoute, quiet: true);
    }
    if (!request.arrived && distance <= _arrivalRadiusMeters) {
      _arrive(quiet: true);
    }
    // The distance on the card moves with every fix.
    setState(() {});
  }

  Future<void> _setEmergencyPaymentAmount(ServiceRequest request) async {
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
    if (amount == null || !mounted) return;

    setState(() => _savingAmount = true);
    try {
      final answer = await _api.setAgreedAmount(widget.requestId, amount);
      if (mounted) setState(() => _request = answer);
    } on ApiException catch (error) {
      _snack(error.message);
    } finally {
      if (mounted) setState(() => _savingAmount = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Active Job'),
      ),
      body: Builder(
        builder: (context) {
          if (_loading) return const Center(child: CircularProgressIndicator());
          final error = _error;
          if (error != null) return _LoadFailed(message: error, onRetry: reload);

          final request = _request;
          // Matched is the job being worked; completed is a paid one, shown with
          // its receipt. Anything else, including a job back in the pool, is no
          // longer this mechanic's.
          if (request == null ||
              (request.status != ServiceRequestStatus.matched && request.status != ServiceRequestStatus.completed)) {
            return Center(child: Text('This job is no longer active.', style: TextStyle(color: AppColors.textdark.withValues(alpha: 0.55))));
          }
          final quote = _accepted;
          final eta = quote == null ? '—' : formatEtaDuration(Duration(minutes: quote.etaMinutes));

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
                        color: AppColors.info.withValues(alpha: 0.08),
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
                                      Text(request.urgency.label, style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55))),
                                    ],
                                  ),
                                ),
                                CircleIconButton(
                                  icon: Icons.call,
                                  color: AppColors.success,
                                  tooltip: 'Call ${request.clientName}',
                                  onTap: () => showContactSheet(
                                    context,
                                    name: request.clientName,
                                    // Clients' numbers aren't shared with
                                    // mechanics yet; the sheet offers the chat.
                                    phone: '',
                                    onMessage: () => _openChat(request),
                                  ),
                                ),
                                ChatIconButton(requestId: request.id, onTap: () => _openChat(request)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                              child: request.isEmergency
                                  ? Row(
                                      children: [
                                        _InfoColumn(label: 'ETA', value: eta),
                                        const _VerticalDivider(),
                                        _InfoColumn(label: 'Distance', value: _distanceLabel(request)),
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        _InfoColumn(label: 'ETA', value: eta),
                                        const _VerticalDivider(),
                                        _InfoColumn(label: 'Distance', value: _distanceLabel(request)),
                                        const _VerticalDivider(),
                                        _InfoColumn(
                                          label: 'Quote',
                                          value: quote == null ? '—' : formatPesos(quote.price),
                                          valueColor: AppColors.success,
                                        ),
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

  /// The one full-width button a step needs, greyed while its call is out.
  Widget _stepButton({
    required String label,
    required Color color,
    required VoidCallback? onPressed,
    IconData? icon,
  }) {
    final style = ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: AppColors.textlight,
      minimumSize: const Size(double.infinity, 46),
      shape: const StadiumBorder(),
    );
    return SizedBox(
      width: double.infinity,
      child: icon == null
          ? ElevatedButton(onPressed: onPressed, style: style, child: Text(label))
          : ElevatedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 18, color: AppColors.textlight),
              label: Text(label),
              style: style,
            ),
    );
  }

  Widget _buildAction(ServiceRequest request, JobQuote? quote) {
    if (request.paymentCompleted) {
      final amount = settledPaymentAmountOf(request, quote) ?? 0;
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
                'Payment received — ₱${amount.toStringAsFixed(0)}',
                style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    final mechanicName = request.mechanicName ?? quote?.mechanicName ?? QuoteNotificationStore.currentMechanicName;

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
              _stepButton(
                label: 'Set Payment Amount',
                color: AppColors.primary,
                onPressed: _savingAmount ? null : () => _setEmergencyPaymentAmount(request),
              ),
            ],
          );
        }

        final amount = request.agreedPaymentAmount!;
        final qrData = buildPaymentQrData(requestId: request.id, mechanicName: mechanicName, amount: amount);
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
            _PaymentCode(qrData: qrData),
            const SizedBox(height: 8),
            // Side by side where they fit; one under the other on a narrow
            // phone or at a large text size, rather than running off the edge.
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                _CopyCodeButton(qrData: qrData),
                TextButton.icon(
                  onPressed: _savingAmount ? null : () => _setEmergencyPaymentAmount(request),
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
      final amount = quote?.price ?? 0.0;
      final qrData = buildPaymentQrData(requestId: request.id, mechanicName: mechanicName, amount: amount);
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
          Text('Have the client scan this to pay ${quote == null ? '' : formatPesos(quote.price)}',
              style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55))),
          const SizedBox(height: 12),
          _PaymentCode(qrData: qrData),
          const SizedBox(height: 8),
          _CopyCodeButton(qrData: qrData),
        ],
      );
    }

    if (request.workStarted) {
      return _stepButton(
        label: 'Service Complete',
        color: AppColors.primary,
        onPressed: _sending.contains(JobProgressStep.completeService)
            ? null
            : () => _advance(JobProgressStep.completeService),
      );
    }

    if (request.arrived) {
      return _stepButton(
        label: 'Start Work',
        color: AppColors.success,
        onPressed: _sending.contains(JobProgressStep.startWork) ? null : () => _advance(JobProgressStep.startWork),
      );
    }

    if (request.navigating) {
      // Without the client's coordinates, or without a working location fix,
      // there is nothing to detect arrival from: the mechanic says so.
      if (request.point == null || _trackingError != null) {
        return _stepButton(
          label: 'Confirm Arrival',
          color: AppColors.success,
          onPressed: _sending.contains(JobProgressStep.arrived) || _sending.contains(JobProgressStep.enRoute)
              ? null
              : () => _arrive(),
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

    return _stepButton(
      label: 'Navigate',
      color: AppColors.success,
      icon: Icons.navigation_outlined,
      onPressed: _sending.contains(JobProgressStep.navigating) ? null : _beginNavigating,
    );
  }
}

/// The job could not be read. Says why, in the backend's words, and offers to
/// try again.
class _LoadFailed extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _LoadFailed({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 48, color: AppColors.textdark.withValues(alpha: 0.55)),
          const SizedBox(height: 12),
          const Text("Couldn't load this job", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55))),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

/// The payment code as text, for a client who pastes rather than scans.
class _PaymentCode extends StatelessWidget {
  final String qrData;

  const _PaymentCode({required this.qrData});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
      child: SelectableText(
        qrData,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55), fontFamily: 'monospace'),
      ),
    );
  }
}

class _CopyCodeButton extends StatelessWidget {
  final String qrData;

  const _CopyCodeButton({required this.qrData});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () {
        Clipboard.setData(ClipboardData(text: qrData));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment code copied'), duration: AppDurations.snackBar));
      },
      icon: const Icon(Icons.copy, size: 16),
      label: const Text('Copy Code'),
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
