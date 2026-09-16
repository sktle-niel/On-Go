import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Where a store keeps its records between launches.
///
/// An interface so the local, on-device box can later give way to one backed
/// by the On Go API without the store — or any screen reading it — changing,
/// and so tests can keep records in memory.
abstract interface class RecordBox {
  Future<List<Map<String, dynamic>>> load();

  Future<void> save(List<Map<String, dynamic>> records);
}

/// Records as JSON under one key in shared preferences. A storage failure
/// reads as no records and a write that cannot happen is skipped — the store
/// still works for the session.
class SharedPreferencesRecordBox implements RecordBox {
  const SharedPreferencesRecordBox(this.key);

  final String key;

  @override
  Future<List<Map<String, dynamic>>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [for (final item in decoded.whereType<Map>()) Map<String, dynamic>.from(item)];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> save(List<Map<String, dynamic>> records) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(records));
    } catch (_) {
      // Still applies for this session.
    }
  }
}

/// Records in memory. For tests.
class MemoryRecordBox implements RecordBox {
  MemoryRecordBox([List<Map<String, dynamic>>? records]) : records = records ?? [];

  List<Map<String, dynamic>> records;

  @override
  Future<List<Map<String, dynamic>>> load() async => [for (final record in records) Map.of(record)];

  @override
  Future<void> save(List<Map<String, dynamic>> records) async =>
      this.records = [for (final record in records) Map.of(record)];
}

/// Writes a store's records one save at a time, in order, so a later save can
/// never be overwritten by an earlier one finishing last.
class RecordWriter {
  RecordWriter(this.box);

  final RecordBox box;
  Future<void> _pending = Future<void>.value();

  /// Completes once every write asked for so far has finished.
  Future<void> get idle => _pending;

  void write(List<Map<String, dynamic>> records) {
    _pending = _pending.then((_) => box.save(records)).catchError((Object _) {});
  }
}
