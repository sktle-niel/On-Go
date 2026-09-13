import 'geo_location.dart';
import 'json.dart';

/// How broad a place is, broadest first. The order is the Philippine
/// administrative hierarchy — region, province, city or municipality,
/// barangay — with street below it for sources that know streets.
enum PlaceLevel {
  region,
  province,
  cityMunicipality,
  barangay,
  street;

  static PlaceLevel fromName(String name) =>
      values.firstWhere((v) => v.name == name, orElse: () => PlaceLevel.barangay);

  String get label => switch (this) {
        PlaceLevel.region => 'Region',
        PlaceLevel.province => 'Province',
        PlaceLevel.cityMunicipality => 'City / Municipality',
        PlaceLevel.barangay => 'Barangay',
        PlaceLevel.street => 'Street',
      };
}

/// A named place, and the places it sits inside.
///
/// The ancestors are carried by name on every place, so a barangay called
/// "San Jose" — and there are hundreds — always travels with enough context to
/// tell it apart, and can be labelled without another lookup. [point] is set
/// when the source that produced the place knows its coordinates.
///
/// The same shape serves the client's chosen location today and a job's
/// location when the backend stores one.
class Place {
  /// Stable key within the source that produced it — a PSGC code, for
  /// example. Two places with the same non-empty id are the same place.
  final String id;

  final String name;
  final PlaceLevel level;

  final String? street;
  final String? barangay;
  final String? cityMunicipality;
  final String? province;
  final String? region;

  final GeoPoint? point;

  const Place({
    required this.id,
    required this.name,
    required this.level,
    this.street,
    this.barangay,
    this.cityMunicipality,
    this.province,
    this.region,
    this.point,
  });

  /// This place's name at [level] — its own name at its own level, an
  /// ancestor's above it, null below it or where the source had none. (Metro
  /// Manila cities, for instance, have a region but no province.)
  String? nameAt(PlaceLevel level) {
    if (level == this.level) return name;
    if (level.index > this.level.index) return null;
    return switch (level) {
      PlaceLevel.region => region,
      PlaceLevel.province => province,
      PlaceLevel.cityMunicipality => cityMunicipality,
      PlaceLevel.barangay => barangay,
      PlaceLevel.street => street,
    };
  }

  /// "San Jose, Puerto Princesa City, Palawan": the place, then just enough of
  /// what contains it to tell it apart from its namesakes.
  String get label {
    final parts = <String>[name];
    void add(String? value) {
      if (value != null && value.isNotEmpty && !parts.contains(value)) parts.add(value);
    }

    if (level == PlaceLevel.street) add(barangay);
    if (level.index > PlaceLevel.cityMunicipality.index) add(cityMunicipality);
    if (level.index > PlaceLevel.province.index) add(province ?? region);
    if (level == PlaceLevel.province) add(region);
    return parts.join(', ');
  }

  /// What contains this place, as one line — for a subtitle under [name].
  String get context => label == name ? level.label : label.substring(name.length + 2);

  Place withPoint(GeoPoint point) => Place(
        id: id,
        name: name,
        level: level,
        street: street,
        barangay: barangay,
        cityMunicipality: cityMunicipality,
        province: province,
        region: region,
        point: point,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'level': level.name,
        'street': street,
        'barangay': barangay,
        'cityMunicipality': cityMunicipality,
        'province': province,
        'region': region,
        'point': point?.toJson(),
      };

  factory Place.fromJson(Map<String, dynamic> json) => Place(
        id: readString(json['id']),
        name: readString(json['name']),
        level: PlaceLevel.fromName(readString(json['level'])),
        street: readStringOrNull(json['street']),
        barangay: readStringOrNull(json['barangay']),
        cityMunicipality: readStringOrNull(json['cityMunicipality']),
        province: readStringOrNull(json['province']),
        region: readStringOrNull(json['region']),
        point: json['point'] is Map ? GeoPoint.fromJson(readObject(json['point'])) : null,
      );

  @override
  bool operator ==(Object other) =>
      other is Place &&
      (id.isNotEmpty && other.id.isNotEmpty
          ? other.id == id
          : other.level == level && other.label == label);

  @override
  int get hashCode => id.isNotEmpty ? id.hashCode : Object.hash(level, label);

  @override
  String toString() => 'Place(${level.name}: $label)';
}
