import 'package:flutter/foundation.dart';

import '../services/backend/mobile_backend.dart';
import '../services/local/record_box.dart';
import 'app_session.dart';
import 'mechanic_notification_store.dart';
import 'quote_store.dart';

/// Why an evaluation was refused.
enum EvaluationRefusal {
  /// Not the Client UI.
  wrongRole,

  /// The job is not paid and complete, so there is nothing to evaluate.
  notEligible,

  /// The job belongs to someone else.
  notYours,

  /// It was already evaluated — one evaluation per job.
  alreadySubmitted,

  /// The job was invalidated after the fact.
  noLongerEligible,

  /// The submission itself is not valid.
  invalid,
}

class EvaluationException implements Exception {
  const EvaluationException(this.reason, this.message);

  final EvaluationRefusal reason;

  /// Safe to show as-is.
  final String message;

  @override
  String toString() => 'EvaluationException(${reason.name}): $message';
}

/// Every job evaluation on this device — the source of truth a mechanic's
/// rating, rank and seasonal score are calculated from.
///
/// One per job, created the moment a job is paid and complete (see
/// [requireFor]), and pending until the client submits it — across leaving the
/// screen and restarting the app, because it is saved, not held by a screen.
/// Submitted once, then locked: there is no edit.
///
/// Eligibility is checked here rather than trusted from a screen. When the jobs
/// domain moves to the On Go API, the server repeats every check; this is the
/// local version of it.
class JobEvaluationStore extends ChangeNotifier {
  JobEvaluationStore._internal();
  static final JobEvaluationStore instance = JobEvaluationStore._internal();

  RecordWriter _writer = RecordWriter(const SharedPreferencesRecordBox('job_evaluations'));
  final Map<String, JobEvaluation> _byJob = {};

  /// Reads what was saved. Safe to call before `runApp`.
  Future<void> load() async {
    final records = await _writer.box.load();
    for (final json in records) {
      final evaluation = JobEvaluation.fromJson(json);
      if (evaluation.jobId.isEmpty) continue;
      // Anything already in memory is newer than what was saved.
      _byJob.putIfAbsent(evaluation.jobId, () => evaluation);
    }
    notifyListeners();
  }

  List<JobEvaluation> get all => List.unmodifiable(_byJob.values);

  JobEvaluation? forJob(String jobId) => _byJob[jobId];

  /// A client's evaluations, most recent job first — which is also their
  /// completed-job history, since every paid job has one.
  List<JobEvaluation> forClient(String clientId) =>
      _byJob.values.where((e) => e.clientId == clientId).toList()
        ..sort((a, b) => b.requiredAt.compareTo(a.requiredAt));

  List<JobEvaluation> pendingForClient(String clientId) =>
      forClient(clientId).where((e) => e.evaluationRequired).toList();

  /// Evaluations that count toward [mechanicId]'s rating.
  List<JobEvaluation> countedForMechanic(String mechanicId) =>
      _byJob.values.where((e) => e.mechanicId == mechanicId && e.counts).toList();

  /// What [mechanicId] may see: newest first, never who wrote it.
  List<AnonymousEvaluation> anonymousForMechanic(String mechanicId) {
    final counted = countedForMechanic(mechanicId)
      ..sort((a, b) => (b.submittedAt ?? b.requiredAt).compareTo(a.submittedAt ?? a.requiredAt));
    return [for (final evaluation in counted) evaluation.anonymous];
  }

  /// [mechanicId]'s overall rating: every evaluation that counts.
  RatingSummary ratingFor(String mechanicId) =>
      RatingSummary.of([for (final e in countedForMechanic(mechanicId)) e.rating!]);

  /// Opens [job]'s evaluation, once the job is paid and complete. Returns the
  /// existing one if it already has one — never a second.
  JobEvaluation? requireFor(HelpRequest job, MechanicQuote? quote, {DateTime? now}) {
    if (quote == null || !job.paymentCompleted || job.status != RequestStatus.completed) return null;
    final existing = _byJob[job.id];
    if (existing != null) return existing;
    // A mechanic cannot evaluate their own work.
    if (job.clientName == quote.mechanicName) return null;

    final at = job.paymentCompletedAt ?? now ?? DateTime.now();
    final evaluation = JobEvaluation(
      jobId: job.id,
      clientId: job.clientName,
      mechanicId: quote.mechanicName,
      requiredAt: at,
      job: EvaluatedJobSummary(
        problem: job.problem,
        location: job.location,
        urgency: job.urgency,
        paidAt: at,
        amountPaid: job.amountPaid,
      ),
    );
    _byJob[job.id] = evaluation;
    _save();
    notifyListeners();
    return evaluation;
  }

  /// CLIENT-ONLY. Submits [clientId]'s evaluation of [jobId]. Throws
  /// [EvaluationException] saying why when it cannot be accepted.
  JobEvaluation submit({
    required String jobId,
    required String clientId,
    required EvaluationSubmission submission,
    String? clientAccountId,
    DateTime? now,
  }) {
    if (AppSession.instance.currentRole != AppRole.client) {
      throw const EvaluationException(EvaluationRefusal.wrongRole, 'Only a client can evaluate a job.');
    }
    final record = _byJob[jobId];
    if (record == null) {
      throw const EvaluationException(
        EvaluationRefusal.notEligible,
        'This job has nothing to evaluate yet — it has to be paid and completed first.',
      );
    }
    if (record.clientId != clientId || clientId == record.mechanicId) {
      throw const EvaluationException(EvaluationRefusal.notYours, 'You can only evaluate your own jobs.');
    }
    switch (record.status) {
      case EvaluationStatus.submitted:
        throw const EvaluationException(EvaluationRefusal.alreadySubmitted, 'This job has already been evaluated.');
      case EvaluationStatus.voided:
        throw const EvaluationException(EvaluationRefusal.noLongerEligible, 'This job can no longer be evaluated.');
      case EvaluationStatus.required:
        break;
    }
    final problem = submission.problem;
    if (problem != null) throw EvaluationException(EvaluationRefusal.invalid, problem);

    final updated = record.submitted(submission, at: now ?? DateTime.now(), clientAccountId: clientAccountId);
    _byJob[jobId] = updated;
    _save();

    // Anonymous: the mechanic hears there is a rating, never whose.
    final feedback = updated.feedback;
    MechanicNotificationStore.instance.add(
      kind: MechanicNotificationKind.rated,
      mechanicName: record.mechanicId,
      clientName: '',
      detail: '${submission.rating}★${feedback.isEmpty ? '' : ' · $feedback'}',
    );
    notifyListeners();
    return updated;
  }

  /// Stops [jobId]'s evaluation counting — the job was refunded or found to be
  /// fraudulent. Kept, with the reason. The admin and backend path; no client
  /// screen calls it.
  JobEvaluation? voidForJob(String jobId, String reason, {DateTime? now}) {
    final record = _byJob[jobId];
    if (record == null || record.status == EvaluationStatus.voided) return record;
    final voided = record.voided(reason, at: now ?? DateTime.now());
    _byJob[jobId] = voided;
    _save();
    notifyListeners();
    return voided;
  }

  void _save() => _writer.write([for (final evaluation in _byJob.values) evaluation.toJson()]);

  /// Test hook: keeps records in [box] from now on, starting empty.
  @visibleForTesting
  void debugUse(RecordBox box) {
    _writer = RecordWriter(box);
    _byJob.clear();
    notifyListeners();
  }

  /// Test hook: what a restart does — forget memory, read what was saved.
  @visibleForTesting
  Future<void> debugRestart() async {
    await _writer.idle;
    _byJob.clear();
    await load();
  }
}
