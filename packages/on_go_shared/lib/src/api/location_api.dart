import '../models/geo_location.dart';

/// Locations: reported by the phone, kept and matched by the backend.
///
/// The phone's own position is decided on the phone — by the device's GPS,
/// through `LocationService` — and nothing here reads GPS. This contract is
/// only the hand-off: what the phone sends when the backend exists, and the
/// questions only a backend holding everyone's last location can answer.
///
/// The path is Device location → LocationService → screens → this API. The
/// screens already hold [LocationUpdate]s shaped for the wire, so connecting a
/// server is an implementation of this interface, not a redesign.
abstract interface class LocationApi {
  /// Records the signed-in user's latest location. Mobile → backend.
  ///
  /// The backend keeps the most recent update per user. For a mechanic, that
  /// stored update — their last known location — is what nearby-job matching
  /// reads, so it goes on working while their phone is briefly out of signal.
  Future<void> reportLocation(LocationUpdate update);

  /// The last location [userId] reported, or null if they never have.
  Future<LocationUpdate?> fetchLastKnown(String userId);

  /// Open jobs within [serviceRadiusKm] of [mechanicId]'s last known location,
  /// by the rule in `isJobWithinServiceRadius`.
  ///
  /// Needs every job's location and every mechanic's, which only a server
  /// holds — a phone implementation cannot answer it honestly.
  Future<List<String>> findNearbyJobIds({
    required String mechanicId,
    required double serviceRadiusKm,
  });
}
