import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_go/screens/auth/client_ui/home/need_help_screen.dart';
import 'package:on_go/services/location/device_location_provider.dart';
import 'package:on_go/services/location/location_service.dart';
import 'package:on_go/services/location/place_directory.dart';
import 'package:on_go/services/location/place_sources.dart';
import 'package:on_go/services/location/place_suggestions.dart';
import 'package:on_go/widgets/location_selector.dart';
import 'package:on_go_shared/on_go_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'location_foundation_test.dart' show FakeDevice;
import 'responsive_layout_test.dart' show app;

// ---------------------------------------------------------------------------
// Test doubles. A tiny slice of the hierarchy — enough to prove ordering and
// navigation — and a geocoder that answers whatever the test says. These are
// fixtures for the selector's behaviour, not a data source for the app.
// ---------------------------------------------------------------------------

const _mimaropa = Place(id: 'r17', name: 'MIMAROPA Region', level: PlaceLevel.region);
const _centralVisayas = Place(id: 'r07', name: 'Central Visayas', level: PlaceLevel.region);
const _palawan = Place(id: 'p-pal', name: 'Palawan', level: PlaceLevel.province, region: 'MIMAROPA Region');
const _cebu = Place(id: 'p-ceb', name: 'Cebu', level: PlaceLevel.province, region: 'Central Visayas');
const _puertoPrincesa = Place(
    id: 'c-pp', name: 'Puerto Princesa City', level: PlaceLevel.cityMunicipality, province: 'Palawan', region: 'MIMAROPA Region');
const _cebuCity = Place(
    id: 'c-ceb', name: 'Cebu City', level: PlaceLevel.cityMunicipality, province: 'Cebu', region: 'Central Visayas');

Place _brgy(String id, String name, Place city) => Place(
      id: id,
      name: name,
      level: PlaceLevel.barangay,
      cityMunicipality: city.name,
      province: city.province,
      region: city.region,
    );

final _sanPedro = _brgy('b1', 'San Pedro', _puertoPrincesa);
final _sanJose = _brgy('b2', 'San Jose', _puertoPrincesa);
final _cebuano = _brgy('b3', 'Cebuano', _puertoPrincesa);
final _lahug = _brgy('b4', 'Lahug', _cebuCity);

final _fixture = <Place>[
  _mimaropa, _centralVisayas, _palawan, _cebu, _puertoPrincesa, _cebuCity,
  _sanPedro, _sanJose, _cebuano, _lahug,
];

class _FixtureDirectory implements PlaceDirectory {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<Place>> search(String query, {Place? near, int limit = 200}) async {
    final words = PlaceSuggestions.normalize(query).split(' ');
    return _fixture
        .where((p) => words.any((w) => PlaceSuggestions.normalize(p.label).contains(w)))
        .toList();
  }

  @override
  Future<List<Place>> topLevel() async => _fixture.where((p) => p.level == PlaceLevel.region).toList();

  @override
  Future<List<Place>> childrenOf(Place parent) async {
    final childLevel = PlaceLevel.values[parent.level.index + 1];
    return _fixture
        .where((p) => p.level == childLevel && p.nameAt(parent.level) == parent.name)
        .toList();
  }

  @override
  Future<List<Place>> around(Place anchor, {int limit = 200}) async => _fixture;

  @override
  Future<Place?> match({String? barangay, String? cityMunicipality, String? province, String? region}) async {
    for (final p in _fixture) {
      if (p.level == PlaceLevel.barangay && p.name == barangay && p.cityMunicipality == cityMunicipality) return p;
    }
    return null;
  }
}

class _FixtureGeocoder implements ReverseGeocoder {
  Place? answer = const Place(
    id: '',
    name: 'Rizal Avenue',
    level: PlaceLevel.street,
    barangay: 'San Pedro',
    cityMunicipality: 'Puerto Princesa City',
    province: 'Palawan',
    region: 'MIMAROPA Region',
  );
  int calls = 0;

  @override
  Future<Place?> placeAt(GeoPoint point) async {
    calls++;
    return answer;
  }
}

DeviceFix _fixAt(double lat, double lng) =>
    DeviceFix(latitude: lat, longitude: lng, accuracyMeters: 10, timestamp: DateTime.now());

const _pp = GeoPoint(9.7392, 118.7353);

const _sizes = <String, Size>{
  'phone': Size(390, 844),
  'tablet': Size(834, 1112),
};

class _Harness {
  _Harness(this.tester, {bool withDirectory = true, bool withGeocoder = true})
      : directory = withDirectory ? _FixtureDirectory() : null,
        geocoder = withGeocoder ? _FixtureGeocoder() : null;

  final WidgetTester tester;
  final FakeDevice device = FakeDevice();
  final _FixtureDirectory? directory;
  final _FixtureGeocoder? geocoder;
  final controller = TextEditingController();
  final changes = <SelectedLocation?>[];
  late final LocationService service = LocationService(provider: device, persist: false);

  SelectedLocation? get last => changes.isEmpty ? null : changes.last;

  Future<void> pump(Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(service.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(app(
      size,
      SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: LocationSelector(
          controller: controller,
          onChanged: changes.add,
          directory: directory,
          geocoder: geocoder,
          service: service,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder get field => find.descendant(of: find.byType(LocationSelector), matching: find.byType(TextField));

  Future<void> openList() async {
    await tester.tap(field);
    await settle();
  }

  Future<void> type(String text) async {
    await tester.enterText(field, text);
    await settle();
  }

  /// Past the typing debounce, then until quiet.
  Future<void> settle() async {
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
  }

  /// The suggestions list inside the selector — not any other list on screen.
  Finder get _panelList =>
      find.descendant(of: find.byType(LocationSelector), matching: find.byType(ListView));

  /// A suggestion row, by its place name — never the same words sitting in
  /// the text field.
  Finder row(String name) => find.descendant(of: _panelList, matching: find.text(name));

  /// The place names in the list, top to bottom. Each row is an InkWell whose
  /// first Text is the name; the browse chevrons inside rows are InkWells too,
  /// with no text of their own, and are skipped.
  List<String> rowTitles() {
    final rows = find.descendant(of: _panelList, matching: find.byType(InkWell));
    final titles = <String>[];
    for (final row in rows.evaluate()) {
      final texts = find.descendant(of: find.byWidget(row.widget), matching: find.byType(Text));
      if (texts.evaluate().isEmpty) continue;
      titles.add(tester.widget<Text>(texts.first).data!);
    }
    return titles;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('without a place source', () {
    testWidgets('it is a plain field: typing works, and it says suggestions are unavailable', (tester) async {
      final h = _Harness(tester, withDirectory: false, withGeocoder: false);
      await h.pump(_sizes['phone']!);

      await h.openList();
      expect(find.textContaining('Place suggestions aren\'t available'), findsOneWidget);

      await h.type('Purok 3, Brgy. San Pedro');
      expect(h.last?.text, 'Purok 3, Brgy. San Pedro');
      expect(h.last?.gps, isNull);
    });

    testWidgets('GPS with no geocoder shows the real coordinates, not a guessed address', (tester) async {
      final h = _Harness(tester, withDirectory: false, withGeocoder: false);
      h.device.permission = DevicePermission.whileInUse;
      h.device.nextFix = _fixAt(_pp.latitude, _pp.longitude);
      await h.pump(_sizes['phone']!);

      await tester.tap(find.text('Use Current Location'));
      await h.settle();

      expect(h.controller.text, 'Near 9.73920, 118.73530');
      expect(h.last?.gps?.point, _pp);
    });
  });

  for (final entry in _sizes.entries) {
    group('on a ${entry.key}', () {
      testWidgets('tap: nearby first; type: matches first; pick: it stays', (tester) async {
        final h = _Harness(tester);
        // The device has been here before, so "nearby" is known without asking.
        h.device.permission = DevicePermission.whileInUse;
        h.device.nextFix = _fixAt(_pp.latitude, _pp.longitude);
        await h.service.locate();
        await h.pump(entry.value);

        await h.openList();
        expect(find.text('Near you'), findsOneWidget);
        expect(h.rowTitles().first, 'San Pedro', reason: 'their own barangay leads the nearby list');

        await h.type('Cebu');
        final titles = h.rowTitles();
        expect(titles.first, 'Cebu', reason: 'what was typed beats what is close');
        expect(titles.indexOf('Cebu City'), lessThan(titles.indexOf('Cebuano')));

        await tester.tap(h.row('Cebu City'));
        await h.settle();
        expect(h.controller.text, 'Cebu City, Cebu');
        expect(h.last?.place, _cebuCity);
        expect(h.last?.gps, isNull, reason: 'a picked place is not a device position');
        expect(find.byType(ListView), findsNothing, reason: 'the list closes on a pick');
      });

      testWidgets('use current location: the real fix, resolved, and kept up to date', (tester) async {
        final h = _Harness(tester);
        h.device.permission = DevicePermission.whileInUse;
        h.device.nextFix = _fixAt(_pp.latitude, _pp.longitude);
        await h.pump(entry.value);

        await tester.tap(find.text('Use Current Location'));
        await h.settle();

        expect(h.controller.text, 'Rizal Avenue, San Pedro, Puerto Princesa City, Palawan');
        expect(h.last?.gps?.point, _pp);
        expect(h.service.isTracking, isTrue, reason: 'the field follows the device while it is on GPS');

        // Two hundred meters on: a real move re-resolves and reports it.
        final callsBefore = h.geocoder!.calls;
        final moved = GeoPoint(_pp.latitude + 200 / 111195, _pp.longitude);
        h.device.fixStream.add(_fixAt(moved.latitude, moved.longitude));
        await h.settle();
        expect(h.last?.gps?.point, moved);
        expect(h.geocoder!.calls, callsBefore + 1);
      });
    });
  }

  group('changing your mind', () {
    testWidgets('typing over a GPS location drops its coordinates and stops following', (tester) async {
      final h = _Harness(tester);
      h.device.permission = DevicePermission.whileInUse;
      h.device.nextFix = _fixAt(_pp.latitude, _pp.longitude);
      await h.pump(_sizes['phone']!);

      await tester.tap(find.text('Use Current Location'));
      await h.settle();
      expect(h.last?.gps, isNotNull);

      await h.type('Lahug, Cebu City');
      expect(h.last?.gps, isNull);
      expect(h.service.isTracking, isFalse);
      expect(h.device.liveListeners, 0);
    });

    testWidgets('clear empties the field and goes back to nearby', (tester) async {
      final h = _Harness(tester);
      h.device.permission = DevicePermission.whileInUse;
      h.device.nextFix = _fixAt(_pp.latitude, _pp.longitude);
      await h.service.locate();
      await h.pump(_sizes['phone']!);

      await h.openList();
      await h.type('Lahug');
      await tester.tap(find.byTooltip('Clear location'));
      await h.settle();

      expect(h.controller.text, isEmpty);
      expect(h.last, isNull);
      expect(h.rowTitles().first, 'San Pedro');
    });

    testWidgets('back to current location after picking a place', (tester) async {
      final h = _Harness(tester);
      h.device.permission = DevicePermission.whileInUse;
      h.device.nextFix = _fixAt(_pp.latitude, _pp.longitude);
      await h.pump(_sizes['phone']!);

      await h.openList();
      await h.type('Lahug');
      await tester.tap(h.row('Lahug'));
      await h.settle();
      expect(h.last?.gps, isNull);

      await tester.tap(find.text('Use Current Location'));
      await h.settle();
      expect(h.last?.gps?.point, _pp);
    });
  });

  group('when location cannot be had', () {
    testWidgets('permanently denied: says so, offers Settings, and typing still works', (tester) async {
      final h = _Harness(tester);
      h.device.permission = DevicePermission.deniedForever;
      await h.pump(_sizes['phone']!);

      await tester.tap(find.text('Use Current Location'));
      await h.settle();

      expect(find.text(LocationFailure.permissionDeniedForever.message), findsOneWidget);
      await tester.tap(find.text('Settings'));
      await h.settle();
      expect(h.device.openedSettings, 'app');

      await h.type('San Jose');
      expect(h.last?.text, 'San Jose');
    });

    testWidgets('GPS switched off: the device\'s location settings', (tester) async {
      final h = _Harness(tester);
      h.device.permission = DevicePermission.whileInUse;
      h.device.servicesOn = false;
      await h.pump(_sizes['phone']!);

      await tester.tap(find.text('Use Current Location'));
      await h.settle();

      expect(find.text(LocationFailure.servicesDisabled.message), findsOneWidget);
      await tester.tap(find.text('Settings'));
      await h.settle();
      expect(h.device.openedSettings, 'location');
    });

    testWidgets('GPS works but the address cannot be resolved: coordinates, not a crash', (tester) async {
      final h = _Harness(tester);
      h.geocoder!.answer = null;
      h.device.permission = DevicePermission.whileInUse;
      h.device.nextFix = _fixAt(_pp.latitude, _pp.longitude);
      await h.pump(_sizes['phone']!);

      await tester.tap(find.text('Use Current Location'));
      await h.settle();
      expect(h.controller.text, startsWith('Near 9.73920'));
      expect(h.last?.gps?.point, _pp);
    });

    testWidgets('no matches: says so, and keeps what was typed', (tester) async {
      final h = _Harness(tester);
      await h.pump(_sizes['phone']!);
      await h.openList();
      await h.type('Zzyzx');
      expect(find.text('No places match "Zzyzx". You can keep what you typed.'), findsOneWidget);
      expect(h.last?.text, 'Zzyzx');
    });
  });

  group('browsing the hierarchy', () {
    testWidgets('region → province → city → barangay, and back up', (tester) async {
      final h = _Harness(tester);
      await h.pump(_sizes['phone']!);
      await h.openList();

      expect(h.rowTitles(), containsAll(['MIMAROPA Region', 'Central Visayas']));

      await tester.tap(find.byTooltip('Places in MIMAROPA Region'));
      await h.settle();
      expect(h.rowTitles(), ['Palawan']);

      await tester.tap(find.byTooltip('Places in Palawan'));
      await h.settle();
      expect(h.rowTitles(), ['Puerto Princesa City']);

      await tester.tap(find.byTooltip('Places in Puerto Princesa City'));
      await h.settle();
      expect(h.rowTitles(), ['Cebuano', 'San Jose', 'San Pedro']);

      // The breadcrumb goes back up in one tap.
      await tester.tap(find.widgetWithText(ChoiceChip, 'All places'));
      await h.settle();
      expect(h.rowTitles(), containsAll(['MIMAROPA Region', 'Central Visayas']));
    });
  });

  group('on the Client Home screen', () {
    testWidgets('GPS captures precise coordinates; picking a named place does not', (tester) async {
      final device = FakeDevice()
        ..permission = DevicePermission.whileInUse
        ..nextFix = _fixAt(_pp.latitude, _pp.longitude);
      final service = LocationService(provider: device, persist: false);
      final original = LocationService.instance;
      LocationService.debugSetInstance(service);
      PlaceSources.configure(directory: _FixtureDirectory(), geocoder: _FixtureGeocoder());
      addTearDown(() {
        LocationService.debugSetInstance(original);
        PlaceSources.debugReset();
        service.dispose();
      });

      const size = Size(390, 844);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(size, const NeedHelpScreen()));
      await tester.pumpAndSettle();

      final useCurrent = find.text('Use Current Location');
      await tester.ensureVisible(useCurrent);
      await tester.tap(useCurrent);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(find.textContaining('Precise location captured'), findsOneWidget);

      final field = find.descendant(of: find.byType(LocationSelector), matching: find.byType(TextField));
      await tester.ensureVisible(field);
      await tester.enterText(field, 'Lahug');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      // The row in the selector's own list: the page is a list too, and the
      // field now holds the same word.
      final lahug = find.descendant(
        of: find.descendant(of: find.byType(LocationSelector), matching: find.byType(ListView)),
        matching: find.text('Lahug'),
      );
      await tester.ensureVisible(lahug);
      await tester.tap(lahug);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(find.textContaining('Precise location captured'), findsNothing);
    });
  });
}
