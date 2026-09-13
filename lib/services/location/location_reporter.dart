import 'dart:async';

import '../backend/mobile_backend.dart';
import 'location_service.dart';

/// Hands the signed-in user's live location to the backend seam.
///
/// The "saved last location → backend synchronization" step of the location
/// path. It listens to [LocationService] and forwards each meaningful move
/// through `MobileBackend.instance.location`, stamped with the user's role and,
/// for a mechanic, their availability. Today that lands in the local
/// implementation; when the backend is configured it lands on the server, and
/// nothing here or in any screen changes.
///
/// Throttled, so a phone jittering in place does not report every second: an
/// update goes out once the user has moved [minDistanceMeters] or
/// [minInterval] has passed since the last one sent.
///
/// It reports; it never reads GPS or starts tracking. Whoever owns the screen
/// decides whether location should be live.
class LocationReporter {
  LocationReporter({
    required this.role,
    this.availability,
    LocationService? service,
    LocationApi? api,
    this.minInterval = const Duration(seconds: 30),
    this.minDistanceMeters = 50,
  })  : _service = service,
        _api = api;

  final LocationRole role;

  /// Read at the moment of sending, so it is always current. Mechanics only.
  final MechanicAvailability? Function()? availability;

  final Duration minInterval;
  final double minDistanceMeters;

  final LocationService? _service;
  final LocationApi? _api;

  LocationService get _location => _service ?? LocationService.instance;

  // Resolved per send rather than captured, so a backend configured after this
  // reporter was created is still the one reported to.
  LocationApi get _backend => _api ?? MobileBackend.instance.location;

  LocationUpdate? _lastSeen;
  LocationUpdate? _lastSent;
  bool _running = false;

  /// The last update this reporter sent.
  LocationUpdate? get lastSent => _lastSent;

  void start() {
    if (_running) return;
    _running = true;
    _location.addListener(_onLocation);
    _onLocation();
  }

  void stop() {
    if (!_running) return;
    _running = false;
    _location.removeListener(_onLocation);
  }

  void _onLocation() {
    final update = _location.current;
    if (update == null || identical(update, _lastSeen)) return;
    _lastSeen = update;

    final previous = _lastSent;
    if (previous != null) {
      final moved = previous.point.distanceTo(update.point);
      final elapsed = update.recordedAt.difference(previous.recordedAt);
      if (moved < minDistanceMeters && elapsed < minInterval) return;
    }

    // No user id: accounts do not carry server-issued ids yet, and the phone
    // must not invent one. The backend attaches it from the session.
    final stamped = update.copyWith(role: role, availability: availability?.call());
    _lastSent = stamped;
    unawaited(_send(stamped));
  }

  Future<void> _send(LocationUpdate update) async {
    try {
      await _backend.reportLocation(update);
    } catch (_) {
      // A report that does not get through is retried by the next move; it
      // must never surface as a location failure on screen.
    }
  }
}
