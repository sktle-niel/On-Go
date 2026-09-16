import 'package:on_go/data/job_evaluation_store.dart';
import 'package:on_go/data/leaderboard_store.dart';
import 'package:on_go/data/mechanic_performance_store.dart';
import 'package:on_go/data/point_transaction_store.dart';
import 'package:on_go/data/problem_report_store.dart';
import 'package:on_go/data/review_store.dart';
import 'package:on_go/services/local/record_box.dart';
import 'package:on_go_shared/on_go_shared.dart';

/// Empties every performance record and puts the leaderboard back to its
/// defaults — off, no seasons — so one test's jobs never rank up the next's.
void resetPerformanceStores() {
  ReviewStore.instance.debugUse(MemoryRecordBox());
  JobEvaluationStore.instance.debugUse(MemoryRecordBox());
  MechanicPerformanceStore.instance.debugUse(MemoryRecordBox());
  PointTransactionStore.instance.debugUse(MemoryRecordBox());
  ProblemReportStore.instance.debugUse(MemoryRecordBox());
  LeaderboardConfigStore.instance.debugSet(config: LeaderboardConfig.defaults, seasons: const []);
}
