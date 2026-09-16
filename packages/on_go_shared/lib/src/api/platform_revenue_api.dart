import '../models/platform_revenue.dart';

/// Platform revenue: written by the mobile app, read by the console.
///
/// The asymmetry is the point. A client's phone can report that a payment
/// completed; only the console ever reads the ledger back. Once the backend
/// exists it is what actually books the money — the phone reports, it decides.
abstract interface class PlatformRevenueApi {
  /// Books ONE completed client payment. Mobile → console.
  ///
  /// Idempotent on [CompletedPaymentReport.requestId]: a job can only be paid
  /// once, so a retry must never double-count.
  ///
  /// A job the server holds is paid through `ServiceRequestApi.payForJob`,
  /// which settles its revenue; reporting it books nothing. This call remains
  /// for jobs a phone settled on its own.
  Future<void> reportCompletedPayment(CompletedPaymentReport payment);

  /// The whole ledger, for the Admin Overview and Income screens.
  Future<PlatformRevenueSummary> fetchSummary();

  /// A live view of the ledger.
  Stream<PlatformRevenueSummary> watchSummary();
}
