/// Small helpers every DTO in this package uses, so date and enum encoding is
/// identical across the wire in both directions.
library;

/// Reads a required string, tolerating a null or non-string value.
String readString(Object? value) =>
    value is String ? value : (value == null ? '' : value.toString());

/// Reads an optional string; absent or empty comes back as null.
String? readStringOrNull(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// Reads a required [DateTime] stored as an ISO-8601 string.
DateTime readDate(Object? value) =>
    value is String ? DateTime.parse(value) : DateTime.fromMillisecondsSinceEpoch(0);

/// Reads an optional [DateTime] stored as an ISO-8601 string.
DateTime? readDateOrNull(Object? value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

/// Writes a [DateTime] as UTC ISO-8601 — the only date format on the wire.
String writeDate(DateTime value) => value.toUtc().toIso8601String();

/// Writes an optional [DateTime], or null.
String? writeDateOrNull(DateTime? value) => value == null ? null : writeDate(value);

/// Reads a list of strings out of a decoded JSON value, tolerating null.
List<String> readStringList(Object? value) =>
    value is List ? value.map((item) => '$item').toList(growable: false) : const [];

/// Reads a nested object out of a decoded JSON value, tolerating null or a
/// value of the wrong shape — both come back as an empty map.
Map<String, dynamic> readObject(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

/// Reads a list of objects out of a decoded JSON value, tolerating null.
List<Map<String, dynamic>> readObjectList(Object? value) => value is List
    ? value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList(growable: false)
    : const [];

/// Reads a number that may arrive as an int or a double.
///
/// [fallback] is what an absent or unreadable value becomes. It defaults to
/// zero, which is right for an amount; pass something else where zero would be
/// a meaningful — and wrong — answer, such as a configured rate.
double readDouble(Object? value, [double fallback = 0]) =>
    value is num ? value.toDouble() : fallback;

/// Reads an int that may arrive as a double (JSON has one number type).
int readInt(Object? value) => value is num ? value.toInt() : 0;

/// Reads an optional number; anything that is not a number comes back as null.
double? readDoubleOrNull(Object? value) => value is num ? value.toDouble() : null;

/// Reads a boolean; anything but `true` is false.
bool readBool(Object? value) => value == true;
