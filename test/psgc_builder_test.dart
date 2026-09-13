import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:on_go/services/location/psgc_place_directory.dart';

import '../tool/psgc/psgc_builder.dart';

/// Rows shaped like the PSA datafile — codes as Excel stores them, awkward
/// cases included. A fixture for the conversion, not real data.
List<PsgcRow> _rows() => const [
      PsgcRow(code: '1700000000', name: 'MIMAROPA Region', level: 'Reg'),
      PsgcRow(code: '1705300000', name: 'Palawan', level: 'Prov'),
      PsgcRow(code: '1705317000', name: 'Roxas', level: 'Mun'),
      PsgcRow(code: '1705317001', name: 'San Jose', level: 'Bgy'),
      // An independent city: its province digits are its own.
      PsgcRow(code: '1731500000', name: 'City of Puerto Princesa', level: 'City'),
      PsgcRow(code: '1731500001', name: 'San Pedro', level: 'Bgy'),
      // Region 01, stored as a number without its leading zero.
      PsgcRow(code: '100000000', name: 'Region I (Ilocos Region)', level: 'Reg'),
      PsgcRow(code: '102800000.0', name: 'Ilocos Norte', level: 'Prov'),
      // Manila: city → sub-municipality → barangay.
      PsgcRow(code: '1300000000', name: 'National Capital Region (NCR)', level: 'Reg'),
      PsgcRow(code: '1380600000', name: 'City of Manila', level: 'City'),
      PsgcRow(code: '1380601000', name: 'Tondo I/II', level: 'SubMun'),
      PsgcRow(code: '1380601001', name: 'Barangay 1', level: 'Bgy'),
    ];

void main() {
  test('codes come back as 10 digits, however Excel stored them', () {
    expect(normalizePsgcCode('100000000'), '0100000000');
    expect(normalizePsgcCode('102800000.0'), '0102800000');
    expect(normalizePsgcCode('1.7E9'), '1700000000');
    expect(normalizePsgcCode(' 1705317001 '), '1705317001');
    expect(normalizePsgcCode(''), '');
    expect(normalizePsgcCode('not a code'), '');
    expect(normalizePsgcCode('12345678901'), '', reason: 'longer than a PSGC code');
  });

  test('parents follow the hierarchy', () {
    final build = buildPsgcAsset(_rows(), source: 'fixture');
    final parents = {
      for (final row in build.asset['places'] as List<List<String>>) row[0]: row[3],
    };

    expect(parents['1705300000'], '1700000000', reason: 'province → region');
    expect(parents['1705317000'], '1705300000', reason: 'municipality → province');
    expect(parents['1705317001'], '1705317000', reason: 'barangay → municipality');
    expect(parents['0102800000'], '0100000000', reason: 'a region that lost its leading zero still parents');
    expect(parents['1380601000'], '1380600000', reason: 'sub-municipality → city');
    expect(parents['1380601001'], '1380601000', reason: 'Manila barangay → sub-municipality');
  });

  test('an independent city sits under its region, as its code says', () {
    final build = buildPsgcAsset(_rows(), source: 'fixture');
    final parents = {
      for (final row in build.asset['places'] as List<List<String>>) row[0]: row[3],
    };
    expect(parents['1731500000'], '1700000000');
    expect(parents['1731500001'], '1731500000');
  });

  test('bad rows are skipped and counted, a repeated code is kept once', () {
    final build = buildPsgcAsset([
      ..._rows(),
      const PsgcRow(code: '', name: 'No code', level: 'Bgy'),
      const PsgcRow(code: '1705317002', name: '', level: 'Bgy'),
      const PsgcRow(code: '1705317003', name: 'Odd level', level: 'Purok'),
      const PsgcRow(code: '1705317001', name: 'San Jose again', level: 'Bgy'),
    ], source: 'fixture');

    expect(build.skipped, 4);
    final names = (build.asset['places'] as List<List<String>>).map((r) => r[1]);
    expect(names.where((n) => n.startsWith('San Jose')), ['San Jose']);
  });

  test('a place with no parent in the file is reported, not dropped', () {
    final build = buildPsgcAsset(const [
      PsgcRow(code: '1705317001', name: 'Stray barangay', level: 'Bgy'),
    ], source: 'fixture');
    expect(build.orphans, ['1705317001']);
    expect((build.asset['places'] as List).length, 1);
  });

  test('the asset is sorted, versioned, attributed, and counted by level', () {
    final build = buildPsgcAsset(_rows(), source: 'PSGC fixture edition');
    expect(build.asset['format'], 1);
    expect(build.asset['source'], 'PSGC fixture edition');
    final codes = (build.asset['places'] as List<List<String>>).map((r) => r[0]).toList();
    expect(codes, [...codes]..sort());
    expect(build.countsByLevel, {'Reg': 3, 'Prov': 2, 'Mun': 1, 'Bgy': 3, 'City': 2, 'SubMun': 1});
  });

  test('what the converter writes, the app\'s directory reads', () {
    final raw = jsonEncode(buildPsgcAsset(_rows(), source: 'fixture').asset);
    final index = PsgcIndex.parse(raw);

    final sanJose = index.byCode['1705317001']!;
    expect(sanJose.label, 'San Jose, Roxas, Palawan');

    final manilaBarangay = index.byCode['1380601001']!;
    expect(manilaBarangay.cityMunicipality, 'Tondo I/II');
    expect(manilaBarangay.region, 'National Capital Region (NCR)');

    expect(index.regions.map((p) => p.id), ['0100000000', '1300000000', '1700000000']);
  });
}
