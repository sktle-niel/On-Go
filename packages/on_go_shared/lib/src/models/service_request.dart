import 'geo_location.dart';
import 'json.dart';

/// How soon a client needs help, as a job carries it on the wire.
///
/// Spelled capitalised (`Normal`, `Urgent`, `Emergency`): the strings the
/// mobile app already puts on a job. The revenue ledger buckets the same three
/// in lower case as `RevenueUrgency`, and `RevenueUrgency.fromJobUrgency`
/// takes [wireName].
enum JobUrgency {
  normal('Normal'),
  urgent('Urgent'),
  emergency('Emergency');

  const JobUrgency(this.wireName);

  final String wireName;

  /// How the urgency reads on screen.
  String get label => wireName;

  static JobUrgency fromWire(String value) => JobUrgency.values.firstWhere(
        (urgency) => urgency.wireName == value,
        orElse: () => JobUrgency.normal,
      );
}

/// Where a service request stands.
enum ServiceRequestStatus {
  /// Open. Normal and Urgent requests collect quotes; an Emergency waits for
  /// the first mechanic to accept it.
  pending('pending'),

  /// A mechanic is assigned. Progress steps and payment happen here.
  matched('matched'),

  /// Paid, which closes the job.
  completed('completed'),

  /// Called off.
  cancelled('cancelled');

  const ServiceRequestStatus(this.wireName);

  final String wireName;

  static ServiceRequestStatus fromWire(String value) =>
      ServiceRequestStatus.values.firstWhere(
        (status) => status.wireName == value,
        orElse: () => ServiceRequestStatus.pending,
      );
}

/// A step the assigned mechanic reports on a matched job, in order.
///
/// Each step is idempotent: reporting it twice keeps the first time. Starting
/// work needs [arrived], and completing the service needs [startWork].
/// Completing the service leaves the job matched; the client's payment is what
/// closes it.
enum JobProgressStep {
  navigating('navigating'),
  enRoute('en-route'),
  arrived('arrived'),
  startWork('start-work'),
  completeService('complete-service');

  const JobProgressStep(this.pathSegment);

  /// The last segment of the route that reports this step.
  final String pathSegment;
}

/// One request for help as the server holds it: the booking, the match, the
/// mechanic's progress and the payment, on one record both phones read.
///
/// Every figure on it is the server's. A client books with
/// [NewServiceRequest]; every later `ServiceRequestApi` call answers the
/// updated request.
class ServiceRequest {
  final String id;
  final String clientId;
  final String clientName;
  final String problem;
  final String description;
  final String location;
  final JobUrgency urgency;

  /// ONGO's priority fee for [urgency], in pesos, set by the server.
  final double surcharge;

  final double? latitude;
  final double? longitude;
  final ServiceRequestStatus status;
  final DateTime createdAt;
  final DateTime? matchedAt;
  final DateTime? completedAt;

  /// When an Urgent (3 days) or Emergency (12 hours) job must be under way,
  /// counted from the match; null for a Normal job. A job not under way by
  /// then returns to the pool. Countdowns read this, not a clock of their own.
  final DateTime? deadlineAt;

  /// [matchedAt] plus the accepted ETA. The client may cancel or reopen a
  /// matched job only after this, or once the mechanic has arrived.
  final DateTime? expectedArrivalAt;

  final String? mechanicId;
  final String? mechanicName;

  final bool navigating;
  final DateTime? navigatingAt;
  final bool enRoute;
  final DateTime? enRouteAt;
  final bool arrived;
  final DateTime? arrivedAt;
  final bool workStarted;
  final DateTime? workStartedAt;
  final bool serviceCompleted;
  final DateTime? serviceCompletedAt;

  final String? lastCancelReason;
  final String? lastCancelledBy;
  final DateTime? lastCancelledAt;
  final DateTime? expiredAt;
  final String? expiredByMechanic;

  /// Emergency only: the price agreed in person, recorded by the mechanic.
  final double? agreedPaymentAmount;
  final DateTime? agreedPaymentAmountSetAt;

  final bool paymentCompleted;
  final DateTime? paymentCompletedAt;

  /// The mechanic's amount as charged, in pesos; null until paid.
  final double? amountPaid;

  /// The priority fee as booked at payment, in pesos; null until paid.
  final double? platformFeeCharged;

  /// Points the client spent on the fee; null when it was paid in pesos.
  final double? feePaidWithPoints;

  /// Points the mechanic earned on this job.
  final double? pointsAwarded;

  /// Points the client earned on this job.
  final double? clientPointsAwarded;

  const ServiceRequest({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.problem,
    required this.location,
    required this.urgency,
    required this.status,
    required this.createdAt,
    this.description = '',
    this.surcharge = 0,
    this.latitude,
    this.longitude,
    this.matchedAt,
    this.completedAt,
    this.deadlineAt,
    this.expectedArrivalAt,
    this.mechanicId,
    this.mechanicName,
    this.navigating = false,
    this.navigatingAt,
    this.enRoute = false,
    this.enRouteAt,
    this.arrived = false,
    this.arrivedAt,
    this.workStarted = false,
    this.workStartedAt,
    this.serviceCompleted = false,
    this.serviceCompletedAt,
    this.lastCancelReason,
    this.lastCancelledBy,
    this.lastCancelledAt,
    this.expiredAt,
    this.expiredByMechanic,
    this.agreedPaymentAmount,
    this.agreedPaymentAmountSetAt,
    this.paymentCompleted = false,
    this.paymentCompletedAt,
    this.amountPaid,
    this.platformFeeCharged,
    this.feePaidWithPoints,
    this.pointsAwarded,
    this.clientPointsAwarded,
  });

  /// The job's coordinates, or null when the booking carried none.
  GeoPoint? get point {
    final lat = latitude;
    final lng = longitude;
    return lat == null || lng == null ? null : GeoPoint(lat, lng);
  }

  bool get isEmergency => urgency == JobUrgency.emergency;

  Map<String, dynamic> toJson() => {
        'id': id,
        'clientId': clientId,
        'clientName': clientName,
        'problem': problem,
        'description': description,
        'location': location,
        'urgency': urgency.wireName,
        'surcharge': surcharge,
        'latitude': latitude,
        'longitude': longitude,
        'status': status.wireName,
        'createdAt': writeDate(createdAt),
        'matchedAt': writeDateOrNull(matchedAt),
        'completedAt': writeDateOrNull(completedAt),
        'deadlineAt': writeDateOrNull(deadlineAt),
        'expectedArrivalAt': writeDateOrNull(expectedArrivalAt),
        'mechanicId': mechanicId,
        'mechanicName': mechanicName,
        'navigating': navigating,
        'navigatingAt': writeDateOrNull(navigatingAt),
        'enRoute': enRoute,
        'enRouteAt': writeDateOrNull(enRouteAt),
        'arrived': arrived,
        'arrivedAt': writeDateOrNull(arrivedAt),
        'workStarted': workStarted,
        'workStartedAt': writeDateOrNull(workStartedAt),
        'serviceCompleted': serviceCompleted,
        'serviceCompletedAt': writeDateOrNull(serviceCompletedAt),
        'lastCancelReason': lastCancelReason,
        'lastCancelledBy': lastCancelledBy,
        'lastCancelledAt': writeDateOrNull(lastCancelledAt),
        'expiredAt': writeDateOrNull(expiredAt),
        'expiredByMechanic': expiredByMechanic,
        'agreedPaymentAmount': agreedPaymentAmount,
        'agreedPaymentAmountSetAt': writeDateOrNull(agreedPaymentAmountSetAt),
        'paymentCompleted': paymentCompleted,
        'paymentCompletedAt': writeDateOrNull(paymentCompletedAt),
        'amountPaid': amountPaid,
        'platformFeeCharged': platformFeeCharged,
        'feePaidWithPoints': feePaidWithPoints,
        'pointsAwarded': pointsAwarded,
        'clientPointsAwarded': clientPointsAwarded,
      };

  factory ServiceRequest.fromJson(Map<String, dynamic> json) => ServiceRequest(
        id: readString(json['id']),
        clientId: readString(json['clientId']),
        clientName: readString(json['clientName']),
        problem: readString(json['problem']),
        description: readString(json['description']),
        location: readString(json['location']),
        urgency: JobUrgency.fromWire(readString(json['urgency'])),
        surcharge: readDouble(json['surcharge']),
        latitude: readDoubleOrNull(json['latitude']),
        longitude: readDoubleOrNull(json['longitude']),
        status: ServiceRequestStatus.fromWire(readString(json['status'])),
        createdAt: readDate(json['createdAt']),
        matchedAt: readDateOrNull(json['matchedAt']),
        completedAt: readDateOrNull(json['completedAt']),
        deadlineAt: readDateOrNull(json['deadlineAt']),
        expectedArrivalAt: readDateOrNull(json['expectedArrivalAt']),
        mechanicId: readStringOrNull(json['mechanicId']),
        mechanicName: readStringOrNull(json['mechanicName']),
        navigating: readBool(json['navigating']),
        navigatingAt: readDateOrNull(json['navigatingAt']),
        enRoute: readBool(json['enRoute']),
        enRouteAt: readDateOrNull(json['enRouteAt']),
        arrived: readBool(json['arrived']),
        arrivedAt: readDateOrNull(json['arrivedAt']),
        workStarted: readBool(json['workStarted']),
        workStartedAt: readDateOrNull(json['workStartedAt']),
        serviceCompleted: readBool(json['serviceCompleted']),
        serviceCompletedAt: readDateOrNull(json['serviceCompletedAt']),
        lastCancelReason: readStringOrNull(json['lastCancelReason']),
        lastCancelledBy: readStringOrNull(json['lastCancelledBy']),
        lastCancelledAt: readDateOrNull(json['lastCancelledAt']),
        expiredAt: readDateOrNull(json['expiredAt']),
        expiredByMechanic: readStringOrNull(json['expiredByMechanic']),
        agreedPaymentAmount: readDoubleOrNull(json['agreedPaymentAmount']),
        agreedPaymentAmountSetAt: readDateOrNull(json['agreedPaymentAmountSetAt']),
        paymentCompleted: readBool(json['paymentCompleted']),
        paymentCompletedAt: readDateOrNull(json['paymentCompletedAt']),
        amountPaid: readDoubleOrNull(json['amountPaid']),
        platformFeeCharged: readDoubleOrNull(json['platformFeeCharged']),
        feePaidWithPoints: readDoubleOrNull(json['feePaidWithPoints']),
        pointsAwarded: readDoubleOrNull(json['pointsAwarded']),
        clientPointsAwarded: readDoubleOrNull(json['clientPointsAwarded']),
      );
}

/// What a client sends to book help. The server fills in the rest: the
/// priority fee, the status, and the client, from the token.
class NewServiceRequest {
  final String problem;
  final String? description;
  final String location;
  final JobUrgency urgency;

  /// Where the client is, when the phone has a fix.
  final GeoPoint? point;

  const NewServiceRequest({
    required this.problem,
    required this.location,
    required this.urgency,
    this.description,
    this.point,
  });

  Map<String, dynamic> toJson() => {
        'problem': problem,
        if (description != null) 'description': description,
        'location': location,
        'urgency': urgency.wireName,
        'latitude': point?.latitude,
        'longitude': point?.longitude,
      };
}

/// The client's side of paying for a finished job. Every figure is settled by
/// the server; this only says what the client agreed to.
class JobPaymentRequest {
  /// Spend points on the priority fee when the balance covers it. A short
  /// balance is charged in pesos, never waived.
  final bool payFeeWithPoints;

  /// The mechanic's amount the client saw. When the current amount differs,
  /// the server refuses with `409 conflict` rather than charge it.
  final double? expectedAmount;

  const JobPaymentRequest({this.payFeeWithPoints = false, this.expectedAmount});

  Map<String, dynamic> toJson() => {
        'payFeeWithPoints': payFeeWithPoints,
        if (expectedAmount != null) 'expectedAmount': expectedAmount,
      };
}
