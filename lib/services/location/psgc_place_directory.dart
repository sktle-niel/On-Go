import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:on_go_shared/on_go_shared.dart';

import 'place_directory.dart';
import 'place_suggestions.dart';

/// Philippine places from the Philippine Standard Geographic Code (PSGC),
/// the Philippine Statistics Authority's official list of every region,
/// province, city, municipality and barangay.
///
/// Bundled with the app, so suggestions and browsing work with no internet.
/// The PSA publishes the PSGC as a spreadsheet; `tool/psgc` converts it into
/// the compact asset this reads:
///
/// ```json
/// {
///   "format": 1,
///   "source": "PSGC, Philippine Statistics Authority — <edition>",
///   "places": [["<10-digit PSGC code>", "<name>", "<level>", "<parent code>"], ...]
/// }
/// ```
///
/// Levels are the PSGC's own codes — `Reg`, `Prov`, `City`, `Mun`, `SubMun`,
/// `Bgy`, with `Dist` and `SGA` read as province-equivalents. Parents are
/// resolved by the converter, so nothing here does code arithmetic.
///
/// The asset is parsed once, in the background, the first time it is needed.
/// A missing or unreadable asset makes the directory report itself unavailable
/// — the selector then offers typing only — and never throws.
class PsgcPlaceDirectory implements PlaceDirectory {
  PsgcPlaceDirectory({
    this.assetPath = defaultAssetPath,
    Future<String> Function()? load,
    this.parseInBackground = true,
  }) : _load = load;

  static const String defaultAssetPath = 'assets/places/ph_psgc.json';

  final String assetPath;

  /// Parse on a background isolate so 40,000-odd rows never stall a frame.
  /// Tests turn it off for determinism.
  final bool parseInBackground;

  final Future<String> Function()? _load;
  Future<PsgcIndex?>? _loading;

  Future<PsgcIndex?> _index() => _loading ??= _loadIndex();

  Future<PsgcIndex?> _loadIndex() async {
    try {
      final raw = await (_load ?? () => rootBundle.loadString(assetPath))();
      return parseInBackground ? await compute(PsgcIndex.parse, raw) : PsgcIndex.parse(raw);
    } catch (_) {
      return null;
    }
  }

  /// The edition the asset was built from, for an attribution line.
  Future<String?> source() async => (await _index())?.source;

  @override
  Future<bool> isAvailable() async => await _index() != null;

  @override
  Future<List<Place>> search(String query, {Place? near, int limit = 200}) async {
    final index = await _index();
    if (index == null) return const [];
    final q = PlaceSuggestions.normalize(query);
    if (q.isEmpty) return const [];

    // A cheap pass to find candidates — any place whose name holds one of the
    // typed words — then the real ranking, with where the user is, before the
    // cut to [limit].
    final words = q.split(' ').where((w) => w.length >= 2 || q.length < 2).toList();
    final candidates = <Place>[];
    for (var i = 0; i < index.places.length; i++) {
      final name = index.searchNames[i];
      if (words.any(name.contains)) candidates.add(index.places[i]);
    }
    return PlaceSuggestions.search(
      query: query,
      candidates: candidates,
      anchor: near == null ? null : index.resolve(near),
      limit: limit,
    );
  }

  @override
  Future<List<Place>> topLevel() async => (await _index())?.regions ?? const [];

  @override
  Future<List<Place>> childrenOf(Place parent) async {
    final index = await _index();
    if (index == null) return const [];
    final node = index.resolve(parent);
    return node == null ? const [] : (index.children[node.id] ?? const []);
  }

  @override
  Future<List<Place>> around(Place anchor, {int limit = 200}) async {
    final index = await _index();
    if (index == null) return const [];
    final node = index.resolve(anchor);
    return node == null ? const [] : index.around(node);
  }

  @override
  Future<Place?> match({
    String? barangay,
    String? cityMunicipality,
    String? province,
    String? region,
  }) async =>
      (await _index())?.match(
        barangay: barangay,
        cityMunicipality: cityMunicipality,
        province: province,
        region: region,
      );
}

/// The parsed PSGC: every place with its ancestors named, and the lookups the
/// directory needs. Built once, off the main isolate.
class PsgcIndex {
  PsgcIndex._({
    required this.source,
    required this.places,
    required this.searchNames,
    required this.byCode,
    required this.children,
    required this.regions,
    required this.parentOf,
    required Map<String, List<Place>> byKey,
  }) : _byKey = byKey;

  final String source;
  final List<Place> places;

  /// [places]' names, normalized once, same order.
  final List<String> searchNames;

  final Map<String, Place> byCode;
  final Map<String, List<Place>> children;
  final List<Place> regions;
  final Map<String, String> parentOf;
  final Map<String, List<Place>> _byKey;

  static PlaceLevel? _level(String code) => switch (code) {
        'Reg' => PlaceLevel.region,
        'Prov' || 'Dist' || 'SGA' => PlaceLevel.province,
        'City' || 'Mun' || 'SubMun' => PlaceLevel.cityMunicipality,
        'Bgy' => PlaceLevel.barangay,
        _ => null,
      };

  static PsgcIndex parse(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map || json['format'] != 1 || json['places'] is! List) {
      throw const FormatException('Not a PSGC place asset this app can read.');
    }

    final rows = <String, (String name, PlaceLevel level, String parent)>{};
    final order = <String>[];
    for (final row in json['places'] as List) {
      if (row is! List || row.length < 4) continue;
      final code = '${row[0]}';
      final level = _level('${row[2]}');
      if (code.isEmpty || level == null) continue;
      rows[code] = ('${row[1]}', level, '${row[3]}');
      order.add(code);
    }

    final places = <Place>[];
    final searchNames = <String>[];
    final byCode = <String, Place>{};
    final children = <String, List<Place>>{};
    final parentOf = <String, String>{};
    final byKey = <String, List<Place>>{};
    final regions = <Place>[];

    for (final code in order) {
      final (name, level, parent) = rows[code]!;

      // Name the ancestors by walking up — the nearest at each level wins.
      String? regionName, provinceName, cityName, barangayName;
      var up = parent;
      var guard = 0;
      while (up.isNotEmpty && rows.containsKey(up) && guard++ < 8) {
        final (upName, upLevel, upParent) = rows[up]!;
        switch (upLevel) {
          case PlaceLevel.region:
            regionName ??= upName;
          case PlaceLevel.province:
            provinceName ??= upName;
          case PlaceLevel.cityMunicipality:
            cityName ??= upName;
          case PlaceLevel.barangay:
            barangayName ??= upName;
          case PlaceLevel.street:
            break;
        }
        up = upParent;
      }

      final place = Place(
        id: code,
        name: name,
        level: level,
        barangay: barangayName,
        cityMunicipality: cityName,
        province: provinceName,
        region: regionName,
      );
      places.add(place);
      searchNames.add(PlaceSuggestions.normalize(name));
      byCode[code] = place;
      if (parent.isNotEmpty && rows.containsKey(parent)) {
        parentOf[code] = parent;
        (children[parent] ??= []).add(place);
      }
      if (level == PlaceLevel.region) regions.add(place);
      (byKey[_key(name)] ??= []).add(place);
    }

    for (final list in children.values) {
      list.sort((a, b) => a.name.compareTo(b.name));
    }
    regions.sort((a, b) => a.id.compareTo(b.id));

    return PsgcIndex._(
      source: '${json['source'] ?? 'Philippine Standard Geographic Code (PSGC)'}',
      places: places,
      searchNames: searchNames,
      byCode: byCode,
      children: children,
      regions: regions,
      parentOf: parentOf,
      byKey: byKey,
    );
  }

  /// How names are compared across sources. A geocoder says "Puerto Princesa"
  /// or "Puerto Princesa City" for the PSA's "City of Puerto Princesa", and
  /// "Cebu" can carry a "(Capital)" note — all of those meet here.
  static String _key(String name) {
    var k = PlaceSuggestions.normalize(name.replaceAll(RegExp(r'\([^)]*\)'), ' '));
    k = k.replaceFirst(RegExp(r'\s+city$'), '');
    return k;
  }

  /// The index's own record for [place]: by code when it came from here, by
  /// name when it came from somewhere else.
  Place? resolve(Place place) =>
      byCode[place.id] ??
      match(
        barangay: place.nameAt(PlaceLevel.barangay),
        cityMunicipality: place.nameAt(PlaceLevel.cityMunicipality),
        province: place.nameAt(PlaceLevel.province),
        region: place.nameAt(PlaceLevel.region),
      );

  /// The narrowest place the given names identify, or the broadest that still
  /// fits when the narrow one is not found.
  Place? match({String? barangay, String? cityMunicipality, String? province, String? region}) {
    bool fits(Place p, PlaceLevel level, String? wanted) {
      if (wanted == null || wanted.trim().isEmpty) return true;
      final have = p.nameAt(level);
      return have == null || _key(have) == _key(wanted);
    }

    Place? find(String? name, PlaceLevel level) {
      if (name == null || name.trim().isEmpty) return null;
      final candidates = (_byKey[_key(name)] ?? const <Place>[])
          .where((p) => p.level == level)
          .where((p) => level.index <= PlaceLevel.cityMunicipality.index || fits(p, PlaceLevel.cityMunicipality, cityMunicipality))
          .where((p) => level.index <= PlaceLevel.province.index || fits(p, PlaceLevel.province, province))
          .where((p) => level == PlaceLevel.region || fits(p, PlaceLevel.region, region))
          .toList();
      return candidates.isEmpty ? null : candidates.first;
    }

    return find(barangay, PlaceLevel.barangay) ??
        find(cityMunicipality, PlaceLevel.cityMunicipality) ??
        find(province, PlaceLevel.province) ??
        find(region, PlaceLevel.region);
  }

  /// Everything worth offering around [node] before anything is typed: the
  /// barangays of its city, the cities of its province (or region, where
  /// there is no province), and the province and region themselves.
  List<Place> around(Place node) {
    final out = <Place>{node};

    String? codeAt(PlaceLevel level) {
      if (node.level == level) return node.id;
      var up = parentOf[node.id];
      while (up != null) {
        final p = byCode[up];
        if (p == null) return null;
        if (p.level == level) return p.id;
        up = parentOf[up];
      }
      return null;
    }

    final city = codeAt(PlaceLevel.cityMunicipality);
    final province = codeAt(PlaceLevel.province);
    final region = codeAt(PlaceLevel.region);

    if (city != null) {
      out.add(byCode[city]!);
      out.addAll(children[city] ?? const []);
    }
    if (province != null) {
      out.add(byCode[province]!);
      out.addAll((children[province] ?? const []).where((p) => p.level == PlaceLevel.cityMunicipality));
    } else if (region != null) {
      out.addAll((children[region] ?? const []).where((p) => p.level == PlaceLevel.cityMunicipality));
    }
    if (region != null) out.add(byCode[region]!);
    return out.toList();
  }
}
