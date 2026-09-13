// Converts the PSA's PSGC publication datafile (.xlsx) into the place asset
// the app bundles.
//
//   dart run tool/psgc/convert.dart <PSGC publication datafile.xlsx> [output.json]
//
// Output defaults to assets/places/ph_psgc.json. Needs nothing beyond the Dart
// SDK: an .xlsx is a zip of XML, and both are read here directly.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'psgc_builder.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/psgc/convert.dart <PSGC publication datafile.xlsx> [output.json]');
    exitCode = 64;
    return;
  }

  final input = File(args[0]);
  if (!await input.exists()) {
    stderr.writeln('Not found: ${input.path}');
    exitCode = 66;
    return;
  }
  final output = File(args.length > 1 ? args[1] : 'assets/places/ph_psgc.json');

  final zip = _Zip(await input.readAsBytes());
  final shared = _sharedStrings(zip.text('xl/sharedStrings.xml'));
  final sheets = zip.names.where((n) => RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(n)).toList()
    ..sort((a, b) => _sheetNumber(a).compareTo(_sheetNumber(b)));

  for (final sheet in sheets) {
    final rows = _rows(zip.text(sheet)!, shared);
    final header = _findHeader(rows);
    if (header == null) continue;

    stdout.writeln('Sheet: $sheet');
    stdout.writeln('Columns: code=${header.headers[header.code]} | name=${header.headers[header.name]} '
        '| level=${header.headers[header.level]}');
    final others = header.headers.entries
        .where((e) => e.key != header.code && e.key != header.name && e.key != header.level)
        .map((e) => e.value)
        .toList();
    if (others.isNotEmpty) stdout.writeln('Other columns (not used): ${others.join(' | ')}');

    final psgcRows = [
      for (final row in rows.skip(header.row + 1))
        PsgcRow(
          code: row[header.code] ?? '',
          name: row[header.name] ?? '',
          level: row[header.level] ?? '',
        ),
    ];

    final fileName = input.uri.pathSegments.isEmpty ? input.path : input.uri.pathSegments.last;
    final build = buildPsgcAsset(
      psgcRows,
      source: 'Philippine Standard Geographic Code (PSGC), Philippine Statistics Authority — $fileName',
    );

    await output.parent.create(recursive: true);
    await output.writeAsString(jsonEncode(build.asset));

    stdout.writeln('Places by level: ${build.countsByLevel}');
    stdout.writeln('Skipped rows: ${build.skipped}');
    stdout.writeln('Without a parent: ${build.orphans.length}'
        '${build.orphans.isEmpty ? '' : ' (first: ${build.orphans.take(10).join(', ')})'}');
    stdout.writeln('Wrote ${output.path} — ${(await output.length() / 1024).toStringAsFixed(0)} KB');
    return;
  }

  stderr.writeln('No sheet has a header row with PSGC code, Name and Geographic Level columns.');
  exitCode = 65;
}

int _sheetNumber(String path) => int.tryParse(RegExp(r'(\d+)\.xml$').firstMatch(path)?.group(1) ?? '') ?? 0;

class _Header {
  _Header(this.row, this.code, this.name, this.level, this.headers);
  final int row;
  final int code;
  final int name;
  final int level;
  final Map<int, String> headers;
}

/// The header row: the first with a PSGC code column (the 10-digit one when
/// there are several), a Name column and a Geographic Level column.
_Header? _findHeader(List<Map<int, String>> rows) {
  for (var r = 0; r < rows.length && r < 40; r++) {
    int? name;
    int? level;
    final codes = <int>[];
    for (final entry in rows[r].entries) {
      final text = entry.value.toLowerCase().trim();
      if (text.contains('geographic level')) {
        level ??= entry.key;
      } else if (text.contains('psgc')) {
        codes.add(entry.key);
      } else if (text == 'name') {
        name ??= entry.key;
      }
    }
    if (codes.isEmpty || name == null || level == null) continue;
    final code = codes.firstWhere((c) => rows[r][c]!.contains('10'), orElse: () => codes.first);
    return _Header(r, code, name, level, rows[r]);
  }
  return null;
}

List<String> _sharedStrings(String? xml) {
  if (xml == null) return const [];
  return [
    for (final si in RegExp(r'<si\b[^>]*>(.*?)</si>', dotAll: true).allMatches(xml))
      RegExp(r'<t\b[^>]*>(.*?)</t>', dotAll: true).allMatches(si.group(1)!).map((m) => _unescape(m.group(1)!)).join(),
  ];
}

List<Map<int, String>> _rows(String xml, List<String> shared) {
  final rows = <Map<int, String>>[];
  for (final row in RegExp(r'<row\b[^>]*>(.*?)</row>', dotAll: true).allMatches(xml)) {
    final cells = <int, String>{};
    for (final cell in RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true).allMatches(row.group(1)!)) {
      final attributes = cell.group(1)!;
      final body = cell.group(2) ?? '';
      final ref = RegExp(r'\br="([A-Z]+)\d+"').firstMatch(attributes)?.group(1);
      if (ref == null) continue;
      final type = RegExp(r'\bt="([^"]+)"').firstMatch(attributes)?.group(1);

      String value;
      if (type == 'inlineStr') {
        value = RegExp(r'<t\b[^>]*>(.*?)</t>', dotAll: true).allMatches(body).map((m) => _unescape(m.group(1)!)).join();
      } else {
        final raw = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(body)?.group(1) ?? '';
        final index = type == 's' ? int.tryParse(raw) : null;
        value = index != null && index < shared.length ? shared[index] : _unescape(raw);
      }
      cells[_columnIndex(ref)] = value.trim();
    }
    rows.add(cells);
  }
  return rows;
}

int _columnIndex(String letters) {
  var n = 0;
  for (final unit in letters.codeUnits) {
    n = n * 26 + (unit - 64);
  }
  return n - 1;
}

String _unescape(String text) => text
    .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)))
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// Just enough of the zip format to read an .xlsx: the central directory, and
/// stored or deflated entries.
class _Zip {
  _Zip(this._bytes) {
    _readDirectory();
  }

  final Uint8List _bytes;
  final Map<String, ({int method, int size, int offset})> _entries = {};

  Iterable<String> get names => _entries.keys;

  static const _little = Endian.little;

  void _readDirectory() {
    final data = ByteData.sublistView(_bytes);
    var end = -1;
    for (var i = _bytes.length - 22; i >= 0 && i >= _bytes.length - 65557; i--) {
      if (data.getUint32(i, _little) == 0x06054b50) {
        end = i;
        break;
      }
    }
    if (end < 0) throw const FormatException('Not a zip archive — is this an .xlsx file?');

    final count = data.getUint16(end + 10, _little);
    var offset = data.getUint32(end + 16, _little);
    for (var n = 0; n < count; n++) {
      if (data.getUint32(offset, _little) != 0x02014b50) {
        throw const FormatException('Damaged zip central directory.');
      }
      final method = data.getUint16(offset + 10, _little);
      final size = data.getUint32(offset + 20, _little);
      final nameLength = data.getUint16(offset + 28, _little);
      final extraLength = data.getUint16(offset + 30, _little);
      final commentLength = data.getUint16(offset + 32, _little);
      final localOffset = data.getUint32(offset + 42, _little);
      // Excel writes "xl/worksheets/…", but some Windows zip tools write
      // backslashes; a workbook re-zipped by one of those must still read.
      final name = utf8.decode(_bytes.sublist(offset + 46, offset + 46 + nameLength)).replaceAll(r'\', '/');
      _entries[name] = (method: method, size: size, offset: localOffset);
      offset += 46 + nameLength + extraLength + commentLength;
    }
  }

  String? text(String name) {
    final entry = _entries[name];
    if (entry == null) return null;
    final data = ByteData.sublistView(_bytes);
    final nameLength = data.getUint16(entry.offset + 26, _little);
    final extraLength = data.getUint16(entry.offset + 28, _little);
    final start = entry.offset + 30 + nameLength + extraLength;
    final raw = _bytes.sublist(start, start + entry.size);
    final content = switch (entry.method) {
      0 => raw,
      8 => ZLibDecoder(raw: true).convert(raw),
      _ => throw FormatException('Unsupported zip compression method ${entry.method}.'),
    };
    return utf8.decode(content);
  }
}
