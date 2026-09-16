import 'dart:async';

import 'package:on_go_shared/on_go_shared.dart';

import 'api_client.dart';
import 'event_socket.dart';

/// [ServiceRequestApi] over `/api/v1/service-requests`. Live.
///
/// The jobs domain is the one place where the server, not the phone, is the
/// authority: it sets the priority fee from the urgency, stamps the completion
/// deadline when a job is matched, caps a quoted ETA to what is left of that
/// window, holds the job under the ETA cancel lock, sweeps overdue jobs back
/// into the pool, and settles the money. This class sends the call and reads
/// back the request the server wrote; it computes nothing of its own.
///
/// Every method answers the updated [ServiceRequest] (or [JobQuote]), so a
/// caller never has to re-fetch to see what its own call did.
///
/// Refusals arrive as an [ApiException] carrying the server's code:
///
/// * `conflict` — the job moved on: already matched, already paid, the wrong
///   step for the status machine, or a cancel that the ETA lock still refuses.
///   A cancel refused under the lock carries `details.cancellableAt`, the
///   moment it opens.
/// * `not_found` — not there, or not the caller's to see. The server answers
///   404 rather than 403 for someone else's job on purpose, so probing an id
///   tells you nothing.
/// * `forbidden` — the wrong role for the call. A client asking for the open
///   pool is the one to expect; the server records the attempt.
class HttpServiceRequestApi implements ServiceRequestApi {
  HttpServiceRequestApi(this._client, {EventSocket? events}) : _events = events;

  final ApiClient _client;
  final EventSocket? _events;

  // ─── Booking and reading ──────────────────────────────────────────────

  @override
  Future<ServiceRequest> bookRequest(NewServiceRequest request) async =>
      _request(await _client.post(
        ApiEndpoints.serviceRequests,
        body: request.toJson(),
        authenticated: true,
      ));

  /// Mechanics and console roles only — a client is refused with `forbidden`,
  /// because the pool carries other clients' names and coordinates.
  @override
  Future<List<ServiceRequest>> listOpenRequests({JobUrgency? urgency}) =>
      _list(scope: 'open', urgency: urgency);

  @override
  Future<List<ServiceRequest>> listMyRequests({JobUrgency? urgency}) =>
      _list(scope: 'mine', urgency: urgency);

  Future<List<ServiceRequest>> _list({required String scope, JobUrgency? urgency}) async {
    final answer = await _client.get(
      ApiEndpoints.serviceRequests,
      query: {
        'scope': scope,
        if (urgency != null) 'urgency': urgency.wireName,
      },
      authenticated: true,
    );
    return [for (final json in responseList(answer)) ServiceRequest.fromJson(json)];
  }

  /// Null for a request that does not exist *or* is not the caller's to see —
  /// the server does not distinguish the two, and neither should a caller.
  @override
  Future<ServiceRequest?> findRequest(String requestId) async {
    try {
      return _request(await _client.get(
        ApiEndpoints.serviceRequest(requestId),
        authenticated: true,
      ));
    } on ApiException catch (error) {
      if (error.code == ApiErrorCodes.notFound) return null;
      rethrow;
    }
  }

  // ─── Calling a job off ────────────────────────────────────────────────

  @override
  Future<ServiceRequest> cancelRequest(String requestId, {String? reason}) async =>
      _request(await _client.post(
        ApiEndpoints.serviceRequestCancel(requestId),
        body: {if (reason != null) 'reason': reason},
        authenticated: true,
      ));

  @override
  Future<ServiceRequest> reopenRequest(String requestId) async => _request(await _client.post(
        ApiEndpoints.serviceRequestReopen(requestId),
        authenticated: true,
      ));

  @override
  Future<ServiceRequest> mechanicCancelJob(String requestId, {required String reason}) async =>
      _request(await _client.post(
        ApiEndpoints.serviceRequestMechanicCancel(requestId),
        body: {'reason': reason},
        authenticated: true,
      ));

  // ─── Quotes ───────────────────────────────────────────────────────────

  @override
  Future<JobQuote> submitQuote(String requestId, QuoteSubmission quote) async =>
      _quote(await _client.post(
        ApiEndpoints.serviceRequestQuotes(requestId),
        body: quote.toJson(),
        authenticated: true,
      ));

  @override
  Future<List<JobQuote>> listQuotes(String requestId) async {
    final answer = await _client.get(
      ApiEndpoints.serviceRequestQuotes(requestId),
      authenticated: true,
    );
    return [for (final json in responseList(answer)) JobQuote.fromJson(json)];
  }

  @override
  Future<JobQuote> withdrawQuote(String requestId) async => _quote(await _client.post(
        ApiEndpoints.serviceRequestQuoteWithdraw(requestId),
        authenticated: true,
      ));

  @override
  Future<JobQuote> rejectQuote(String requestId, String quoteId) async => _quote(await _client.post(
        ApiEndpoints.serviceRequestQuoteReject(requestId, quoteId),
        authenticated: true,
      ));

  // ─── The match ────────────────────────────────────────────────────────

  /// When two accepts race, exactly one wins: the server flips the row under a
  /// lock. The loser gets `conflict`, not a second match.
  @override
  Future<ServiceRequest> acceptQuote(String requestId, String quoteId) async =>
      _request(await _client.post(
        ApiEndpoints.serviceRequestQuoteAccept(requestId, quoteId),
        authenticated: true,
      ));

  @override
  Future<ServiceRequest> acceptEmergency(String requestId, {required int etaMinutes}) async =>
      _request(await _client.post(
        ApiEndpoints.serviceRequestAccept(requestId),
        body: {'etaMinutes': etaMinutes},
        authenticated: true,
      ));

  // ─── Progress, price and payment ──────────────────────────────────────

  /// Each step is idempotent — repeating one keeps the first timestamp — and
  /// gated: work needs arrival, and completing the service needs work.
  @override
  Future<ServiceRequest> advanceJob(String requestId, JobProgressStep step) async =>
      _request(await _client.post(
        ApiEndpoints.serviceRequestProgress(requestId, step.pathSegment),
        authenticated: true,
      ));

  @override
  Future<ServiceRequest> setAgreedAmount(String requestId, double amount) async =>
      _request(await _client.put(
        ApiEndpoints.serviceRequestAgreedAmount(requestId),
        body: {'amount': amount},
        authenticated: true,
      ));

  /// Paying closes the job. The server settles the quoted price (or the
  /// Emergency's agreed amount), the priority fee and both sides' points in one
  /// transaction, and pays twice for nothing if two taps race.
  ///
  /// Send [JobPaymentRequest.expectedAmount] to have a changed price refused
  /// rather than charged: the server answers `conflict` instead of taking a
  /// figure the client never saw.
  @override
  Future<ServiceRequest> payForJob(
    String requestId, {
    JobPaymentRequest payment = const JobPaymentRequest(),
  }) async =>
      _request(await _client.post(
        ApiEndpoints.serviceRequestPay(requestId),
        body: payment.toJson(),
        authenticated: true,
      ));

  // ─── Live ─────────────────────────────────────────────────────────────

  /// `service_request.created` reaches every mechanic when a job enters the
  /// pool; `service_request.updated` reaches the job's two parties. A caller
  /// sees whichever of the two the server addressed to them, so this merges
  /// both rather than guessing which one a given screen wants.
  ///
  /// Empty when there is no event socket — a caller that must not miss a
  /// change should re-fetch on resume as well as listen.
  @override
  Stream<ServiceRequest> watchRequests() => _merge(
        [ApiEventNames.serviceRequestCreated, ApiEventNames.serviceRequestUpdated],
        ServiceRequest.fromJson,
      );

  @override
  Stream<JobQuote> watchQuotes() => _merge(
        [ApiEventNames.quoteSubmitted, ApiEventNames.quoteUpdated],
        JobQuote.fromJson,
      );

  Stream<T> _merge<T>(List<String> names, T Function(Map<String, dynamic>) parse) {
    final events = _events;
    if (events == null) return const Stream.empty();
    final controller = StreamController<T>.broadcast();
    final subscriptions = <StreamSubscription<ApiEvent>>[];

    controller.onListen = () {
      for (final name in names) {
        subscriptions.add(events.on(name).listen((event) {
          if (event.data.isEmpty) return;
          try {
            controller.add(parse(event.data));
          } catch (_) {
            // A frame this build cannot read is dropped rather than killing
            // the stream: the next fetch is the source of truth anyway.
          }
        }));
      }
    };
    controller.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      subscriptions.clear();
    };
    return controller.stream;
  }

  static ServiceRequest _request(Object? json) => ServiceRequest.fromJson(responseObject(json));

  static JobQuote _quote(Object? json) => JobQuote.fromJson(responseObject(json));
}
