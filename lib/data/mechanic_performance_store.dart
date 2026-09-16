import 'package:flutter/foundation.dart';

import '../services/backend/mobile_backend.dart';
import '../services/local/record_box.dart';
import 'job_evaluation_store.dart';
import 'quote_store.dart';

/// How every job a mechanic took on ended — completed, dropped, or run out —
/// kept as events rather than read back off jobs, whose fields are reset when
/// they are cancelled or expire.
///
/// The raw record a mechanic's measurable performance, their rank and their
/// seasonal leaderboard score are all calculated from. Saved between launches.
class MechanicPerformanceStore extends ChangeNotifier {
  MechanicPerformanceStore._internal();
  static final MechanicPerformanceStore instance = MechanicPerformanceStore._internal();

  RecordWriter _writer = RecordWriter(const SharedPreferencesRecordBox('job_outcomes'));
  final List<JobOutcome> _outcomes = [];

  Future<void> load() async {
    final records = await _writer.box.load();
    final known = {for (final outcome in _outcomes) outcome.id};
    for (final json in records) {
      final outcome = JobOutcome.fromJson(json);
      if (outcome.id.isEmpty || known.contains(outcome.id)) continue;
      _outcomes.add(outcome);
    }
    notifyListeners();
  }

  List<JobOutcome> get all => List.unmodifiable(_outcomes);

  List<JobOutcome> outcomesFor(String mechanicId) =>
      _outcomes.where((outcome) => outcome.mechanicId == mechanicId).toList();

  /// [job], paid and complete, by [quote]'s mechanic. Once per job.
  void recordCompleted(HelpRequest job, MechanicQuote quote) {
    final at = job.paymentCompletedAt ?? DateTime.now();
    final id = JobOutcome.idFor(JobOutcomeKind.completed, job.id, quote.mechanicName, at);
    if (_outcomes.any((outcome) => outcome.id == id)) return;

    // On time means arriving by the ETA they promised. Without a recorded
    // arrival it cannot be told, and is left out rather than guessed.
    final due = expectedArrivalAt(job, quote);
    final arrived = job.arrivedAt;
    _add(JobOutcome(
      id: id,
      jobId: job.id,
      mechanicId: quote.mechanicName,
      kind: JobOutcomeKind.completed,
      at: at,
      clientId: job.clientName,
      urgency: job.urgency,
      payout: job.amountPaid,
      arrivedOnTime: due == null || arrived == null ? null : !arrived.isAfter(due),
    ));
  }

  /// [mechanicId] dropped [job], or let its window run out.
  void recordDropped(HelpRequest job, String mechanicId, JobOutcomeKind kind, {DateTime? now}) {
    assert(kind != JobOutcomeKind.completed);
    final at = now ?? DateTime.now();
    _add(JobOutcome(
      id: JobOutcome.idFor(kind, job.id, mechanicId, at),
      jobId: job.id,
      mechanicId: mechanicId,
      kind: kind,
      at: at,
      clientId: job.clientName,
      urgency: job.urgency,
    ));
  }

  /// [mechanicId]'s performance: their outcomes and the evaluations of their
  /// jobs.
  MechanicPerformance performanceFor(String mechanicId) => MechanicPerformance.from(
        outcomes: outcomesFor(mechanicId),
        evaluations: JobEvaluationStore.instance.countedForMechanic(mechanicId),
      );

  /// Stops every outcome of [jobId] counting — the job was invalidated. Kept,
  /// with the reason.
  void voidForJob(String jobId, String reason, {DateTime? now}) {
    var changed = false;
    for (var i = 0; i < _outcomes.length; i++) {
      if (_outcomes[i].jobId == jobId && _outcomes[i].counts) {
        _outcomes[i] = _outcomes[i].voided(reason, at: now ?? DateTime.now());
        changed = true;
      }
    }
    if (!changed) return;
    _save();
    notifyListeners();
  }

  void _add(JobOutcome outcome) {
    _outcomes.add(outcome);
    _save();
    notifyListeners();
  }

  void _save() => _writer.write([for (final outcome in _outcomes) outcome.toJson()]);

  @visibleForTesting
  void debugUse(RecordBox box) {
    _writer = RecordWriter(box);
    _outcomes.clear();
    notifyListeners();
  }

  @visibleForTesting
  Future<void> debugRestart() async {
    await _writer.idle;
    _outcomes.clear();
    await load();
  }
}
