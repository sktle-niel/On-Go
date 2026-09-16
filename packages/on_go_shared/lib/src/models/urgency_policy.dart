import 'json.dart';
import 'points_policy.dart';

/// The units an admin can set a completion time in. [none] means the urgency
/// sets no deadline: a job's timing is then whatever ETA the mechanic quotes.
enum CompletionTimeUnit {
  none('none', 'None'),
  minutes('minutes', 'Minutes'),
  hours('hours', 'Hours'),
  days('days', 'Days');

  const CompletionTimeUnit(this.wireName, this.label);

  final String wireName;
  final String label;

  static CompletionTimeUnit fromWire(String value) => CompletionTimeUnit.values.firstWhere(
        (unit) => unit.wireName == value,
        orElse: () => CompletionTimeUnit.none,
      );
}

/// How long a mechanic has to finish a job once they accept it — a whole
/// number of one unit, kept exactly as the admin entered it ("12 hours", not
/// "720 minutes"), the same way a mechanic's ETA is.
class CompletionTime {
  const CompletionTime(this.value, this.unit);

  /// No time limit.
  const CompletionTime.none()
      : value = 0,
        unit = CompletionTimeUnit.none;

  final int value;
  final CompletionTimeUnit unit;

  bool get isNone => unit == CompletionTimeUnit.none || value <= 0;

  /// The window as a duration, or null when there is no time limit.
  Duration? get duration {
    if (isNone) return null;
    return switch (unit) {
      CompletionTimeUnit.minutes => Duration(minutes: value),
      CompletionTimeUnit.hours => Duration(hours: value),
      CompletionTimeUnit.days => Duration(days: value),
      CompletionTimeUnit.none => null,
    };
  }

  /// "No time limit", "45 minutes", "1 hour", "3 days".
  String get label {
    if (isNone) return 'No time limit';
    final plural = value == 1 ? '' : 's';
    return switch (unit) {
      CompletionTimeUnit.minutes => '$value minute$plural',
      CompletionTimeUnit.hours => '$value hour$plural',
      CompletionTimeUnit.days => '$value day$plural',
      CompletionTimeUnit.none => 'No time limit',
    };
  }

  Map<String, dynamic> toJson() => {'value': isNone ? 0 : value, 'unit': isNone ? 'none' : unit.wireName};

  factory CompletionTime.fromJson(Map<String, dynamic> json) {
    final unit = CompletionTimeUnit.fromWire(readString(json['unit']));
    final value = readInt(json['value']);
    return unit == CompletionTimeUnit.none || value <= 0 ? const CompletionTime.none() : CompletionTime(value, unit);
  }

  @override
  bool operator ==(Object other) =>
      other is CompletionTime &&
      ((other.isNone && isNone) || (other.value == value && other.unit == unit));

  @override
  int get hashCode => isNone ? 0 : Object.hash(value, unit);
}

/// What one urgency level costs the client and gives the mechanic to finish.
class UrgencyTerms {
  const UrgencyTerms({required this.additionalCharge, required this.completionTime});

  /// Pesos added to the client's total at checkout. ONGO's revenue — never
  /// part of what the mechanic is paid.
  final double additionalCharge;

  final CompletionTime completionTime;

  /// No negative charge, and a completion time of at least one unit unless it
  /// is None.
  bool get isValid =>
      additionalCharge >= 0 &&
      (completionTime.unit == CompletionTimeUnit.none || completionTime.value >= 1);

  UrgencyTerms copyWith({double? additionalCharge, CompletionTime? completionTime}) => UrgencyTerms(
        additionalCharge: additionalCharge ?? this.additionalCharge,
        completionTime: completionTime ?? this.completionTime,
      );

  Map<String, dynamic> toJson() => {
        'additionalCharge': additionalCharge,
        'completionTime': completionTime.toJson(),
      };

  factory UrgencyTerms.fromJson(Map<String, dynamic> json, UrgencyTerms fallback) => UrgencyTerms(
        additionalCharge: readDouble(json['additionalCharge'], fallback.additionalCharge),
        completionTime: json['completionTime'] is Map
            ? CompletionTime.fromJson(readObject(json['completionTime']))
            : fallback.completionTime,
      );

  @override
  bool operator ==(Object other) =>
      other is UrgencyTerms &&
      other.additionalCharge == additionalCharge &&
      other.completionTime == completionTime;

  @override
  int get hashCode => Object.hash(additionalCharge, completionTime);
}

/// The additional charge and completion time for every urgency level, set by
/// the admin. The points each level awards are in [PointsPolicy].
///
/// Like [PointsPolicy], nothing in the app carries its own copy: pricing a new
/// job, its deadline and the longest ETA a mechanic may quote all read these.
/// [defaults] is the starting point the admin edits, not a second set of rules.
class UrgencyPolicy {
  const UrgencyPolicy({
    this.normal = const UrgencyTerms(additionalCharge: 10, completionTime: CompletionTime.none()),
    this.urgent = const UrgencyTerms(
      additionalCharge: 50,
      completionTime: CompletionTime(3, CompletionTimeUnit.days),
    ),
    this.emergency = const UrgencyTerms(
      additionalCharge: 100,
      completionTime: CompletionTime(12, CompletionTimeUnit.hours),
    ),
  });

  /// Normal ₱10 / no time limit, Urgent ₱50 / 3 days, Emergency ₱100 / 12 hours.
  static const UrgencyPolicy defaults = UrgencyPolicy();

  final UrgencyTerms normal;
  final UrgencyTerms urgent;
  final UrgencyTerms emergency;

  /// The terms for an urgency as the mobile app names it. Unknown is Normal,
  /// the same default [PointsPolicy.pointsFor] applies.
  UrgencyTerms termsFor(String urgency) => switch (urgency) {
        'Emergency' => emergency,
        'Urgent' => urgent,
        _ => normal,
      };

  UrgencyPolicy withTerms(String urgency, UrgencyTerms terms) => switch (urgency) {
        'Emergency' => UrgencyPolicy(normal: normal, urgent: urgent, emergency: terms),
        'Urgent' => UrgencyPolicy(normal: normal, urgent: terms, emergency: emergency),
        _ => UrgencyPolicy(normal: terms, urgent: urgent, emergency: emergency),
      };

  bool get isValid => normal.isValid && urgent.isValid && emergency.isValid;

  Map<String, dynamic> toJson() => {
        'normal': normal.toJson(),
        'urgent': urgent.toJson(),
        'emergency': emergency.toJson(),
      };

  factory UrgencyPolicy.fromJson(Map<String, dynamic> json) => UrgencyPolicy(
        normal: UrgencyTerms.fromJson(readObject(json['normal']), defaults.normal),
        urgent: UrgencyTerms.fromJson(readObject(json['urgent']), defaults.urgent),
        emergency: UrgencyTerms.fromJson(readObject(json['emergency']), defaults.emergency),
      );

  @override
  bool operator ==(Object other) =>
      other is UrgencyPolicy && other.normal == normal && other.urgent == urgent && other.emergency == emergency;

  @override
  int get hashCode => Object.hash(normal, urgent, emergency);
}

/// An additional charge as it reads on screen: `₱10`, `₱12.50`.
String formatAdditionalCharge(double pesos) =>
    pesos.roundToDouble() == pesos ? formatPesos(pesos) : '₱${pesos.toStringAsFixed(2)}';
