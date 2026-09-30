import 'dart:async';

import 'package:on_go_shared/on_go_shared.dart';

/// A [ServiceRequestApi] that answers the way the server does — its ids, its
/// separate problem and description, its `expectedArrivalAt`, a progress step
/// answered with the whole updated job — so a screen can be tested on the
/// backend's side of the seam without a network or the phone's own job store.
class ScriptedServiceRequests implements ServiceRequestApi {
  /// The caller's jobs, as the backend holds them.
  List<ServiceRequest> mine = [];
  Map<String, List<JobQuote>> quotes = {};

  /// When set, reading the list, or one job, fails with this.
  ApiException? listFails;
  ApiException? findFails;

  /// When set, a progress step is refused with this.
  ApiException? advanceFails;

  /// What a cancel answers; by default the request, cancelled, and gone.
  Future<ServiceRequest> Function(String requestId)? cancelWith;

  final cancelled = <String>[];
  final reopened = <String>[];
  final advanced = <JobProgressStep>[];
  final agreedAmounts = <double>[];
  var reads = 0;
  final requestEvents = StreamController<ServiceRequest>.broadcast();
  final quoteEvents = StreamController<JobQuote>.broadcast();

  Future<void> close() async {
    await requestEvents.close();
    await quoteEvents.close();
  }

  /// Replaces a job the way a change on the backend would, and announces it.
  void publish(ServiceRequest request) {
    mine = [for (final r in mine) r.id == request.id ? request : r];
    requestEvents.add(request);
  }

  @override
  Future<List<ServiceRequest>> listMyRequests({JobUrgency? urgency}) async {
    reads++;
    final failure = listFails;
    if (failure != null) throw failure;
    return List.of(mine);
  }

  @override
  Future<ServiceRequest?> findRequest(String requestId) async {
    reads++;
    final failure = findFails;
    if (failure != null) throw failure;
    for (final request in mine) {
      if (request.id == requestId) return request;
    }
    return null;
  }

  @override
  Future<List<JobQuote>> listQuotes(String requestId) async => quotes[requestId] ?? const [];

  @override
  Future<ServiceRequest> cancelRequest(String requestId, {String? reason}) {
    cancelled.add(requestId);
    final answer = cancelWith;
    if (answer != null) return answer(requestId);
    final request = mine.singleWhere((r) => r.id == requestId);
    mine = [for (final r in mine) if (r.id != requestId) r];
    return Future.value(request);
  }

  @override
  Future<ServiceRequest> reopenRequest(String requestId) async {
    reopened.add(requestId);
    return mine.singleWhere((r) => r.id == requestId);
  }

  @override
  Future<ServiceRequest> advanceJob(String requestId, JobProgressStep step) async {
    advanced.add(step);
    final failure = advanceFails;
    if (failure != null) throw failure;
    final json = mine.singleWhere((r) => r.id == requestId).toJson();
    final (flag, stamp) = switch (step) {
      JobProgressStep.navigating => ('navigating', 'navigatingAt'),
      JobProgressStep.enRoute => ('enRoute', 'enRouteAt'),
      JobProgressStep.arrived => ('arrived', 'arrivedAt'),
      JobProgressStep.startWork => ('workStarted', 'workStartedAt'),
      JobProgressStep.completeService => ('serviceCompleted', 'serviceCompletedAt'),
    };
    json[flag] = true;
    // Reporting a step twice keeps the first time, as the server does.
    json[stamp] ??= DateTime.now().toUtc().toIso8601String();
    final updated = ServiceRequest.fromJson(json);
    mine = [for (final r in mine) r.id == requestId ? updated : r];
    return updated;
  }

  @override
  Future<ServiceRequest> setAgreedAmount(String requestId, double amount) async {
    agreedAmounts.add(amount);
    final json = mine.singleWhere((r) => r.id == requestId).toJson()
      ..['agreedPaymentAmount'] = amount
      ..['agreedPaymentAmountSetAt'] = DateTime.now().toUtc().toIso8601String();
    final updated = ServiceRequest.fromJson(json);
    mine = [for (final r in mine) r.id == requestId ? updated : r];
    return updated;
  }

  @override
  Stream<ServiceRequest> watchRequests() => requestEvents.stream;

  @override
  Stream<JobQuote> watchQuotes() => quoteEvents.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// A job as the server would answer it. Ids are uuids there; any string does
/// here, as long as it is not the phone's own `local-…` shape.
ServiceRequest scriptedRequest({
  required String id,
  String problem = 'Flat tire',
  String description = '',
  JobUrgency urgency = JobUrgency.urgent,
  ServiceRequestStatus status = ServiceRequestStatus.pending,
  double surcharge = 50,
  DateTime? matchedAt,
  DateTime? deadlineAt,
  DateTime? expectedArrivalAt,
  String? mechanicName,
  bool navigating = false,
  bool enRoute = false,
  bool arrived = false,
  bool workStarted = false,
  bool serviceCompleted = false,
  bool paymentCompleted = false,
  double? agreedPaymentAmount,
  double? amountPaid,
  double? platformFeeCharged,
}) =>
    ServiceRequest(
      id: id,
      clientId: 'da530bdb-0000-4000-8000-000000000001',
      clientName: 'Carla Sample',
      problem: problem,
      description: description,
      location: 'EDSA Guadalupe',
      urgency: urgency,
      status: status,
      surcharge: surcharge,
      createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 10)),
      matchedAt: matchedAt,
      deadlineAt: deadlineAt,
      expectedArrivalAt: expectedArrivalAt,
      mechanicId: mechanicName == null ? null : '4004a552-0000-4000-8000-000000000002',
      mechanicName: mechanicName,
      navigating: navigating,
      enRoute: enRoute,
      arrived: arrived,
      workStarted: workStarted,
      serviceCompleted: serviceCompleted,
      paymentCompleted: paymentCompleted,
      agreedPaymentAmount: agreedPaymentAmount,
      amountPaid: amountPaid,
      platformFeeCharged: platformFeeCharged,
    );

JobQuote scriptedQuote(String id, String requestId,
        {bool accepted = false, DateTime? withdrawnAt, double price = 500, int etaMinutes = 30}) =>
    JobQuote(
      id: id,
      requestId: requestId,
      mechanicId: 'mechanic-$id',
      mechanicName: 'Mike Sample',
      price: price,
      etaMinutes: etaMinutes,
      rating: 4.5,
      accepted: accepted,
      withdrawnAt: withdrawnAt,
      createdAt: DateTime.now().toUtc(),
    );
