import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// What the operating system says about location permission, in the app's
/// own words.
///
/// Neither Android nor iOS reports "never asked" distinctly — both answer
/// [denied] until the user decides. Whether the user has been asked is
/// tracked by `LocationService` itself.
enum DevicePermission { denied, deniedForever, whileInUse, always, unknown }

/// One raw fix from the device.
class DeviceFix {
  final double latitude;
  final double longitude;

  /// The device's estimate, in meters.
  final double accuracyMeters;

  final DateTime timestamp;

  const DeviceFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
  });
}

enum DeviceLocationErrorKind {
  servicesDisabled,
  permissionDenied,
  timeout,
  requestInProgress,
  unavailable,
}

/// Every failure the device layer can report, already sorted — so nothing
/// above this file has to know which plugin threw what.
class DeviceLocationException implements Exception {
  final DeviceLocationErrorKind kind;
  final Object? cause;

  const DeviceLocationException(this.kind, [this.cause]);

  @override
  String toString() => 'DeviceLocationException(${kind.name}${cause == null ? '' : ': $cause'})';
}

/// The device's location hardware and permission system, and nothing else.
///
/// The ONLY place the location plugin is used. `LocationService` works
/// through this interface, which keeps the plugin out of every screen and
/// lets tests put a scripted device underneath the real service.
abstract interface class DeviceLocationProvider {
  Future<bool> isServiceEnabled();

  /// Emits whenever location services are switched on (true) or off (false).
  /// Platforms that cannot report it simply never emit.
  Stream<bool> serviceStatusChanges();

  Future<DevicePermission> checkPermission();

  /// Shows the operating system's own permission prompt.
  Future<DevicePermission> requestPermission();

  /// True when the user granted only approximate location.
  Future<bool> isApproximate();

  /// A fresh fix. Throws [DeviceLocationException] on any failure.
  Future<DeviceFix> currentFix({required Duration timeLimit});

  /// The last fix the OS cached, or null.
  Future<DeviceFix?> lastKnownFix();

  /// Fixes as the device moves at least [distanceFilterMeters]. Errors arrive
  /// on the stream as [DeviceLocationException].
  Stream<DeviceFix> fixes({required int distanceFilterMeters});

  Future<bool> openAppSettings();

  Future<bool> openLocationSettings();
}

/// [DeviceLocationProvider] backed by the geolocator plugin.
class GeolocatorLocationProvider implements DeviceLocationProvider {
  const GeolocatorLocationProvider();

  static DevicePermission _permission(LocationPermission p) => switch (p) {
        LocationPermission.denied => DevicePermission.denied,
        LocationPermission.deniedForever => DevicePermission.deniedForever,
        LocationPermission.whileInUse => DevicePermission.whileInUse,
        LocationPermission.always => DevicePermission.always,
        LocationPermission.unableToDetermine => DevicePermission.unknown,
      };

  static DeviceFix _fix(Position p) => DeviceFix(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracyMeters: p.accuracy,
        timestamp: p.timestamp,
      );

  static DeviceLocationException _translate(Object error) {
    if (error is DeviceLocationException) return error;
    if (error is LocationServiceDisabledException) {
      return DeviceLocationException(DeviceLocationErrorKind.servicesDisabled, error);
    }
    if (error is PermissionDeniedException) {
      return DeviceLocationException(DeviceLocationErrorKind.permissionDenied, error);
    }
    if (error is PermissionRequestInProgressException) {
      return DeviceLocationException(DeviceLocationErrorKind.requestInProgress, error);
    }
    if (error is TimeoutException) {
      return DeviceLocationException(DeviceLocationErrorKind.timeout, error);
    }
    return DeviceLocationException(DeviceLocationErrorKind.unavailable, error);
  }

  @override
  Future<bool> isServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<bool> serviceStatusChanges() {
    try {
      return Geolocator.getServiceStatusStream()
          .map((status) => status == ServiceStatus.enabled)
          .handleError((Object _) {});
    } catch (_) {
      return const Stream<bool>.empty();
    }
  }

  @override
  Future<DevicePermission> checkPermission() async {
    try {
      return _permission(await Geolocator.checkPermission());
    } catch (_) {
      return DevicePermission.unknown;
    }
  }

  @override
  Future<DevicePermission> requestPermission() async {
    try {
      return _permission(await Geolocator.requestPermission());
    } catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<bool> isApproximate() async {
    try {
      return await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.reduced;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<DeviceFix> currentFix({required Duration timeLimit}) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: timeLimit),
      );
      return _fix(position);
    } catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<DeviceFix?> lastKnownFix() async {
    try {
      final position = await Geolocator.getLastKnownPosition();
      return position == null ? null : _fix(position);
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<DeviceFix> fixes({required int distanceFilterMeters}) {
    try {
      return Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilterMeters,
        ),
      ).map(_fix).handleError((Object e) => throw _translate(e));
    } catch (e) {
      return Stream<DeviceFix>.error(_translate(e));
    }
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (_) {
      return false;
    }
  }
}
