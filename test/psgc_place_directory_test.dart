import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:on_go/services/location/psgc_place_directory.dart';

/// A hand-made slice in the asset's format — not real data, just enough of
/// the hierarchy, and its awkward cases, to pin the directory's behaviour:
/// PSA naming ("City of …"), a municipality beside a city, namesake barangays
/// in different places, and Metro Manila with no province.
List<List<String>> _rows() => [
      ['1700000000', 'MIMAROPA Region', 'Reg', ''],
      ['1705300000', 'Palawan', 'Prov', '1700000000'],
      ['1731500000', 'City of Puerto Princesa', 'City', '1705300000'],
      ['1731500001', 'San Pedro', 'Bgy', '1731500000'],
      ['1731500002', 'San Jose', 'Bgy', '1731500000'],
      ['1705317000', 'Roxas', 'Mun', '1705300000'],
      ['1705317001', 'San Jose', 'Bgy', '1705317000'],
      ['0700000000', 'Central Visayas', 'Reg', ''],
      ['0702200000', 'Cebu', 'Prov', '0700000000'],
      ['0730600000', 'City of Cebu', 'City', '0702200000'],
      ['0730600001', 'Lahug', 'Bgy', '0730600000'],
      ['1300000000', 'National Capital Region (NCR)', 'Reg', ''],
      ['1380600000', 'City of Manila', 'City', '1300000000'],
      ['1380600001', 'Barangay 1', 'Bgy', '1380600000'],
      ['1381500000', 'City of Makati', 'City', '1300000000'],
    ];

String _asset(List<List<String>> rows) =>
    jsonEncode({'format': 1, 'source': 'test fixture', 'places': rows});

PsgcPlaceDirectory _directory([List<List<String>>? rows]) => PsgcPlaceDirectory(
      load: () async => _asset(rows ?? _rows()),
      parseInBackground: false,
    );

void main() {
  test('loads the asset and reports itself available', () async {
    final directory = _directory();
    expect(await directory.isAvailable(), isTrue);
    expect(await directory.source(), 'test fixture');
  });

  test('a missing or broken asset means unavailable — never a crash', () async {
    final missing = PsgcPlaceDirectory(load: () async => throw Exception('no asset'), parseInBackground: false);
    expect(await missing.isAvailable(), isFalse);
    expect(await missing.search('san'), isEmpty);

    final broken = PsgcPlaceDirectory(load: () async => '{"format": 99}', parseInBackground: false);
    expect(await broken.isAvailable(), isFalse);
    expect(await broken.topLevel(), isEmpty);
  });

  test('every place carries its ancestors, so namesakes read differently', () async {
    final directory = _directory();
    final sanJoses = (await directory.search('San Jose')).where((p) => p.name == 'San Jose').toList();
    expect(sanJoses.map((p) => p.label), containsAll([
      'San Jose, City of Puerto Princesa, Palawan',
      'San Jose, Roxas, Palawan',
    ]));
  });

  test('browsing goes down the hierarchy by parent', () async {
    final directory = _directory();
    final regions = await directory.topLevel();
    expect(regions.map((p) => p.name), containsAll(['MIMAROPA Region', 'Central Visayas', 'National Capital Region (NCR)']));

    final mimaropa = regions.firstWhere((p) => p.name == 'MIMAROPA Region');
    final provinces = await directory.childrenOf(mimaropa);
    expect(provinces.map((p) => p.name), ['Palawan']);

    final palawanCities = await directory.childrenOf(provinces.single);
    expect(palawanCities.map((p) => p.name), ['City of Puerto Princesa', 'Roxas']);
  });

  test('a geocoder\'s names find the PSA\'s record', () async {
    final directory = _directory();

    final sanPedro = await directory.match(
      barangay: 'San Pedro',
      cityMunicipality: 'Puerto Princesa',
      province: 'Palawan',
    );
    expect(sanPedro?.id, '1731500001');

    // The same barangay name in another town resolves to that town's.
    final sanJoseRoxas = await directory.match(barangay: 'San Jose', cityMunicipality: 'Roxas');
    expect(sanJoseRoxas?.id, '1705317001');

    expect((await directory.match(cityMunicipality: 'Cebu City'))?.id, '0730600000');
    expect((await directory.match(cityMunicipality: 'Puerto Princesa City'))?.id, '1731500000');
  });

  test('an unknown barangay falls back to the city it was reported in', () async {
    final directory = _directory();
    final place = await directory.match(barangay: 'Nowhere', cityMunicipality: 'Puerto Princesa');
    expect(place?.id, '1731500000');
  });

  test('around a barangay: its city\'s barangays, its province\'s towns, up to the region', () async {
    final directory = _directory();
    final sanPedro = (await directory.match(barangay: 'San Pedro', cityMunicipality: 'Puerto Princesa'))!;
    final ids = (await directory.around(sanPedro)).map((p) => p.id).toSet();
    expect(ids, containsAll(['1731500001', '1731500002', '1731500000', '1705317000', '1705300000', '1700000000']));
    expect(ids, isNot(contains('0730600001')), reason: 'Lahug is in Cebu');
  });

  test('Metro Manila, with no province: neighbours by region', () async {
    final directory = _directory();
    final manila = (await directory.match(cityMunicipality: 'Manila'))!;
    final ids = (await directory.around(manila)).map((p) => p.id).toSet();
    expect(ids, containsAll(['1380600000', '1380600001', '1381500000', '1300000000']));
  });

  test('a big national cut keeps the nearby matches', () async {
    // Three hundred far-away "San …" barangays in Cebu City, more than the cut.
    final rows = _rows();
    for (var i = 0; i < 300; i++) {
      rows.add(['07306${(1000 + i).toString().padLeft(5, '0')}', 'San Far $i', 'Bgy', '0730600000']);
    }
    final directory = _directory(rows);
    final near = (await directory.match(barangay: 'San Pedro', cityMunicipality: 'Puerto Princesa'))!;

    final results = await directory.search('san', near: near, limit: 30);
    expect(results, hasLength(30));
    expect(results.take(3).map((p) => p.id), containsAll(['1731500001', '1731500002', '1705317001']),
        reason: 'the Palawan matches must survive the cut, and lead it');
  });

  test('typing still beats distance across the whole dataset', () async {
    final directory = _directory();
    final near = (await directory.match(barangay: 'San Pedro', cityMunicipality: 'Puerto Princesa'))!;
    final results = await directory.search('Cebu', near: near);
    expect(results.take(2).map((p) => p.name), containsAll(['Cebu', 'City of Cebu']));
  });

  test('the background parse gives the same index', () async {
    final background = PsgcPlaceDirectory(load: () async => _asset(_rows()));
    expect(await background.isAvailable(), isTrue);
    expect((await background.topLevel()).length, 3);
  });
}
