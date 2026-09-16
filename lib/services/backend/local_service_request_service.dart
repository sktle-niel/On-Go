import 'dart:async';

import 'package:on_go_shared/on_go_shared.dart';

import '../../data/app_session.dart';
import '../../data/quote_store.dart';
import '../../data/review_store.dart';

/// [ServiceRequestApi] over the on-device job store, for an
/// `ONGO_BACKEND=local` build.
///
/// This is an adapter, not a second implementation of the rules. Every rule it
/// enforces is the one `quote_store.dart` already enforces — the completion
/// windows, the ETA cap, the cancel lock, the priority fee, the points — and
/// this class only reshapes the call and the answer so a screen can be written
/// once against [ServiceRequestApi] and work either way.
///
/// The two shapes differ in three ways worth knowing:
///
/// * **Identity.** The store knows people by name; the server knows them by
///   account id. A name is used as the id here, so `clientId == clientName`.
///   Nothing on this side compares an id across the two.
/// * **Refusals.** The store reports a refusal by returning false or null.
///   Each one is raised as the [ApiException] the server would have sent, with
///   the same `code`, so a screen's error handling does not branch on which
///   backend it is talking to. A cancel refused by the ETA lock carries
///   `cancellableAt` on [ApiException.info], as the server's does.
/// * **Cancellation.** The store has no `cancelled` state — a cancelled
///   request leaves the list. [cancelRequest] therefore answers the request as
///   it was, marked cancelled, rather than re-reading one that is gone.
///
/// The store also guards who may call what, against [AppSession] rather than a
/// token, and reports a wrong caller by throwing a [StateError]. Every call
/// here goes through [_guarded], which turns that into the `forbidden` the
/// server would have answered — so "a client cannot advance a job" reads the
/// same to a screen whichever backend is underneath.
class LocalServiceRequestService implements ServiceRequestApi {
  LocalServiceRequestService({QuoteNotificationStore? store}) : _store = store;

  final QuoteNotificationStore? _store;

  QuoteNotificationStore get _jobs => _store ?? QuoteNotificationStore.instance;

  // ─── Booking and reading ──────────────────────────────────────────────

  @override
  Future<ServiceRequest> bookRequest(NewServiceRequest request) async {
    if (_jobs.activeRequest != null) {
      throw _conflict('You already have a request open. Close it before booking another.');
    }
    final point = request.point;
    final booked = HelpRequest(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      problem: request.problem,
      location: request.location,
      urgency: request.urgency.wireName,
      createdAt: DateTime.now(),
      // Who the job belongs to — what its evaluation, points and history are
      // recorded against. Without it every local booking would be filed under
      // HelpRequest's placeholder name.
      clientName: ReviewStore.currentClientName,
      // The admin's configured charge for this urgency, which is what the rest
      // of a local build prices against. The server has its own fixed table;
      // whichever backend is in use, the fee comes from that backend.
      surcharge: additionalChargeFor(request.urgency.wireName),
      clientLat: point?.latitude,
      clientLng: point?.longitude,
    );
    _guarded(() => _jobs.submitRequest(booked));
    return _toDto(booked);
  }

  @override
  Future<List<ServiceRequest>> listOpenRequests({JobUrgency? urgency}) async =>
      _dtos(_jobs.availableJobs, urgency);

  @override
  Future<List<ServiceRequest>> listMyRequests({JobUrgency? urgency}) async {
    final mine = <HelpRequest>[
      ..._jobs.myPendingRequests,
      ..._jobs.myActiveJobs,
      ..._jobs.myCompletedJobs,
      // A mechanic's own jobs, by the only name this build has for them.
      ..._jobs.matchedJobsFor(QuoteNotificationStore.currentMechanicName),
      ..._jobs.completedJobsFor(QuoteNotificationStore.currentMechanicName),
    ];
    final seen = <String>{};
    return _dtos([for (final job in mine) if (seen.add(job.id)) job], urgency);
  }

  @override
  Future<ServiceRequest?> findRequest(String requestId) async {
    final request = _jobs.requestFor(requestId);
    return request == null ? null : _toDto(request);
  }

  // ─── Calling a job off ────────────────────────────────────────────────

  @override
  Future<ServiceRequest> cancelRequest(String requestId, {String? reason}) async {
    final request = _required(requestId);
    _refuseIfLocked(request);
    // Read the record before it leaves the store: there is nothing to re-read.
    final answer = _toDto(request, statusOverride: ServiceRequestStatus.cancelled);
    if (!_guarded(() => _jobs.clientDeleteRequest(requestId))) {
      throw _conflict('This job can no longer be cancelled.');
    }
    return answer;
  }

  @override
  Future<ServiceRequest> reopenRequest(String requestId) async {
    final request = _required(requestId);
    _refuseIfLocked(request);
    if (!_guarded(() => _jobs.clientRevertToPending(requestId))) {
      throw _conflict('This job can no longer be put back in the pool.');
    }
    return _toDto(_required(requestId));
  }

  @override
  Future<ServiceRequest> mechanicCancelJob(String requestId, {required String reason}) async {
    _required(requestId);
    if (!_guarded(() => _jobs.mechanicCancelJob(requestId, reason))) {
      throw _conflict('This job can no longer be cancelled.');
    }
    return _toDto(_required(requestId));
  }

  // ─── Quotes ───────────────────────────────────────────────────────────

  @override
  Future<JobQuote> submitQuote(String requestId, QuoteSubmission quote) async {
    final request = _required(requestId);
    final eta = Duration(minutes: quote.etaMinutes);
    // The store's own cap, so a local build refuses exactly what the server
    // would: an arrival promised past the completion window. The store's
    // wording is better than anything invented here — it names the urgency,
    // the window and what is left of it.
    final tooLong = etaTooLongReason(request, eta);
    if (tooLong != null) throw _badRequest(tooLong);

    final mechanic = QuoteNotificationStore.currentMechanicName;
    _guarded(() => _jobs.mechanicSendQuote(
          requestId,
          mechanicName: mechanic,
          price: '₱${quote.price.toStringAsFixed(0)}',
          eta: eta,
          rating: ReviewStore.instance.averageRatingFor(mechanic),
        ));
    final sent = _jobs.mechanicLiveQuoteFor(requestId, mechanic);
    if (sent == null) throw _conflict('That quote could not be sent.');
    return _toQuoteDto(sent);
  }

  @override
  Future<List<JobQuote>> listQuotes(String requestId) async =>
      [for (final quote in _jobs.quotesForRequest(requestId)) _toQuoteDto(quote)];

  @override
  Future<JobQuote> withdrawQuote(String requestId) async {
    final mechanic = QuoteNotificationStore.currentMechanicName;
    final live = _jobs.mechanicLiveQuoteFor(requestId, mechanic);
    if (live == null) throw _notFound('You have no live quote on this job.');
    if (!_guarded(() => _jobs.mechanicWithdrawQuote(requestId, mechanicName: mechanic))) {
      throw _conflict('That quote can no longer be withdrawn.');
    }
    return _toQuoteDto(live);
  }

  @override
  Future<JobQuote> rejectQuote(String requestId, String quoteId) async {
    final quote = _jobs.quoteById(quoteId);
    if (quote == null) throw _notFound('That quote is not available.');
    if (!_guarded(() => _jobs.clientRejectQuote(quoteId))) {
      throw _conflict('That quote can no longer be turned down.');
    }
    return _toQuoteDto(quote);
  }

  // ─── The match ────────────────────────────────────────────────────────

  @override
  Future<ServiceRequest> acceptQuote(String requestId, String quoteId) async {
    final request = _required(requestId);
    if (request.status != RequestStatus.pending) {
      throw _conflict('This request has already been matched or closed.');
    }
    if (_jobs.quoteById(quoteId) == null) throw _notFound('That quote is not available to accept.');
    _guarded(() => _jobs.clientAcceptQuote(quoteId));
    return _toDto(_required(requestId));
  }

  @override
  Future<ServiceRequest> acceptEmergency(String requestId, {required int etaMinutes}) async {
    _required(requestId);
    final mechanic = QuoteNotificationStore.currentMechanicName;
    final accepted = _guarded(() => _jobs.mechanicAcceptEmergency(
          requestId,
          mechanicName: mechanic,
          eta: Duration(minutes: etaMinutes),
          rating: ReviewStore.instance.averageRatingFor(mechanic),
        ));
    if (!accepted) throw _conflict('This emergency has already been taken.');
    return _toDto(_required(requestId));
  }

  // ─── Progress, price and payment ──────────────────────────────────────

  @override
  Future<ServiceRequest> advanceJob(String requestId, JobProgressStep step) async {
    final request = _required(requestId);
    // Gated in the same order the server gates it, so a local build cannot
    // reach a state the server would have refused.
    switch (step) {
      case JobProgressStep.navigating:
        _guarded(() => _jobs.mechanicStartNavigating(requestId));
      case JobProgressStep.enRoute:
        _guarded(() => _jobs.mechanicMarkEnRoute(requestId));
      case JobProgressStep.arrived:
        _guarded(() => _jobs.mechanicMarkArrived(requestId));
      case JobProgressStep.startWork:
        if (!request.arrived) throw _conflict('The mechanic has not arrived yet.');
        _guarded(() => _jobs.mechanicStartWork(requestId));
      case JobProgressStep.completeService:
        if (!request.workStarted) throw _conflict('The work has not been started yet.');
        _guarded(() => _jobs.mechanicCompleteService(requestId));
    }
    return _toDto(_required(requestId));
  }

  @override
  Future<ServiceRequest> setAgreedAmount(String requestId, double amount) async {
    _required(requestId);
    if (!_guarded(() => _jobs.mechanicSetPaymentAmount(requestId, amount))) {
      throw _conflict('That amount cannot be set on this job.');
    }
    return _toDto(_required(requestId));
  }

  @override
  Future<ServiceRequest> payForJob(
    String requestId, {
    JobPaymentRequest payment = const JobPaymentRequest(),
  }) async {
    final request = _required(requestId);
    if (request.paymentCompleted) return _toDto(request);
    if (!request.serviceCompleted) {
      throw _conflict('The mechanic has not marked the service complete yet.');
    }
    final expected = payment.expectedAmount;
    if (expected != null) {
      final current = effectivePaymentAmount(request, _jobs.acceptedQuoteFor(requestId));
      if (current != null && (current - expected).abs() >= 0.005) {
        throw _conflict('The amount to pay has changed. Review it and pay again.');
      }
    }
    final paid = _guarded(
        () => _jobs.clientConfirmPayment(requestId, payFeeWithPoints: payment.payFeeWithPoints));
    if (paid == null) throw _conflict('This job could not be paid.');
    return _toDto(_required(requestId));
  }

  // ─── Live ─────────────────────────────────────────────────────────────

  /// The store is a [ChangeNotifier], so there is no per-record event to
  /// forward: every change republishes the caller's own requests. A screen
  /// listening here sees the same records it would get from the server, just
  /// arriving as a set rather than one at a time.
  @override
  Stream<ServiceRequest> watchRequests() =>
      _onChange(() async => listMyRequests()).asyncExpand(Stream.fromIterable);

  @override
  Stream<JobQuote> watchQuotes() => _onChange(() async {
        final active = _jobs.activeRequest;
        return active == null ? const <JobQuote>[] : await listQuotes(active.id);
      }).asyncExpand(Stream.fromIterable);

  Stream<List<T>> _onChange<T>(Future<List<T>> Function() read) {
    late final StreamController<List<T>> controller;
    Future<void> emit() async {
      if (controller.isClosed) return;
      controller.add(await read());
    }

    void listener() => unawaited(emit());
    controller = StreamController<List<T>>.broadcast(
      onListen: () {
        _jobs.addListener(listener);
        unawaited(emit());
      },
      onCancel: () => _jobs.removeListener(listener),
    );
    return controller.stream;
  }

  // ─── Reshaping ────────────────────────────────────────────────────────

  List<ServiceRequest> _dtos(List<HelpRequest> requests, JobUrgency? urgency) => [
        for (final request in requests)
          if (urgency == null || request.urgency == urgency.wireName) _toDto(request),
      ];

  HelpRequest _required(String requestId) {
    final request = _jobs.requestFor(requestId);
    if (request == null) throw _notFound('Request not found.');
    return request;
  }

  /// Refuses a client's cancel or reopen while the mechanic is still inside
  /// their promised arrival time, and says when it opens — the same refusal,
  /// with the same fact attached, that the server sends.
  void _refuseIfLocked(HelpRequest request) {
    final accepted = _jobs.acceptedQuoteFor(request.id);
    if (!clientCancelLockedByEta(request, accepted)) return;
    final opensAt = expectedArrivalAt(request, accepted);
    throw ApiException(
      ApiErrorKind.rejected,
      'The mechanic is still on their way.',
      code: ApiErrorCodes.conflict,
      info: {if (opensAt != null) 'cancellableAt': opensAt.toUtc().toIso8601String()},
    );
  }

  ServiceRequest _toDto(HelpRequest request, {ServiceRequestStatus? statusOverride}) {
    final accepted = _jobs.acceptedQuoteFor(request.id);
    return ServiceRequest(
      id: request.id,
      // A name is the only identity this build has for a person.
      clientId: request.clientName,
      clientName: request.clientName,
      problem: request.problem,
      description: '',
      location: request.location,
      urgency: JobUrgency.fromWire(request.urgency),
      surcharge: request.surcharge,
      latitude: request.clientLat,
      longitude: request.clientLng,
      status: statusOverride ?? _statusOf(request.status),
      createdAt: request.createdAt,
      matchedAt: request.matchedAt,
      completedAt: request.completedAt,
      deadlineAt: request.completionDeadline,
      expectedArrivalAt: expectedArrivalAt(request, accepted),
      mechanicId: accepted?.mechanicName,
      mechanicName: accepted?.mechanicName,
      navigating: request.navigating,
      navigatingAt: request.navigatingAt,
      enRoute: request.enRoute,
      enRouteAt: request.enRouteAt,
      arrived: request.arrived,
      arrivedAt: request.arrivedAt,
      workStarted: request.workStarted,
      workStartedAt: request.workStartedAt,
      serviceCompleted: request.serviceCompleted,
      serviceCompletedAt: request.serviceCompletedAt,
      lastCancelReason: request.lastCancelReason,
      lastCancelledBy: request.lastCancelledBy,
      lastCancelledAt: request.lastCancelledAt,
      expiredAt: request.expiredAt,
      expiredByMechanic: request.expiredByMechanic,
      agreedPaymentAmount: request.agreedPaymentAmount,
      agreedPaymentAmountSetAt: request.agreedPaymentAmountSetAt,
      paymentCompleted: request.paymentCompleted,
      paymentCompletedAt: request.paymentCompletedAt,
      amountPaid: request.amountPaid,
      platformFeeCharged: request.platformFeeCharged,
      feePaidWithPoints: request.feePaidWithPoints,
      pointsAwarded: request.pointsAwarded,
      // The store awards the client's points through the wallet rather than
      // stamping them on the job, so there is nothing to read back here.
      clientPointsAwarded: null,
    );
  }

  JobQuote _toQuoteDto(MechanicQuote quote) => JobQuote(
        id: quote.id,
        requestId: quote.requestId,
        mechanicId: quote.mechanicName,
        mechanicName: quote.mechanicName,
        price: parsePesoAmount(quote.price),
        etaMinutes: quote.etaDuration.inMinutes,
        rating: quote.rating,
        accepted: quote.accepted,
        withdrawnAt: quote.withdrawnAt,
        rejectedAt: quote.rejectedAt,
        // The store does not record when a quote was sent. The job's own
        // creation time is the closest stable stand-in — never later than the
        // quote, and it does not change between reads the way now() would.
        createdAt: _jobs.requestFor(quote.requestId)?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  static ServiceRequestStatus _statusOf(RequestStatus status) => switch (status) {
        RequestStatus.pending => ServiceRequestStatus.pending,
        RequestStatus.matched => ServiceRequestStatus.matched,
        RequestStatus.completed => ServiceRequestStatus.completed,
      };

  /// The store enforces role and approval by throwing. On the server the same
  /// call is a 403, so that is what a screen should see either way.
  static T _guarded<T>(T Function() call) {
    try {
      return call();
    } on StateError catch (error) {
      throw ApiException(
        ApiErrorKind.forbidden,
        error.message,
        code: ApiErrorCodes.forbidden,
      );
    }
  }

  static ApiException _conflict(String message) =>
      ApiException(ApiErrorKind.rejected, message, code: ApiErrorCodes.conflict);

  static ApiException _notFound(String message) =>
      ApiException(ApiErrorKind.notFound, message, code: ApiErrorCodes.notFound);

  static ApiException _badRequest(String message) =>
      ApiException(ApiErrorKind.rejected, message, code: ApiErrorCodes.badRequest);
}
