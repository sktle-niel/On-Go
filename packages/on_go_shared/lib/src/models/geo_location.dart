import 'dart:math' as math;

import 'json.dart';

/// A position on the earth, in WGS84 degrees — what a phone's GPS reports and
/// what every map, geocoder and spatial database speaks.
class GeoPoint {
  final double latitude;
  final double longitude;

  const GeoPoint(this.latitude, this.longitude);

  /// A usable coordinate: finite, and on the planet.
  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180;

  /// Mean earth radius, the IUGG figure.
  static const double _earthRadiusMeters = 6371008.8;

  /// Straight-line (great-circle) distance to [other], in meters.
  ///
  /// Haversine. Well within 1% at the distances a mechanic's service radius
  /// deals in, which is all "is this job within 10 km" needs — and the same
  /// formula a backend can run in its own query, so the phone and the server
  /// agree on what "nearby" means.
  double distanceTo(GeoPoint other) {
    final lat1 = _radians(latitude);
    final lat2 = _radians(other.latitude);
    final dLat = lat2 - lat1;
    final dLng = _radians(other.longitude - longitude);
    final sinLat = math.sin(dLat / 2);
    final sinLng = math.sin(dLng / 2);
    final a = sinLat * sinLat + math.cos(lat1) * math.cos(lat2) * sinLng * sinLng;
    return 2 * _earthRadiusMeters * math.asin(math.min(1.0, math.sqrt(a)));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;

  Map<String, dynamic> toJson() => {'latitude': latitude, 'longitude': longitude};

  factory GeoPoint.fromJson(Map<String, dynamic> json) =>
      GeoPoint(readDouble(json['latitude']), readDouble(json['longitude']));

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.latitude == latitude && other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}

/// Where a location came from. Recorded on every update, because "the phone's
/// GPS said so a second ago" and "the client typed it" are not the same claim
/// and a backend matching jobs must be able to tell them apart.
enum LocationSource {
  /// A live fix from the device.
  gps,

  /// The device's last fix, reused because a fresh one could not be had.
  lastKnown,

  /// Chosen or typed by the user.
  manual;

  static LocationSource fromName(String name) =>
      values.firstWhere((v) => v.name == name, orElse: () => LocationSource.manual);
}

/// Which side of the marketplace a location belongs to.
enum LocationRole {
  client,
  mechanic;

  static LocationRole? fromName(String? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// Whether a mechanic can take a job right now. Only meaningful on a
/// mechanic's location — a backend matching nearby jobs skips anyone not
/// [available].
enum MechanicAvailability {
  available,
  onJob,
  offline;

  static MechanicAvailability? fromName(String? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// One location update — the unit a backend will receive and keep.
///
/// Built on the phone by `LocationService` from a real device fix, stamped
/// with who and what it is for by whichever screen sends it, and shaped so it
/// can cross the wire unchanged. The backend keeps the latest one per user;
/// for a mechanic, that stored update plus their service radius is what
/// nearby-job matching runs on.
class LocationUpdate {
  final GeoPoint point;

  /// When the device took the fix — not when it was sent.
  final DateTime recordedAt;

  /// The device's own estimate, in meters, or null when it gave none.
  final double? accuracyMeters;

  final LocationSource source;

  /// The account this belongs to. Null until accounts carry server-issued ids;
  /// the phone must never invent one.
  final String? userId;

  final LocationRole? role;

  /// Mechanics only.
  final MechanicAvailability? availability;

  const LocationUpdate({
    required this.point,
    required this.recordedAt,
    required this.source,
    this.accuracyMeters,
    this.userId,
    this.role,
    this.availability,
  });

  /// Worse than this, a fix is good enough to say which barangay someone is in
  /// but not good enough to say which street — worth telling the user.
  static const double poorAccuracyMeters = 100;

  bool get isPoorAccuracy => accuracyMeters != null && accuracyMeters! > poorAccuracyMeters;

  /// Older than [maxAge] at [now].
  bool isStale(Duration maxAge, {DateTime? now}) =>
      (now ?? DateTime.now()).difference(recordedAt) > maxAge;

  LocationUpdate copyWith({
    LocationSource? source,
    String? userId,
    LocationRole? role,
    MechanicAvailability? availability,
  }) =>
      LocationUpdate(
        point: point,
        recordedAt: recordedAt,
        accuracyMeters: accuracyMeters,
        source: source ?? this.source,
        userId: userId ?? this.userId,
        role: role ?? this.role,
        availability: availability ?? this.availability,
      );

  Map<String, dynamic> toJson() => {
        'point': point.toJson(),
        'recordedAt': writeDate(recordedAt),
        'accuracyMeters': accuracyMeters,
        'source': source.name,
        'userId': userId,
        'role': role?.name,
        'availability': availability?.name,
      };

  factory LocationUpdate.fromJson(Map<String, dynamic> json) => LocationUpdate(
        point: GeoPoint.fromJson(readObject(json['point'])),
        recordedAt: readDate(json['recordedAt']),
        accuracyMeters: json['accuracyMeters'] is num ? (json['accuracyMeters'] as num).toDouble() : null,
        source: LocationSource.fromName(readString(json['source'])),
        userId: readStringOrNull(json['userId']),
        role: LocationRole.fromName(readStringOrNull(json['role'])),
        availability: MechanicAvailability.fromName(readStringOrNull(json['availability'])),
      );
}

/// The circle a mechanic is willing to travel to.
class ServiceArea {
  final GeoPoint center;
  final double radiusKm;

  const ServiceArea({required this.center, required this.radiusKm});

  double distanceKmTo(GeoPoint point) => center.distanceTo(point) / 1000;

  /// Whether a job at [point] falls inside the circle. The edge counts as in.
  bool contains(GeoPoint point) => distanceKmTo(point) <= radiusKm;
}

/// THE nearby-job rule, written down before the backend that will run it.
///
/// A job is eligible for a mechanic when the mechanic can take work, their
/// last known location is real, and the job lies within their service radius
/// of it. The backend's query implements exactly this; keeping it here too
/// means the phone can explain a result, and tests pin the rule.
bool isJobWithinServiceRadius({
  required LocationUpdate mechanicLocation,
  required double serviceRadiusKm,
  required GeoPoint jobLocation,
}) {
  if (serviceRadiusKm <= 0) return false;
  if (!mechanicLocation.point.isValid || !jobLocation.isValid) return false;
  final availability = mechanicLocation.availability;
  if (availability != null && availability != MechanicAvailability.available) return false;
  return ServiceArea(center: mechanicLocation.point, radiusKm: serviceRadiusKm).contains(jobLocation);
}
