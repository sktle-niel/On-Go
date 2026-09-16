import 'package:flutter/material.dart';
import '../../../../data/job_evaluation_store.dart';
import '../../../../data/problem_report_store.dart';
import '../../../../data/review_store.dart';
import '../../../../services/backend/mobile_backend.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/evaluation_widgets.dart';
import '../profile/mechanic_profile_view_screen.dart';

/// The client's completed jobs, each with where its evaluation stands:
/// "⚠ Evaluation Required" until it is sent, "✓ Evaluated" after.
///
/// Read from the job evaluations rather than the live job list — every paid job
/// has one, and unlike the jobs they are saved, so the history and its
/// evaluation states are the same after the app restarts.
class ServiceHistoryScreen extends StatefulWidget {
  const ServiceHistoryScreen({super.key});

  @override
  State<ServiceHistoryScreen> createState() => _ServiceHistoryScreenState();
}

class _ServiceHistoryScreenState extends State<ServiceHistoryScreen> {
  late final Listenable _sources = Listenable.merge([JobEvaluationStore.instance, ProblemReportStore.instance]);

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

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final history = JobEvaluationStore.instance.forClient(ReviewStore.currentClientName);

    return ListView(
      padding: context.layout.pageInsets,
      children: [
        const Text('Service History', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        if (history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Completed jobs will show up here once you\'ve paid a mechanic.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textdark.withValues(alpha: 0.55), fontSize: 13),
              ),
            ),
          )
        else
          ...history.map((evaluation) {
            final paid = evaluation.job.amountPaid;
            final reported = ProblemReportStore.instance
                .forJob(evaluation.jobId)
                .any((report) => report.status != ProblemReportStatus.resolved);
            return _HistoryCard(
              evaluation: evaluation,
              date: _formatDate(evaluation.job.paidAt),
              price: paid == null ? '—' : '₱${paid.toStringAsFixed(0)}',
              reported: reported,
            );
          }),
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final JobEvaluation evaluation;
  final String date;
  final String price;
  final bool reported;

  const _HistoryCard({
    required this.evaluation,
    required this.date,
    required this.price,
    required this.reported,
  });

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.textdark.withValues(alpha: 0.55);
    return InkWell(
      onTap: () => MechanicProfileViewScreen.open(context, evaluation.mechanicId),
      borderRadius: BorderRadius.circular(16),
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.55),
          border: Border.all(
            color: evaluation.evaluationRequired
                ? AppColors.warning.withValues(alpha: 0.6)
                : AppColors.textdark.withValues(alpha: 0.2),
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(evaluation.mechanicId, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(evaluation.job.problem,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textdark)),
                      Text(evaluation.job.location,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: muted)),
                      Text(date, style: TextStyle(fontSize: 12, color: muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(price, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.success)),
                    if (evaluation.rating != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star, size: 14, color: AppColors.warning),
                          const SizedBox(width: 2),
                          Text('${evaluation.rating}', style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Completed', style: TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w600)),
                ),
                EvaluationStatusLabel(evaluation: evaluation),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (evaluation.evaluationRequired)
                  TextButton(
                    onPressed: () => evaluateJob(context, evaluation.jobId),
                    child: const Text('Evaluate'),
                  ),
                if (reported)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('Problem reported', style: TextStyle(fontSize: 12, color: muted)),
                  )
                else
                  TextButton(
                    onPressed: () => reportProblem(context, evaluation),
                    child: const Text('Report a problem'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
