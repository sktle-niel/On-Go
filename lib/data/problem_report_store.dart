import 'package:flutter/foundation.dart';

import '../services/backend/mobile_backend.dart';
import '../services/local/record_box.dart';
import 'app_session.dart';
import 'job_evaluation_store.dart';

class ProblemReportException implements Exception {
  const ProblemReportException(this.message);

  /// Safe to show as-is.
  final String message;

  @override
  String toString() => 'ProblemReportException: $message';
}

/// Problems clients report with a job — disputes, fraud, safety — kept apart
/// from ratings on purpose. A low rating says the service was poor; a report
/// says someone needs to look into what happened. Neither is inferred from
/// the other.
///
/// Saved between launches, for the dispute handling a backend will own.
class ProblemReportStore extends ChangeNotifier {
  ProblemReportStore._internal();
  static final ProblemReportStore instance = ProblemReportStore._internal();

  RecordWriter _writer = RecordWriter(const SharedPreferencesRecordBox('problem_reports'));
  final List<ProblemReport> _reports = [];

  Future<void> load() async {
    final known = {for (final report in _reports) report.id};
    for (final json in await _writer.box.load()) {
      final report = ProblemReport.fromJson(json);
      if (report.id.isEmpty || known.contains(report.id)) continue;
      _reports.add(report);
    }
    notifyListeners();
  }

  List<ProblemReport> get all => List.unmodifiable(_reports);

  List<ProblemReport> forJob(String jobId) => _reports.where((r) => r.jobId == jobId).toList();

  /// CLIENT-ONLY. Reports a problem with one of [clientId]'s paid jobs. Throws
  /// [ProblemReportException] saying why when it cannot be filed.
  ProblemReport report({
    required String jobId,
    required String clientId,
    required ProblemCategory category,
    required String description,
    DateTime? now,
  }) {
    if (AppSession.instance.currentRole != AppRole.client) {
      throw const ProblemReportException('Only a client can report a problem with a job.');
    }
    final evaluation = JobEvaluationStore.instance.forJob(jobId);
    if (evaluation == null) {
      throw const ProblemReportException('Problems can be reported once the job is paid.');
    }
    if (evaluation.clientId != clientId) {
      throw const ProblemReportException('You can only report problems with your own jobs.');
    }
    final text = description.trim();
    if (text.length < 10) throw const ProblemReportException('Describe the problem in a few words.');
    if (text.length > ProblemReport.maxDescriptionLength) {
      throw const ProblemReportException('Keep the description under ${ProblemReport.maxDescriptionLength} characters.');
    }
    if (forJob(jobId).any((r) => r.status != ProblemReportStatus.resolved)) {
      throw const ProblemReportException('You already have an open report for this job.');
    }

    final at = now ?? DateTime.now();
    final report = ProblemReport(
      id: 'report_${jobId}_${at.microsecondsSinceEpoch}',
      jobId: jobId,
      clientId: clientId,
      mechanicId: evaluation.mechanicId,
      category: category,
      description: text,
      createdAt: at,
    );
    _reports.add(report);
    _writer.write([for (final r in _reports) r.toJson()]);
    notifyListeners();
    return report;
  }

  @visibleForTesting
  void debugUse(RecordBox box) {
    _writer = RecordWriter(box);
    _reports.clear();
    notifyListeners();
  }
}
