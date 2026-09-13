/// Turns rows of the PSA's PSGC publication datafile into the compact asset
/// `PsgcPlaceDirectory` reads. Pure: no files, no spreadsheet — `convert.dart`
/// does the reading, and tests drive this directly.
library;

/// One row as the spreadsheet has it.
class PsgcRow {
  const PsgcRow({required this.code, required this.name, required this.level});

  final String code;
  final String name;
  final String level;
}

/// The PSGC's geographic level codes this app understands.
const Set<String> psgcLevels = {'Reg', 'Prov', 'Dist', 'SGA', 'City', 'Mun', 'SubMun', 'Bgy'};

/// Lower is broader.
int _breadth(String level) => switch (level) {
      'Reg' => 0,
      'Prov' || 'Dist' || 'SGA' => 1,
      'City' || 'Mun' => 2,
      'SubMun' => 3,
      'Bgy' => 4,
      _ => 9,
    };

/// A 10-digit PSGC code from whatever the spreadsheet stored. Excel keeps
/// codes as numbers, so region codes 01–09 lose their leading zero, and a
/// number can come back as "100000000.0" or "1.7E9".
String normalizePsgcCode(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return '';
  if (RegExp(r'[eE]').hasMatch(text)) {
    final value = double.tryParse(text);
    if (value == null) return '';
    text = value.toStringAsFixed(0);
  } else if (text.contains('.')) {
    text = text.split('.').first;
  }
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty || digits.length > 10) return '';
  return digits.padLeft(10, '0');
}

/// The level code as this app spells it, or '' when it is not one of
/// [psgcLevels].
String normalizePsgcLevel(String raw) {
  final text = raw.trim().toLowerCase();
  for (final level in psgcLevels) {
    if (level.toLowerCase() == text) return level;
  }
  return '';
}

class PsgcBuild {
  const PsgcBuild({
    required this.asset,
    required this.countsByLevel,
    required this.skipped,
    required this.orphans,
  });

  /// Ready for `jsonEncode`.
  final Map<String, Object> asset;
  final Map<String, int> countsByLevel;

  /// Rows dropped: no usable code, name or level, or a repeated code.
  final int skipped;

  /// Codes other than regions for which no parent could be found. Kept in the
  /// asset, just not attached to anything — worth reading when a new edition
  /// changes shape.
  final List<String> orphans;
}

PsgcBuild buildPsgcAsset(Iterable<PsgcRow> rows, {required String source}) {
  final known = <String, PsgcRow>{};
  var skipped = 0;
  for (final row in rows) {
    final code = normalizePsgcCode(row.code);
    final level = normalizePsgcLevel(row.level);
    final name = row.name.trim();
    if (code.isEmpty || level.isEmpty || name.isEmpty || known.containsKey(code)) {
      skipped++;
      continue;
    }
    known[code] = PsgcRow(code: code, name: name, level: level);
  }

  final codes = known.keys.toList()..sort();
  final places = <List<String>>[];
  final counts = <String, int>{};
  final orphans = <String>[];

  for (final code in codes) {
    final row = known[code]!;
    final parent = parentPsgcCode(code, row.level, known);
    if (parent == null && row.level != 'Reg') orphans.add(code);
    places.add([code, row.name, row.level, parent ?? '']);
    counts[row.level] = (counts[row.level] ?? 0) + 1;
  }

  return PsgcBuild(
    asset: {'format': 1, 'source': source, 'places': places},
    countsByLevel: counts,
    skipped: skipped,
    orphans: orphans,
  );
}

/// The code of the nearest broader place that exists in [known].
///
/// A 10-digit PSGC code is region (2) · province (3) · city/municipality (2) ·
/// barangay (3), so a parent is a prefix of the code padded back out with
/// zeros. The nearest prefix that names a real, broader row wins — which is
/// what puts a barangay under a sub-municipality in Manila, and an independent
/// city (whose province digits are its own) under its region.
String? parentPsgcCode(String code, String level, Map<String, PsgcRow> known) {
  if (level == 'Reg' || code.length != 10) return null;
  final breadth = _breadth(level);
  for (final keep in const [7, 5, 2]) {
    final candidate = code.substring(0, keep).padRight(10, '0');
    if (candidate == code) continue;
    final parent = known[candidate];
    if (parent != null && _breadth(parent.level) < breadth) return candidate;
  }
  return null;
}
