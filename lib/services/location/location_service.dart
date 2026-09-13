import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:on_go_shared/on_go_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_location_provider.dart';

/// Where the app stands with location — one answer a screen can switch on.
enum LocationAccess {
  /// Not checked yet.
  unknown,

  /// The user has not been asked on this device.
  notDetermined,

  /// Asked, and declined. Asking again is allowed, but only when the user
  /// does something that needs location — never on its own.
  denied,

  /// Declined for good. Only the system settings can change it.
  deniedForever,

  /// Permission is granted, but location services are switched off.
  servicesDisabled,

  /// Granted, with services on.
  granted,
}

/// Why a location could not be had, in words a screen can show as they are.
enum LocationFailure {
  permissionDenied('Location permission is off. You can type your location instead, or turn it on.'),
  permissionDeniedForever(
      'Location permission is turned off for On Go. Turn it on in Settings, or type your location instead.'),
  servicesDisabled('Location services are off on this device. Turn them on, or type your location instead.'),
  timeout('Your location is taking too long to find. Try again in the open, or type your location instead.'),
  unavailable('Your location is unavailable right now. You can type your location instead.');

  const LocationFailure(this.message);
  final String message;
}

/// The outcome of asking for a location.
sealed class LocationResult {
  const LocationResult();
}

class LocationFound extends LocationResult {
  final LocationUpdate update;
  const LocationFound(this.update);
}

class LocationNotFound extends LocationResult {
  final LocationFailure failure;
  const LocationNotFound(this.failure);
}

/// THE location service — the one place the app decides where the user is.
///
/// Device location → [DeviceLocationProvider] → this service → screens →
/// (later) `LocationApi`. Screens never touch GPS or permissions themselves:
/// they call [locate], [startTracking] or [requestAccess], and listen here.
/// Both roles use this one instance; it knows nothing about clients or
/// mechanics, and screens stamp an update with who it belongs to when they
/// send it on.
///
/// While-in-use only: live updates pause when the app goes to the
/// background and resume when it returns, and permission is re-read on
/// return, so a change made in the system settings shows up immediately.
class LocationService extends ChangeNotifier with WidgetsBindingObserver {
  LocationService({DeviceLocationProvider? provider, bool persist = true})
      : _provider = provider ?? const GeolocatorLocationProvider(),
        _persist = persist;

  static LocationService _instance = LocationService();
  static LocationService get instance => _instance;

  /// Swaps the shared instance — for tests, which put a scripted device under
  /// the real service.
  @visibleForTesting
  static void debugSetInstance(LocationService service) => _instance = service;

  final DeviceLocationProvider _provider;
  final bool _persist;

  static const String _askedKey = 'location_permission_asked';
  static const String _lastKnownKey = 'location_last_known';

  /// How long to wait for a fix before giving up on this attempt.
  static const Duration fixTimeout = Duration(seconds: 15);

  /// How old the device's cached fix may be and still stand in for a fresh one
  /// when GPS is slow.
  static const Duration lastKnownMaxAge = Duration(minutes: 30);

  /// Live updates arrive when the device moves at least this far.
  static const int trackingDistanceMeters = 10;

  LocationAccess _access = LocationAccess.unknown;
  bool _askedBefore = false;
  bool _approximate = false;
  bool _locating = false;
  LocationUpdate? _current;
  LocationUpdate? _lastKnown;
  LocationFailure? _failure;

  int _trackers = 0;
  bool _foreground = true;
  bool _attached = false;
  StreamSubscription<DeviceFix>? _fixes;
  StreamSubscription<bool>? _serviceChanges;
  Future<LocationResult>? _inFlight;

  /// Set when the live stream failed. While set, the stream is not restarted
  /// on its own: if permission and services still look fine, restarting would
  /// just fail again, over and over, burning battery. It is cleared by
  /// anything that could genuinely change the outcome — the app returning to
  /// the front, location services being toggled, or a screen asking to track.
  bool _streamBroken = false;

  LocationAccess get access => _access;

  /// Whether the user has ever been shown the permission prompt on this device.
  bool get askedBefore => _askedBefore;

  /// Granted, but only approximately — good for a barangay, not a street.
  bool get isApproximate => _approximate;

  bool get isLocating => _locating;

  /// This session's latest live fix.
  LocationUpdate? get current => _current;

  /// The last fix this device took, kept across restarts.
  LocationUpdate? get lastKnown => _lastKnown;

  /// The best position available: live if there is one, else the last known.
  LocationUpdate? get bestKnown => _current ?? _lastKnown;

  /// Why the most recent attempt failed, cleared by the next success.
  LocationFailure? get failure => _failure;

  bool get isTracking => _fixes != null;

  // -------------------------------------------------------------- startup ---

  /// Restores what was saved and reads the current permission. Safe before
  /// `runApp`; nothing here can throw or prompt.
  Future<void> load() async {
    if (_persist) {
      try {
        final prefs = await SharedPreferences.getInstance();
        _askedBefore = prefs.getBool(_askedKey) ?? false;
        final raw = prefs.getString(_lastKnownKey);
        if (raw != null) {
          _lastKnown = LocationUpdate.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
        }
      } catch (_) {
        // Nothing saved, or unreadable — start fresh rather than block startup.
      }
    }
    _attach();
    await refreshAccess();
  }

  void _attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    _serviceChanges = _provider.serviceStatusChanges().listen(
          (_) {
            _streamBroken = false;
            refreshAccess();
          },
          onError: (Object _) {},
        );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        _streamBroken = false;
        // The user may have changed permission or services while away.
        refreshAccess();
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _foreground = false;
        _stopStream();
    }
  }

  // ----------------------------------------------------------- permission ---

  /// Re-reads permission and services from the device. Never prompts.
  Future<LocationAccess> refreshAccess() async {
    LocationAccess next;
    try {
      final permission = await _provider.checkPermission();
      final servicesOn = await _provider.isServiceEnabled();
      next = _accessFrom(permission, servicesOn);
      _approximate = next == LocationAccess.granted && await _provider.isApproximate();
    } catch (_) {
      next = LocationAccess.unknown;
    }
    _setAccess(next);
    return next;
  }

  LocationAccess _accessFrom(DevicePermission permission, bool servicesOn) {
    switch (permission) {
      case DevicePermission.whileInUse:
      case DevicePermission.always:
        return servicesOn ? LocationAccess.granted : LocationAccess.servicesDisabled;
      case DevicePermission.deniedForever:
        return LocationAccess.deniedForever;
      case DevicePermission.denied:
        return _askedBefore ? LocationAccess.denied : LocationAccess.notDetermined;
      case DevicePermission.unknown:
        return LocationAccess.unknown;
    }
  }

  void _setAccess(LocationAccess next) {
    final changed = next != _access;
    _access = next;
    if (next == LocationAccess.granted) {
      if (_trackers > 0) _startStream();
    } else {
      _stopStream();
    }
    if (changed) notifyListeners();
  }

  /// Shows the operating system's permission prompt — when asking can still
  /// change anything. A permanent denial, or services being off, cannot be
  /// fixed by a prompt, so those return straight away for the screen to offer
  /// the right settings page instead.
  Future<LocationAccess> requestAccess() async {
    final now = await refreshAccess();
    if (now == LocationAccess.granted ||
        now == LocationAccess.deniedForever ||
        now == LocationAccess.servicesDisabled) {
      return now;
    }
    try {
      await _provider.requestPermission();
    } on DeviceLocationException {
      // A prompt already on screen, or the platform refused — read the
      // outcome below either way.
    } catch (_) {}
    await _markAsked();
    return refreshAccess();
  }

  /// The first-sign-in prompt: asks once on this device, and never again on
  /// its own once the user has made a decision either way.
  Future<void> promptOnFirstUse() async {
    final now = await refreshAccess();
    if (now == LocationAccess.notDetermined) {
      await requestAccess();
    } else if (now != LocationAccess.unknown && !_askedBefore) {
      // Decided before this app ever asked (a restored install, a setting
      // flipped by hand). Respect it.
      await _markAsked();
    }
  }

  Future<void> _markAsked() async {
    if (_askedBefore) return;
    _askedBefore = true;
    if (!_persist) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_askedKey, true);
    } catch (_) {}
  }

  Future<bool> openAppSettings() => _provider.openAppSettings();

  Future<bool> openLocationSettings() => _provider.openLocationSettings();

  /// Opens whichever settings page can fix [access]: the device's location
  /// switch when services are off, the app's permissions otherwise.
  Future<bool> openSettingsFor(LocationAccess access) =>
      access == LocationAccess.servicesDisabled ? openLocationSettings() : openAppSettings();

  // ------------------------------------------------------------- locating ---

  /// One location, now. Asks for permission first when [requestIfNeeded] and
  /// asking could help. Calls made while one is already running share it.
  Future<LocationResult> locate({bool requestIfNeeded = true}) =>
      _inFlight ??= _locate(requestIfNeeded).whenComplete(() => _inFlight = null);

  Future<LocationResult> _locate(bool requestIfNeeded) async {
    _locating = true;
    notifyListeners();
    try {
      final access = requestIfNeeded ? await requestAccess() : await refreshAccess();
      switch (access) {
        case LocationAccess.granted:
          break;
        case LocationAccess.notDetermined:
        case LocationAccess.denied:
          return _fail(LocationFailure.permissionDenied);
        case LocationAccess.deniedForever:
          return _fail(LocationFailure.permissionDeniedForever);
        case LocationAccess.servicesDisabled:
          return _fail(LocationFailure.servicesDisabled);
        case LocationAccess.unknown:
          return _fail(LocationFailure.unavailable);
      }

      try {
        final fix = await _provider.currentFix(timeLimit: fixTimeout);
        return LocationFound(_accept(fix, LocationSource.gps));
      } on DeviceLocationException catch (e) {
        switch (e.kind) {
          case DeviceLocationErrorKind.servicesDisabled:
            await refreshAccess();
            return _fail(LocationFailure.servicesDisabled);
          case DeviceLocationErrorKind.permissionDenied:
            await refreshAccess();
            return _fail(_access == LocationAccess.deniedForever
                ? LocationFailure.permissionDeniedForever
                : LocationFailure.permissionDenied);
          case DeviceLocationErrorKind.timeout:
          case DeviceLocationErrorKind.requestInProgress:
          case DeviceLocationErrorKind.unavailable:
            // GPS is slow or briefly out — a recent cached fix is still a real
            // location, and says so in its source.
            final cached = await _provider.lastKnownFix();
            if (cached != null &&
                DateTime.now().difference(cached.timestamp) <= lastKnownMaxAge) {
              return LocationFound(_accept(cached, LocationSource.lastKnown));
            }
            return _fail(e.kind == DeviceLocationErrorKind.timeout
                ? LocationFailure.timeout
                : LocationFailure.unavailable);
        }
      }
    } catch (_) {
      return _fail(LocationFailure.unavailable);
    } finally {
      _locating = false;
      notifyListeners();
    }
  }

  LocationNotFound _fail(LocationFailure failure) {
    _failure = failure;
    return LocationNotFound(failure);
  }

  LocationUpdate _accept(DeviceFix fix, LocationSource source) {
    final update = LocationUpdate(
      point: GeoPoint(fix.latitude, fix.longitude),
      recordedAt: fix.timestamp,
      accuracyMeters: fix.accuracyMeters,
      source: source,
    );
    if (!update.point.isValid) throw const DeviceLocationException(DeviceLocationErrorKind.unavailable);
    _current = update;
    _lastKnown = update;
    _failure = null;
    notifyListeners();
    _saveLastKnown(update);
    return update;
  }

  Future<void> _saveLastKnown(LocationUpdate update) async {
    if (!_persist) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastKnownKey, jsonEncode(update.toJson()));
    } catch (_) {}
  }

  // ------------------------------------------------------------- tracking ---

  /// Keeps [current] moving while the app is in use. Reference-counted: every
  /// caller that starts tracking stops it once, so two screens can both need
  /// it without one switching it off under the other.
  ///
  /// Never prompts. Returns whether live updates are running.
  Future<bool> startTracking() async {
    _trackers++;
    // A screen asking is a fresh attempt, even after a failure.
    _streamBroken = false;
    final access = await refreshAccess();
    if (access == LocationAccess.granted) _startStream();
    return isTracking;
  }

  void stopTracking() {
    if (_trackers == 0) return;
    _trackers--;
    if (_trackers == 0) _stopStream();
  }

  void _startStream() {
    if (_fixes != null || _streamBroken || !_foreground || _access != LocationAccess.granted) return;
    _fixes = _provider.fixes(distanceFilterMeters: trackingDistanceMeters).listen(
      (fix) {
        try {
          _accept(fix, LocationSource.gps);
        } catch (_) {
          // A nonsense coordinate is dropped, not believed.
        }
      },
      onError: (Object error) {
        _streamBroken = true;
        _stopStream();
        _failure = error is DeviceLocationException &&
                error.kind == DeviceLocationErrorKind.servicesDisabled
            ? LocationFailure.servicesDisabled
            : LocationFailure.unavailable;
        notifyListeners();
        refreshAccess();
      },
      cancelOnError: true,
    );
    notifyListeners();
  }

  void _stopStream() {
    final subscription = _fixes;
    if (subscription == null) return;
    _fixes = null;
    subscription.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _stopStream();
    _serviceChanges?.cancel();
    if (_attached) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
