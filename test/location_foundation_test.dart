import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_go/services/backend/local_location_service.dart';
import 'package:on_go/services/location/device_location_provider.dart';
import 'package:on_go/services/location/location_reporter.dart';
import 'package:on_go/services/location/location_service.dart';
import 'package:on_go/services/location/place_suggestions.dart';
import 'package:on_go_shared/on_go_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A scripted device. It stands in for the phone's GPS and permission system
/// — the one thing a test cannot drive — underneath the REAL LocationService.
class FakeDevice implements DeviceLocationProvider {
  DevicePermission permission = DevicePermission.denied;

  /// What the user picks when the operating system's prompt is shown.
  DevicePermission? userChoice;

  bool servicesOn = true;
  bool approximate = false;
  int prompts = 0;
  String? openedSettings;

  DeviceFix? nextFix;
  DeviceLocationException? fixError;
  DeviceFix? cachedFix;

  final fixStream = StreamController<DeviceFix>.broadcast();
  final serviceStream = StreamController<bool>.broadcast();
  int liveListeners = 0;

  FakeDevice() {
    fixStream.onListen = () => liveListeners++;
    fixStream.onCancel = () => liveListeners--;
  }

  @override
  Future<bool> isServiceEnabled() async => servicesOn;

  @override
  Stream<bool> serviceStatusChanges() => serviceStream.stream;

  @override
  Future<DevicePermission> checkPermission() async => permission;

  @override
  Future<DevicePermission> requestPermission() async {
    prompts++;
    if (userChoice != null) permission = userChoice!;
    return permission;
  }

  @override
  Future<bool> isApproximate() async => approximate;

  @override
  Future<DeviceFix> currentFix({required Duration timeLimit}) async {
    if (fixError != null) throw fixError!;
    return nextFix!;
  }

  @override
  Future<DeviceFix?> lastKnownFix() async => cachedFix;

  @override
  Stream<DeviceFix> fixes({required int distanceFilterMeters}) => fixStream.stream;

  @override
  Future<bool> openAppSettings() async {
    openedSettings = 'app';
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    openedSettings = 'location';
    return true;
  }
}

DeviceFix _fix(double lat, double lng, {double accuracy = 12, DateTime? at}) =>
    DeviceFix(latitude: lat, longitude: lng, accuracyMeters: accuracy, timestamp: at ?? DateTime.now());

/// Puerto Princesa City, Palawan.
const _pp = GeoPoint(9.7392, 118.7353);

/// Roughly 6 km due north of [_pp]: one degree of latitude is ~111.2 km.
final _sixKmNorth = GeoPoint(_pp.latitude + 6 / 111.195, _pp.longitude);

class _RecordingApi implements LocationApi {
  final reports = <LocationUpdate>[];

  @override
  Future<void> reportLocation(LocationUpdate update) async => reports.add(update);

  @override
  Future<LocationUpdate?> fetchLastKnown(String userId) async => null;

  @override
  Future<List<String>> findNearbyJobIds({required String mechanicId, required double serviceRadiusKm}) async =>
      const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeDevice device;
  final services = <LocationService>[];

  LocationService newService({bool persist = false}) {
    final s = LocationService(provider: device, persist: persist);
    services.add(s);
    return s;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    device = FakeDevice();
  });

  tearDown(() {
    for (final s in services) {
      s.dispose();
    }
    services.clear();
  });

  // ---------------------------------------------------------------------
  // Permission
  // ---------------------------------------------------------------------

  group('permission', () {
    test('never asked: reported as not determined, and the first-use prompt asks once', () async {
      final service = newService();
      expect(await service.refreshAccess(), LocationAccess.notDetermined);

      device.userChoice = DevicePermission.whileInUse;
      await service.promptOnFirstUse();

      expect(device.prompts, 1);
      expect(service.access, LocationAccess.granted);
      expect(service.askedBefore, isTrue);
    });

    test('a decision is respected on the next launch — no second prompt', () async {
      final first = newService(persist: true);
      await first.load();
      device.userChoice = DevicePermission.denied;
      await first.promptOnFirstUse();
      expect(device.prompts, 1);
      expect(first.access, LocationAccess.denied);

      // The app is reopened.
      final second = newService(persist: true);
      await second.load();
      await second.promptOnFirstUse();

      expect(device.prompts, 1, reason: 'the user already decided; asking again on launch is nagging');
      expect(second.access, LocationAccess.denied);
    });

    test('permission already granted before the app ever asked is not asked for', () async {
      device.permission = DevicePermission.whileInUse;
      final service = newService();
      await service.promptOnFirstUse();
      expect(device.prompts, 0);
      expect(service.access, LocationAccess.granted);
      expect(service.askedBefore, isTrue);
    });

    test('denied once: tapping for location may ask again; it is the user acting', () async {
      final service = newService();
      device.userChoice = DevicePermission.denied;
      await service.promptOnFirstUse();

      device.userChoice = DevicePermission.whileInUse;
      await service.requestAccess();
      expect(device.prompts, 2);
      expect(service.access, LocationAccess.granted);
    });

    test('denied permanently: no prompt, the app settings page instead', () async {
      device.permission = DevicePermission.deniedForever;
      final service = newService();

      expect(await service.requestAccess(), LocationAccess.deniedForever);
      expect(device.prompts, 0);

      final result = await service.locate();
      expect((result as LocationNotFound).failure, LocationFailure.permissionDeniedForever);

      await service.openSettingsFor(service.access);
      expect(device.openedSettings, 'app');
    });

    test('GPS switched off: no prompt, the location settings page instead', () async {
      device.permission = DevicePermission.whileInUse;
      device.servicesOn = false;
      final service = newService();

      expect(await service.requestAccess(), LocationAccess.servicesDisabled);
      expect(device.prompts, 0);

      final result = await service.locate();
      expect((result as LocationNotFound).failure, LocationFailure.servicesDisabled);

      await service.openSettingsFor(service.access);
      expect(device.openedSettings, 'location');
    });

    test('changed in system settings while away: picked up when the app returns', () async {
      device.permission = DevicePermission.whileInUse;
      final service = newService();
      await service.load();
      expect(service.access, LocationAccess.granted);

      device.permission = DevicePermission.deniedForever;
      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();

      expect(service.access, LocationAccess.deniedForever);
    });

    test('GPS toggled from the quick settings: picked up without reopening', () async {
      device.permission = DevicePermission.whileInUse;
      final service = newService();
      await service.load();

      device.servicesOn = false;
      device.serviceStream.add(false);
      await pumpEventQueue();

      expect(service.access, LocationAccess.servicesDisabled);
    });
  });

  // ---------------------------------------------------------------------
  // Getting a location
  // ---------------------------------------------------------------------

  group('locating', () {
    setUp(() => device.permission = DevicePermission.whileInUse);

    test('a real fix becomes the current and last known location', () async {
      device.nextFix = _fix(_pp.latitude, _pp.longitude, accuracy: 8);
      final service = newService();

      final result = await service.locate();

      final update = (result as LocationFound).update;
      expect(update.point, _pp);
      expect(update.accuracyMeters, 8);
      expect(update.source, LocationSource.gps);
      expect(service.current, update);
      expect(service.lastKnown, update);
      expect(service.failure, isNull);
    });

    test('slow GPS: a recent cached fix stands in, and says it is not live', () async {
      device.fixError = const DeviceLocationException(DeviceLocationErrorKind.timeout);
      device.cachedFix = _fix(_pp.latitude, _pp.longitude, at: DateTime.now().subtract(const Duration(minutes: 5)));
      final service = newService();

      final result = await service.locate();
      expect((result as LocationFound).update.source, LocationSource.lastKnown);
    });

    test('slow GPS and nothing recent cached: a timeout, not a crash', () async {
      device.fixError = const DeviceLocationException(DeviceLocationErrorKind.timeout);
      device.cachedFix = _fix(_pp.latitude, _pp.longitude, at: DateTime.now().subtract(const Duration(hours: 3)));
      final service = newService();

      final result = await service.locate();
      expect((result as LocationNotFound).failure, LocationFailure.timeout);
      expect(service.failure, LocationFailure.timeout);
    });

    test('GPS unavailable: reported, never thrown', () async {
      device.fixError = const DeviceLocationException(DeviceLocationErrorKind.unavailable);
      final service = newService();
      final result = await service.locate();
      expect((result as LocationNotFound).failure, LocationFailure.unavailable);
    });

    test('a nonsense coordinate is not believed', () async {
      device.nextFix = _fix(999, 999);
      final service = newService();
      final result = await service.locate();
      expect(result, isA<LocationNotFound>());
      expect(service.current, isNull);
    });

    test('poor accuracy is flagged on the update', () async {
      device.nextFix = _fix(_pp.latitude, _pp.longitude, accuracy: 250);
      final service = newService();
      final update = ((await service.locate()) as LocationFound).update;
      expect(update.isPoorAccuracy, isTrue);
    });

    test('approximate-only permission is visible to screens', () async {
      device.approximate = true;
      final service = newService();
      await service.refreshAccess();
      expect(service.isApproximate, isTrue);
    });

    test('the last known location survives the app being reopened', () async {
      device.nextFix = _fix(_pp.latitude, _pp.longitude);
      final first = newService(persist: true);
      await first.load();
      await first.locate();

      final second = newService(persist: true);
      await second.load();
      expect(second.lastKnown?.point, _pp);
      expect(second.current, isNull, reason: 'a saved fix is last known, not live');
      expect(second.bestKnown?.point, _pp);
    });

    test('two callers asking at once share one fix', () async {
      device.nextFix = _fix(_pp.latitude, _pp.longitude);
      final service = newService();
      final results = await Future.wait([service.locate(), service.locate()]);
      expect((results[0] as LocationFound).update, same((results[1] as LocationFound).update));
    });
  });

  // ---------------------------------------------------------------------
  // Live tracking
  // ---------------------------------------------------------------------

  group('tracking', () {
    setUp(() => device.permission = DevicePermission.whileInUse);

    test('updates flow while tracking, and stop only when every caller stops', () async {
      final service = newService();
      expect(await service.startTracking(), isTrue);
      await service.startTracking(); // a second screen

      device.fixStream.add(_fix(_pp.latitude, _pp.longitude));
      await pumpEventQueue();
      expect(service.current?.point, _pp);

      service.stopTracking();
      expect(service.isTracking, isTrue, reason: 'the other screen still needs it');
      service.stopTracking();
      expect(service.isTracking, isFalse);
      expect(device.liveListeners, 0);
    });

    test('never prompts, and stays off when permission is missing', () async {
      device.permission = DevicePermission.denied;
      final service = newService();
      expect(await service.startTracking(), isFalse);
      expect(device.prompts, 0);
    });

    test('pauses in the background, resumes when back in use', () async {
      final service = newService();
      await service.load();
      await service.startTracking();
      expect(service.isTracking, isTrue);

      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(service.isTracking, isFalse);

      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(service.isTracking, isTrue);
    });

    test('a failure mid-stream stops tracking and says why', () async {
      final service = newService();
      await service.startTracking();
      device.fixStream.addError(const DeviceLocationException(DeviceLocationErrorKind.servicesDisabled));
      await pumpEventQueue();
      expect(service.isTracking, isFalse);
      expect(service.failure, LocationFailure.servicesDisabled);
    });

    test('a broken stream is not restarted in a loop, but the next request retries it', () async {
      final service = newService();
      await service.startTracking();

      // Permission and services still look fine — which is exactly when an
      // automatic restart would fail again and spin.
      device.fixStream.addError(const DeviceLocationException(DeviceLocationErrorKind.unavailable));
      await pumpEventQueue();
      expect(service.isTracking, isFalse);
      expect(device.liveListeners, 0);

      await service.startTracking();
      expect(service.isTracking, isTrue);
    });

    test('a broken stream comes back when the app returns to the front', () async {
      final service = newService();
      await service.load();
      await service.startTracking();
      device.fixStream.addError(const DeviceLocationException(DeviceLocationErrorKind.unavailable));
      await pumpEventQueue();
      expect(service.isTracking, isFalse);

      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(service.isTracking, isTrue);
    });
  });

  // ---------------------------------------------------------------------
  // Toward the backend
  // ---------------------------------------------------------------------

  group('backend readiness', () {
    test('a location update survives the wire unchanged', () {
      final update = LocationUpdate(
        point: _pp,
        recordedAt: DateTime.utc(2026, 9, 13, 8, 30),
        accuracyMeters: 14.5,
        source: LocationSource.gps,
        userId: 'm-42',
        role: LocationRole.mechanic,
        availability: MechanicAvailability.available,
      );
      final back = LocationUpdate.fromJson(update.toJson());
      expect(back.point, update.point);
      expect(back.recordedAt, update.recordedAt);
      expect(back.accuracyMeters, 14.5);
      expect(back.source, LocationSource.gps);
      expect(back.userId, 'm-42');
      expect(back.role, LocationRole.mechanic);
      expect(back.availability, MechanicAvailability.available);
    });

    test('distance is right at country scale', () {
      const manila = GeoPoint(14.5995, 120.9842);
      const cebuCity = GeoPoint(10.3157, 123.8854);
      final km = manila.distanceTo(cebuCity) / 1000;
      expect(km, inInclusiveRange(560, 580));
    });

    test('the nearby-job rule: 6 km away is inside a 10 km radius, outside a 5 km one', () {
      final mechanic = LocationUpdate(
        point: _pp,
        recordedAt: DateTime.now(),
        source: LocationSource.gps,
        role: LocationRole.mechanic,
        availability: MechanicAvailability.available,
      );
      expect(isJobWithinServiceRadius(mechanicLocation: mechanic, serviceRadiusKm: 10, jobLocation: _sixKmNorth), isTrue);
      expect(isJobWithinServiceRadius(mechanicLocation: mechanic, serviceRadiusKm: 5, jobLocation: _sixKmNorth), isFalse);
    });

    test('a mechanic on a job or offline is not matched, whatever the distance', () {
      for (final availability in [MechanicAvailability.onJob, MechanicAvailability.offline]) {
        final mechanic = LocationUpdate(
          point: _pp,
          recordedAt: DateTime.now(),
          source: LocationSource.gps,
          availability: availability,
        );
        expect(isJobWithinServiceRadius(mechanicLocation: mechanic, serviceRadiusKm: 10, jobLocation: _pp), isFalse);
      }
    });

    test('reporter: stamps the role and availability, and does not flood', () async {
      device.permission = DevicePermission.whileInUse;
      final service = newService();
      final api = _RecordingApi();
      final reporter = LocationReporter(
        role: LocationRole.mechanic,
        availability: () => MechanicAvailability.available,
        service: service,
        api: api,
      )..start();

      final t0 = DateTime.now();
      device.nextFix = _fix(_pp.latitude, _pp.longitude, at: t0);
      await service.locate();
      await pumpEventQueue();
      expect(api.reports, hasLength(1));
      expect(api.reports.single.role, LocationRole.mechanic);
      expect(api.reports.single.availability, MechanicAvailability.available);

      // Ten meters, five seconds later: jitter, not a move.
      device.nextFix = _fix(_pp.latitude + 10 / 111195, _pp.longitude, at: t0.add(const Duration(seconds: 5)));
      await service.locate();
      await pumpEventQueue();
      expect(api.reports, hasLength(1));

      // Two hundred meters away: a real move.
      device.nextFix = _fix(_pp.latitude + 200 / 111195, _pp.longitude, at: t0.add(const Duration(seconds: 10)));
      await service.locate();
      await pumpEventQueue();
      expect(api.reports, hasLength(2));

      reporter.stop();
    });

    test('on the phone, matching nearby jobs honestly needs the backend', () async {
      final api = LocalLocationService();
      await expectLater(
        api.findNearbyJobIds(mechanicId: 'm-42', serviceRadiusKm: 10),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.unsupported)),
      );
    });
  });

  // ---------------------------------------------------------------------
  // Suggestions
  // ---------------------------------------------------------------------

  group('suggestions', () {
    // A fixture, not app data: just enough of the hierarchy to test ordering.
    const mimaropa = Place(id: 'r17', name: 'MIMAROPA Region', level: PlaceLevel.region);
    const centralVisayas = Place(id: 'r07', name: 'Central Visayas', level: PlaceLevel.region);
    const ncr = Place(id: 'r13', name: 'National Capital Region', level: PlaceLevel.region);
    const palawan = Place(id: 'p-pal', name: 'Palawan', level: PlaceLevel.province, region: 'MIMAROPA Region');
    const cebu = Place(id: 'p-ceb', name: 'Cebu', level: PlaceLevel.province, region: 'Central Visayas');
    const occMindoro =
        Place(id: 'p-occ', name: 'Occidental Mindoro', level: PlaceLevel.province, region: 'MIMAROPA Region');
    const puertoPrincesa = Place(
        id: 'c-pp',
        name: 'Puerto Princesa City',
        level: PlaceLevel.cityMunicipality,
        province: 'Palawan',
        region: 'MIMAROPA Region');
    const roxas = Place(
        id: 'c-rox', name: 'Roxas', level: PlaceLevel.cityMunicipality, province: 'Palawan', region: 'MIMAROPA Region');
    const cebuCity = Place(
        id: 'c-ceb', name: 'Cebu City', level: PlaceLevel.cityMunicipality, province: 'Cebu', region: 'Central Visayas');
    const sanJoseMindoro = Place(
        id: 'c-sjm',
        name: 'San Jose',
        level: PlaceLevel.cityMunicipality,
        province: 'Occidental Mindoro',
        region: 'MIMAROPA Region');
    const manila = Place(
        id: 'c-mnl', name: 'Manila', level: PlaceLevel.cityMunicipality, region: 'National Capital Region');
    const makati = Place(
        id: 'c-mkt', name: 'Makati', level: PlaceLevel.cityMunicipality, region: 'National Capital Region');

    Place brgy(String id, String name, Place city) => Place(
          id: id,
          name: name,
          level: PlaceLevel.barangay,
          cityMunicipality: city.name,
          province: city.province,
          region: city.region,
        );

    final sanPedroPP = brgy('b1', 'San Pedro', puertoPrincesa);
    final sanJosePP = brgy('b2', 'San Jose', puertoPrincesa);
    final sanMiguelPP = brgy('b3', 'San Miguel', puertoPrincesa);
    final bancaoPP = brgy('b4', 'Bancao-Bancao', puertoPrincesa);
    final staNinoPP = brgy('b5', 'Sta. Niño', puertoPrincesa);
    final sanJoseRoxas = brgy('b6', 'San Jose', roxas);
    final cebuanoRoxas = brgy('b7', 'Cebuano', roxas);
    final sanJuanCebu = brgy('b8', 'San Juan', cebuCity);

    final all = <Place>[
      mimaropa, centralVisayas, ncr, palawan, cebu, occMindoro,
      puertoPrincesa, roxas, cebuCity, sanJoseMindoro, manila, makati,
      sanPedroPP, sanJosePP, sanMiguelPP, bancaoPP, staNinoPP,
      sanJoseRoxas, cebuanoRoxas, sanJuanCebu,
    ];

    test('nothing typed: the user\'s barangay, then around it, broadening out', () {
      final list = PlaceSuggestions.around(candidates: all, anchor: sanPedroPP);
      expect(list.map((p) => p.id).toList(), [
        'b1', // San Pedro — where they are
        'b4', 'b2', 'b3', 'b5', // other barangays in Puerto Princesa, alphabetical
        'c-pp', // their city
        'c-rox', // the other city in Palawan
        'p-pal', // their province
        'r17', // their region
      ]);
      expect(list, isNot(contains(sanJoseRoxas)), reason: 'a barangay in another city is not "near"');
      expect(list, isNot(contains(cebu)));
    });

    test('typing "San": matching names, the nearest first', () {
      final list = PlaceSuggestions.search(query: 'San', candidates: all, anchor: sanPedroPP);
      expect(list.map((p) => p.id).toList(), [
        'b1', // San Pedro, their own barangay
        'b2', 'b3', // San Jose, San Miguel — same city
        'b6', // San Jose, Roxas — same province
        'c-sjm', // San Jose, Occidental Mindoro — same region
        'b8', // San Juan, Cebu City — elsewhere
      ]);
    });

    test('typing "Cebu" in Palawan: Cebu first, not the Palawan place that merely contains it', () {
      final ids = PlaceSuggestions.search(query: 'Cebu', candidates: all, anchor: sanPedroPP)
          .map((p) => p.id)
          .toList();
      expect(ids.indexOf('p-ceb'), 0);
      expect(ids.indexOf('c-ceb'), lessThan(ids.indexOf('b7')),
          reason: 'Cebu City is a whole-word match; "Cebuano" only starts with the letters');
    });

    test('accents and "Brgy." do not get in the way', () {
      expect(PlaceSuggestions.search(query: 'sta nino', candidates: all, anchor: sanPedroPP).first, staNinoPP);
      expect(PlaceSuggestions.search(query: 'Brgy. San Pedro', candidates: all).first, sanPedroPP);
    });

    test('a search across levels narrows to the right namesake', () {
      final list = PlaceSuggestions.search(query: 'san jose roxas', candidates: all, anchor: sanPedroPP);
      expect(list.first, sanJoseRoxas);
      expect(list, isNot(contains(sanJosePP)));
    });

    test('no matches is an empty list', () {
      expect(PlaceSuggestions.search(query: 'zzzz', candidates: all, anchor: sanPedroPP), isEmpty);
    });

    test('no anchor: typed search still works, ordered by match then level', () {
      final list = PlaceSuggestions.search(query: 'san jose', candidates: all);
      expect(list.first.level, PlaceLevel.barangay);
      expect(list.map((p) => p.id), containsAll(['b2', 'b6', 'c-sjm']));
    });

    test('Metro Manila cities, which have no province, are neighbours by region', () {
      final list = PlaceSuggestions.around(candidates: all, anchor: manila);
      expect(list.first, manila);
      expect(list, contains(makati));
    });

    test('duplicates from a source are shown once', () {
      final list = PlaceSuggestions.search(query: 'san pedro', candidates: [...all, sanPedroPP, sanPedroPP]);
      expect(list.where((p) => p == sanPedroPP), hasLength(1));
    });

    test('labels tell namesakes apart', () {
      expect(sanJosePP.label, 'San Jose, Puerto Princesa City, Palawan');
      expect(sanJoseRoxas.label, 'San Jose, Roxas, Palawan');
      expect(manila.label, 'Manila, National Capital Region');
      expect(Place.fromJson(sanJosePP.toJson()), sanJosePP);
    });
  });
}
