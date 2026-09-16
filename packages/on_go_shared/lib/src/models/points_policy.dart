import 'json.dart';

/// What one point is worth when it is spent or converted: ₱1.
///
/// The one place the exchange rate is written down. Everything that turns
/// points into pesos — a client paying a priority fee with points, a mechanic
/// converting points to balance — goes through [pesosForPoints] rather than
/// multiplying by its own copy of this.
const double pesosPerPoint = 1;

/// Pesos that [points] are worth.
double pesosForPoints(double points) => points * pesosPerPoint;

/// Points needed to cover [pesos].
double pointsForPesos(double pesos) => pesos / pesosPerPoint;

/// How points read on screen: `3`, `0.5`, `12.5` — never `3.0`.
///
/// Shared so the client's balance, the mechanic's, and the admin's own
/// configuration screen all spell the same number the same way.
String formatPoints(double points) {
  final rounded = (points * 100).round() / 100;
  if (rounded == rounded.roundToDouble()) return rounded.toStringAsFixed(0);
  final oneDecimal = (points * 10).round() / 10;
  return oneDecimal == rounded
      ? rounded.toStringAsFixed(1)
      : rounded.toStringAsFixed(2);
}

/// Pesos as the points surfaces write them: `₱150`, `₱1,250`.
///
/// Beside the exchange rate rather than in a widget file, so anything turning
/// points into money words it the same way.
String formatPesos(double amount) {
  final whole = amount.round().toString();
  final withSeparators = whole.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]},',
  );
  return '₱$withSeparators';
}

/// `12 pts` / `1 pt`.
String formatPointsLabel(double points) =>
    '${formatPoints(points)} ${points == 1 ? 'pt' : 'pts'}';

/// The rules that decide how many points an action is worth.
///
/// Owned by the admin console (Points Modifier) and read by the mobile app, so
/// nothing in the transaction logic carries its own numbers. [defaults] is the
/// fallback used before the policy has been fetched and when storage has
/// nothing saved — it is not a second copy of the rules, it is the starting
/// point the admin edits.
///
/// Every rate is a `double`: an admin setting a Normal job to 0.5 pts is an
/// example in the brief, not an edge case.
///
/// One figure per urgency, awarded to BOTH sides of a paid job: the client who
/// paid and the mechanic who was paid earn the same points. The field names
/// are the On Go API's (`clientNormal`…), which is why they still say client.
/// Neither side is shown what a job awards — only the admin sees the rates.
class PointsPolicy {
  /// Points for a completed, paid Normal job — client and mechanic alike.
  final double clientNormal;

  /// …for an Urgent job.
  final double clientUrgent;

  /// …for an Emergency job.
  final double clientEmergency;

  /// The API's old per-peso mechanic rate. The apps no longer award by it —
  /// mechanics earn [pointsFor] their job's urgency — but the API requires the
  /// field on every update, so it is carried through unchanged.
  final double mechanicPerPeso;

  const PointsPolicy({
    this.clientNormal = 1,
    this.clientUrgent = 3,
    this.clientEmergency = 5,
    this.mechanicPerPeso = 0.05,
  });

  /// What the platform starts on, and what "Reset to defaults" restores.
  static const PointsPolicy defaults = PointsPolicy();

  /// The urgency names the mobile app uses on a job.
  static const List<String> urgencies = ['Normal', 'Urgent', 'Emergency'];

  /// What a paid job of [urgency] awards — to the client, and the same to the
  /// mechanic. An unknown urgency is treated as Normal, the same way the app's
  /// own pricing does.
  double pointsFor(String urgency) {
    switch (urgency) {
      case 'Emergency':
        return clientEmergency;
      case 'Urgent':
        return clientUrgent;
      default:
        return clientNormal;
    }
  }

  PointsPolicy copyWith({
    double? clientNormal,
    double? clientUrgent,
    double? clientEmergency,
    double? mechanicPerPeso,
  }) =>
      PointsPolicy(
        clientNormal: clientNormal ?? this.clientNormal,
        clientUrgent: clientUrgent ?? this.clientUrgent,
        clientEmergency: clientEmergency ?? this.clientEmergency,
        mechanicPerPeso: mechanicPerPeso ?? this.mechanicPerPeso,
      );

  /// The points for [urgency], replaced — so the admin screen can edit one row
  /// without knowing which field backs it.
  PointsPolicy withPoints(String urgency, double points) {
    switch (urgency) {
      case 'Emergency':
        return copyWith(clientEmergency: points);
      case 'Urgent':
        return copyWith(clientUrgent: points);
      default:
        return copyWith(clientNormal: points);
    }
  }

  Map<String, dynamic> toJson() => {
        'clientNormal': clientNormal,
        'clientUrgent': clientUrgent,
        'clientEmergency': clientEmergency,
        'mechanicPerPeso': mechanicPerPeso,
      };

  factory PointsPolicy.fromJson(Map<String, dynamic> json) => PointsPolicy(
        clientNormal: readDouble(json['clientNormal'], defaults.clientNormal),
        clientUrgent: readDouble(json['clientUrgent'], defaults.clientUrgent),
        clientEmergency:
            readDouble(json['clientEmergency'], defaults.clientEmergency),
        mechanicPerPeso:
            readDouble(json['mechanicPerPeso'], defaults.mechanicPerPeso),
      );

  @override
  bool operator ==(Object other) =>
      other is PointsPolicy &&
      other.clientNormal == clientNormal &&
      other.clientUrgent == clientUrgent &&
      other.clientEmergency == clientEmergency &&
      other.mechanicPerPeso == mechanicPerPeso;

  @override
  int get hashCode =>
      Object.hash(clientNormal, clientUrgent, clientEmergency, mechanicPerPeso);
}
