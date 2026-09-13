import 'package:on_go_shared/on_go_shared.dart';

/// This device's end of [LocationApi], until there is a server to send to.
///
/// [reportLocation] keeps the most recent update reported from this device, in
/// memory — the same honest shape as `LocalRevenueService`: the call site
/// behaves exactly as it will on the day it goes over the wire, and nothing
/// pretends a server received anything. Nothing is written to disk here; the
/// device's own last fix is `LocationService`'s to keep.
///
/// [findNearbyJobIds] refuses. Matching needs every open job's location and
/// every mechanic's, and only a backend holds those.
class LocalLocationService implements LocationApi {
  final Map<String, LocationUpdate> _latestByUser = {};
  LocationUpdate? _latest;

  /// The most recent update reported from this device, whoever it was for —
  /// for inspecting the seam while debugging.
  LocationUpdate? get latestReported => _latest;

  @override
  Future<void> reportLocation(LocationUpdate update) async {
    _latest = update;
    final userId = update.userId;
    if (userId != null && userId.isNotEmpty) _latestByUser[userId] = update;
  }

  @override
  Future<LocationUpdate?> fetchLastKnown(String userId) async => _latestByUser[userId];

  @override
  Future<List<String>> findNearbyJobIds({
    required String mechanicId,
    required double serviceRadiusKm,
  }) =>
      Future.error(const ApiException.unsupported(
        'Finding nearby jobs needs the On Go backend, which holds every job\'s and mechanic\'s location.',
      ));
}
