import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../theme/app_theme.dart';
// Todo: adjust this path to wherever quote_store.dart lives in your project
import '../../../../data/quote_store.dart';

/// What the mechanic entered on the quote form. Returned by [SendQuoteSheet]
/// so the caller can turn it into a real [MechanicQuote] via
/// `QuoteNotificationStore.instance.mechanicSendQuote(...)`.
class QuoteInput {
  final double labor;
  final double parts;
  final double travel;

  /// How long the mechanic committed to being at the client's location, as a
  /// real duration — the client's job details count down against it.
  final Duration eta;

  const QuoteInput({
    required this.labor,
    required this.parts,
    required this.travel,
    required this.eta,
  });

  double get total => labor + parts + travel;
}

class SendQuoteSheet extends StatefulWidget {
  final HelpRequest request;
  const SendQuoteSheet({super.key, required this.request});

  @override
  State<SendQuoteSheet> createState() => _SendQuoteSheetState();
}

class _SendQuoteSheetState extends State<SendQuoteSheet> {
  final _laborCtrl = TextEditingController(text: '100');
  final _partsCtrl = TextEditingController(text: '100');
  final _travelCtrl = TextEditingController(text: '100');

  /// The ETA is a number plus a unit rather than free text, so "1 hour" can't
  /// be typed as "1hr", "an hour" or anything else the app then has to guess
  /// at — the client's arrival countdown runs off this value.
  final _etaValueCtrl = TextEditingController(text: '1');
  EtaUnit _etaUnit = EtaUnit.hours;

  int get _etaValue => int.tryParse(_etaValueCtrl.text.trim()) ?? 0;
  Duration get _eta => _etaUnit.toDuration(_etaValue);
  bool get _etaIsValid => _etaValue > 0;

  /// The ceiling this job's urgency puts on the ETA — null for a Normal job,
  /// which has no completion deadline of its own and so allows any arrival
  /// time the mechanic is willing to commit to.
  Duration? get _maxEta => maxEtaFor(widget.request);

  /// Why the ETA as entered can't be sent, or null when it can. Covers both
  /// "nothing entered" and "longer than the job's completion window", so one
  /// line under the field always says what is wrong.
  String? get _etaProblem {
    if (!_etaIsValid) return 'Enter how long it will take you to reach the client.';
    return etaTooLongReason(widget.request, _eta);
  }

  /// The ETA is entered but overruns the job's completion window — the state
  /// the field itself has to flag.
  bool get _etaTooLong => _etaIsValid && etaTooLongReason(widget.request, _eta) != null;

  double get _total {
    final labor = double.tryParse(_laborCtrl.text) ?? 0;
    final parts = double.tryParse(_partsCtrl.text) ?? 0;
    final travel = double.tryParse(_travelCtrl.text) ?? 0;
    return labor + parts + travel;
  }

  @override
  void dispose() {
    _laborCtrl.dispose();
    _partsCtrl.dispose();
    _travelCtrl.dispose();
    _etaValueCtrl.dispose();
    super.dispose();
  }

  /// Confirms the ETA in plain words before the quote goes out. The mechanic
  /// is agreeing to be somewhere by a time, not filing an estimate, so the
  /// commitment is spelled out with their own number in it.
  Future<void> _send() async {
    // The button is disabled while [_etaProblem] has anything to say, and the
    // reason is already on screen under the field — this only guards the path.
    if (_etaProblem != null) return;

    final etaLabel = formatEtaDuration(_eta);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm your ETA'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are promising to arrive at ${widget.request.clientName}\'s location '
              'within $etaLabel of them accepting your quote.',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(
              'The countdown starts the moment your quote is accepted, and the client '
              'is notified if $etaLabel passes before you arrive.',
              style: TextStyle(fontSize: 13, color: AppColors.textmedium),
            ),
            const SizedBox(height: 10),
            Text(
              'The job is held for you while you are within $etaLabel — the client cannot '
              'cancel during that time. Once $etaLabel is up and you still are not there, '
              'they are free to cancel at any time.',
              style: TextStyle(fontSize: 13, color: AppColors.textmedium),
            ),
            const SizedBox(height: 10),
            // Which clock this job is on. The two urgencies with a completion
            // window are the ones whose ETA had to fit inside it; a Normal job
            // has no window, so the ETA is the whole of what was promised.
            Text(
              _maxEta != null
                  ? 'This ${widget.request.urgency} job also has to be COMPLETED within '
                      '${formatEtaDuration(widget.request.completionWindow!)} of being accepted. '
                      'Arriving in $etaLabel leaves you the rest of that window to do the work.'
                  : 'This job has no fixed completion deadline — the $etaLabel you set is the '
                      'only timing the client is promised.',
              style: TextStyle(fontSize: 13, color: AppColors.textmedium),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Change ETA')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send Quote'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    Navigator.pop(
      context,
      QuoteInput(
        labor: double.tryParse(_laborCtrl.text) ?? 0,
        parts: double.tryParse(_partsCtrl.text) ?? 0,
        travel: double.tryParse(_travelCtrl.text) ?? 0,
        eta: _eta,
      ),
    );
  }

  /// The same field styling [_QuoteField] uses, for the two ETA controls.
  /// [error] outlines both of them when the ETA overruns the job's window, so
  /// the number and the unit are flagged together — either one can be the part
  /// that needs changing.
  InputDecoration _etaDecoration({String? hint, bool error = false}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: error ? AppColors.error : AppColors.textmedium.withValues(alpha: 0.55),
        width: error ? 1.5 : 1,
      ),
    );
    return InputDecoration(
      filled: true,
      fillColor: AppColors.surface.withValues(alpha: 0.55),
      hintText: hint,
      isDense: true,
      border: border,
      enabledBorder: border,
      focusedBorder: border,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        // Clears the gesture bar on phones that have one.
        padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + MediaQuery.paddingOf(context).bottom),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: AppColors.primary, width: 1.5)),
        ),
        // Scrolls rather than overflows. The form is tall enough that a short
        // phone — or any phone with the keyboard up, which is most of the time
        // the mechanic is filling this in — leaves less room than it needs.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Send a Quote — ${widget.request.clientName}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
              const SizedBox(height: 16),
              _QuoteField(label: 'Labor Fee', controller: _laborCtrl, onChanged: (_) => setState(() {})),
              const SizedBox(height: 14),
              _QuoteField(label: 'Parts Needed', controller: _partsCtrl, onChanged: (_) => setState(() {})),
              const SizedBox(height: 14),
              _QuoteField(label: 'Travel Fee', controller: _travelCtrl, onChanged: (_) => setState(() {})),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  Text('₱${_total.toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Arrival Time (ETA)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              // What this job's urgency allows, said before they type rather
              // than after they get it wrong.
              Text(
                _maxEta != null
                    ? '${widget.request.urgency} job — must be completed within '
                        '${formatEtaDuration(widget.request.completionWindow!)}, so your ETA cannot '
                        'be longer than ${formatEtaDuration(_maxEta!)}.'
                    : 'Normal job — no fixed completion deadline. The ETA you set is the timing '
                        'the client is promised.',
                style: TextStyle(fontSize: 11, color: AppColors.textmedium, height: 1.3),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Just the number — no units typed by hand.
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _etaValueCtrl,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      // A whole number of minutes, hours or days.
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                      onChanged: (_) => setState(() {}),
                      decoration: _etaDecoration(hint: 'e.g. 1', error: _etaTooLong),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<EtaUnit>(
                      initialValue: _etaUnit,
                      decoration: _etaDecoration(error: _etaTooLong),
                      items: EtaUnit.values
                          .map((unit) => DropdownMenuItem(
                                value: unit,
                                child: Text(unit.labelFor(_etaValue)),
                              ))
                          .toList(),
                      onChanged: (unit) => setState(() => _etaUnit = unit ?? _etaUnit),
                    ),
                  ),
                ],
              ),
              // An ETA past the job's completion window is refused here, at the
              // field, rather than after the quote has gone out.
              if (_etaTooLong) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 14, color: AppColors.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        etaTooLongReason(widget.request, _eta)!,
                        style: TextStyle(fontSize: 12, color: AppColors.error, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              // The ETA is a commitment, so say what it commits them to — with
              // their own figure in it — right where they set it.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.schedule, size: 16, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _etaIsValid
                            ? 'Set your ETA carefully. '
                                'You are expected to arrive within ${formatEtaDuration(_eta)}. '
                                'The client cannot cancel while your ETA is active. '
                                'If you have not arrived within ${formatEtaDuration(_eta)}, the client can cancel the job. '
  
                            : 'Enter your expected arrival time. '
                                'The client will be notified if you have not arrived when the ETA expires and can cancel the job after that.',
                        style: TextStyle(fontSize: 12, color: AppColors.warning, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Cancel first and Send Quote last, the order every dialog in
              // the app uses, so the commitment sits under the thumb.
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, null),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textmedium,
                        backgroundColor: AppColors.surface.withValues(alpha: 0.55),
                        side: BorderSide(color: AppColors.textmedium.withValues(alpha: 0.55)),
                        minimumSize: const Size(double.infinity, 48),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      // Off while the ETA is blank or longer than the job allows;
                      // the line under the field says which.
                      onPressed: _etaProblem == null ? _send : null,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Send Quote'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuoteField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  const _QuoteField({
    required this.label,
    required this.controller,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          // Pesos: digits and a decimal point, nothing else.
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surface.withValues(alpha: 0.55),
            prefixText: '₱ ',
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.textmedium.withValues(alpha: 0.55)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.textmedium.withValues(alpha: 0.55)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}