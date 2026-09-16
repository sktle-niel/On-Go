import '../models/job_quote.dart';
import '../models/service_request.dart';

/// The jobs domain: booking, quotes, the match, progress, payment and
/// cancellation, owned by the server so a client and a mechanic on two phones
/// see the same job.
///
/// Every rule that decides money or who may act lives on the server: priority
/// fees, completion deadlines, the ETA cancel lock, the expiry sweep, points.
/// A refusal arrives as an `ApiException`; a cancel refused under the ETA lock
/// carries `details.cancellableAt` with the moment it opens.
///
/// Live changes arrive on the event socket as `service_request.created`,
/// `service_request.updated`, `quote.submitted` and `quote.updated`.
abstract interface class ServiceRequestApi {
  /// Books help. Clients only, one active request per client.
  Future<ServiceRequest> bookRequest(NewServiceRequest request);

  /// Pending requests a mechanic can take, optionally of one [urgency].
  /// Mechanics and console roles only; a client is refused.
  Future<List<ServiceRequest>> listOpenRequests({JobUrgency? urgency});

  /// The caller's own requests (a client) or assigned jobs (a mechanic).
  Future<List<ServiceRequest>> listMyRequests({JobUrgency? urgency});

  /// One request, or null when it does not exist or is not the caller's to see.
  Future<ServiceRequest?> findRequest(String requestId);

  /// The client calls their request off: while pending, or while matched once
  /// the ETA lock has passed and before work starts. The app's "Delete".
  Future<ServiceRequest> cancelRequest(String requestId, {String? reason});

  /// The client puts a matched job back in the pool, under the same lock.
  /// The app's "Revert to Pending".
  Future<ServiceRequest> reopenRequest(String requestId);

  /// The assigned mechanic backs out before any progress step and tells the
  /// client why. Not for an Emergency. The app's "Cancel Job".
  Future<ServiceRequest> mechanicCancelJob(String requestId, {required String reason});

  /// An approved mechanic quotes a pending Normal or Urgent request.
  Future<JobQuote> submitQuote(String requestId, QuoteSubmission quote);

  /// The quotes on a request, for its client, mechanics and the console.
  Future<List<JobQuote>> listQuotes(String requestId);

  /// The mechanic withdraws their own live quote.
  Future<JobQuote> withdrawQuote(String requestId);

  /// The client turns a quote down. That mechanic cannot quote the request
  /// again.
  Future<JobQuote> rejectQuote(String requestId, String quoteId);

  /// The client accepts a live quote, which matches the job. When two accepts
  /// race, exactly one wins.
  Future<ServiceRequest> acceptQuote(String requestId, String quoteId);

  /// An approved mechanic takes a pending Emergency, first come. The price is
  /// agreed in person and recorded with [setAgreedAmount].
  Future<ServiceRequest> acceptEmergency(String requestId, {required int etaMinutes});

  /// The assigned mechanic reports a progress step.
  Future<ServiceRequest> advanceJob(String requestId, JobProgressStep step);

  /// Emergency only: the assigned mechanic records the price agreed in person,
  /// until the job is paid.
  Future<ServiceRequest> setAgreedAmount(String requestId, double amount);

  /// The client pays for a finished job, which closes it. The server settles
  /// the price, the priority fee and the points; read them off the answer.
  Future<ServiceRequest> payForJob(
    String requestId, {
    JobPaymentRequest payment = const JobPaymentRequest(),
  });

  /// Requests the caller may see, as they change.
  Stream<ServiceRequest> watchRequests();

  /// Quotes the caller may see, as they arrive or change.
  Stream<JobQuote> watchQuotes();
}
