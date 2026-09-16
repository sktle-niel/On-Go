import 'package:flutter/material.dart';

import '../data/job_evaluation_store.dart';
import '../data/problem_report_store.dart';
import '../data/review_store.dart';
import '../services/backend/mobile_backend.dart';
import '../theme/app_theme.dart';

/// The client this device evaluates and reports as — the same key its jobs are
/// recorded against.
String get _currentClient => ReviewStore.currentClientName;

/// Opens [jobId]'s evaluation and, once it is sent, thanks the client. Closing
/// it without sending leaves the evaluation pending. Returns whether it was sent.
Future<bool> evaluateJob(BuildContext context, String jobId) async {
  final evaluation = JobEvaluationStore.instance.forJob(jobId);
  if (evaluation == null || !evaluation.evaluationRequired) return false;
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _EvaluationSheet(evaluation: evaluation),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thanks — your evaluation was sent.'), duration: AppDurations.snackBar),
    );
  }
  return sent == true;
}

/// "How was your service?" — stars, a few tags, optional words. Quick on
/// purpose: a long form is one nobody finishes.
class _EvaluationSheet extends StatefulWidget {
  const _EvaluationSheet({required this.evaluation});

  final JobEvaluation evaluation;

  @override
  State<_EvaluationSheet> createState() => _EvaluationSheetState();
}

class _EvaluationSheetState extends State<_EvaluationSheet> {
  final _feedback = TextEditingController();
  final Set<EvaluationTag> _tags = {};
  int _rating = 0;
  String? _error;

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  /// Good service gets the good tags to choose from, poor service the bad ones.
  List<EvaluationTag> get _offeredTags => _rating >= 4 ? EvaluationTag.positives : EvaluationTag.negatives;

  void _submit() {
    try {
      JobEvaluationStore.instance.submit(
        jobId: widget.evaluation.jobId,
        clientId: _currentClient,
        submission: EvaluationSubmission(
          rating: _rating,
          tags: _tags.where(_offeredTags.contains).toSet(),
          feedback: _feedback.text,
        ),
      );
      Navigator.pop(context, true);
    } on EvaluationException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.textdark.withValues(alpha: 0.55);
    final evaluation = widget.evaluation;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: muted, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Text('How was your service?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textdark)),
              const SizedBox(height: 4),
              Text(
                '${evaluation.mechanicId} · ${evaluation.job.problem}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: muted),
              ),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var star = 1; star <= 5; star++)
                      IconButton(
                        tooltip: '$star star${star == 1 ? '' : 's'}',
                        icon: Icon(star <= _rating ? Icons.star : Icons.star_border, color: AppColors.warning, size: 36),
                        onPressed: () => setState(() {
                          _rating = star;
                          _error = null;
                        }),
                      ),
                  ],
                ),
              ),
              if (_rating > 0) ...[
                const SizedBox(height: 8),
                Text(_rating >= 4 ? 'What went well?' : 'What could have been better?',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in _offeredTags)
                      FilterChip(
                        label: Text(tag.label, style: const TextStyle(fontSize: 12)),
                        selected: _tags.contains(tag),
                        onSelected: (selected) => setState(() => selected ? _tags.add(tag) : _tags.remove(tag)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _feedback,
                maxLines: 3,
                maxLength: EvaluationSubmission.maxFeedbackLength,
                decoration: const InputDecoration(hintText: 'Anything to add? (optional)'),
              ),
              Text('The mechanic sees your rating and comments, not your name.',
                  style: TextStyle(fontSize: 11, color: muted)),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(fontSize: 12, color: AppColors.error)),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _rating == 0 ? null : _submit,
                  child: const Text('Submit evaluation'),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Flexible(
                    child: TextButton(
                      onPressed: () => reportProblem(context, evaluation),
                      child: const Text('Report a problem', overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Later'),
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

/// A reminder that stays on the client's home screen for as long as any
/// completed job still needs an evaluation. It never blocks the app.
class PendingEvaluationBanner extends StatelessWidget {
  const PendingEvaluationBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: JobEvaluationStore.instance,
      builder: (context, _) {
        final pending = JobEvaluationStore.instance.pendingForClient(_currentClient);
        if (pending.isEmpty) return const SizedBox.shrink();
        final count = pending.length;
        return Material(
          color: AppColors.warning.withValues(alpha: 0.14),
          child: InkWell(
            onTap: () => evaluateJob(context, pending.first.jobId),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  Icon(Icons.rate_review_outlined, color: AppColors.warning, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Evaluation Required',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textdark)),
                        Text(
                          count == 1
                              ? 'You have a completed job waiting for your evaluation.'
                              : 'You have $count completed jobs waiting for your evaluation.',
                          style: TextStyle(fontSize: 12, color: AppColors.textdark),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => evaluateJob(context, pending.first.jobId),
                    child: const Text('Evaluate'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Where a job's evaluation stands: "⚠ Evaluation Required" or "✓ Evaluated".
class EvaluationStatusLabel extends StatelessWidget {
  const EvaluationStatusLabel({super.key, required this.evaluation});

  final JobEvaluation evaluation;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (evaluation.status) {
      EvaluationStatus.required => ('⚠ Evaluation Required', AppColors.warning),
      EvaluationStatus.submitted => ('✓ Evaluated', AppColors.success),
      EvaluationStatus.voided => ('Evaluation closed', AppColors.textdark.withValues(alpha: 0.55)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

/// Opens "Report a problem" for [evaluation]'s job — for disputes and anything
/// someone needs to look into, separate from the rating.
Future<void> reportProblem(BuildContext context, JobEvaluation evaluation) async {
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => _ProblemReportDialog(evaluation: evaluation),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report submitted.'), duration: AppDurations.snackBar),
    );
  }
}

class _ProblemReportDialog extends StatefulWidget {
  const _ProblemReportDialog({required this.evaluation});

  final JobEvaluation evaluation;

  @override
  State<_ProblemReportDialog> createState() => _ProblemReportDialogState();
}

class _ProblemReportDialogState extends State<_ProblemReportDialog> {
  final _description = TextEditingController();
  ProblemCategory _category = ProblemCategory.other;
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  void _send() {
    try {
      ProblemReportStore.instance.report(
        jobId: widget.evaluation.jobId,
        clientId: _currentClient,
        category: _category,
        description: _description.text,
      );
      Navigator.pop(context, true);
    } on ProblemReportException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report a problem'),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'For something that needs looking into — separate from your rating.',
                style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ProblemCategory>(
                initialValue: _category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'What happened?'),
                items: [
                  for (final category in ProblemCategory.values)
                    DropdownMenuItem(value: category, child: Text(category.label, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (category) => setState(() => _category = category ?? _category),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                maxLines: 4,
                maxLength: ProblemReport.maxDescriptionLength,
                decoration: const InputDecoration(hintText: 'Describe the problem'),
              ),
              if (_error != null) Text(_error!, style: TextStyle(fontSize: 12, color: AppColors.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: _send, child: const Text('Send report')),
      ],
    );
  }
}
