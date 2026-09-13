import 'dart:async';

import 'package:geocoding/geocoding.dart';
import 'package:on_go_shared/on_go_shared.dart';

import 'place_directory.dart';

/// Turns a coordinate into a readable place using the phone's own geocoder —
/// Android's Geocoder, Apple's CLGeocoder — through the geocoding plugin.
///
/// No API key and no service of our own, but it does need the network on most
/// devices, and what it knows varies by device and by map data. So every
/// failure — offline, no geocoder on the device, no result, a slow answer —
/// comes back as null, and the location field shows the real coordinates
/// instead.
///
/// The Philippine hierarchy is read out of the platform's fields as they
/// usually arrive for the Philippines: street from the thoroughfare, barangay
/// from the sub-locality, city or municipality from the locality, province
/// from the sub-administrative area, region from the administrative area.
/// `PsgcPlaceDirectory.match` then places those names into the official list,
/// tolerating "Puerto Princesa" for "City of Puerto Princesa".
class PlatformReverseGeocoder implements ReverseGeocoder {
  PlatformReverseGeocoder({this.timeout = const Duration(seconds: 8)});

  /// How long to wait for the device before giving up on an address.
  final Duration timeout;

  // Created on first use, not at construction: the plugin looks itself up
  // when constructed and throws where it is not registered.
  Geocoding? _geocoding;

  @override
  Future<Place?> placeAt(GeoPoint point) async {
    if (!point.isValid) return null;
    try {
      final geocoding = _geocoding ??= Geocoding();
      final marks = await geocoding
          .placemarkFromCoordinates(point.latitude, point.longitude)
          .timeout(timeout);
      for (final mark in marks) {
        final place = placeFromPlacemark(mark);
        if (place != null) return place.withPoint(point);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// The Philippine reading of one platform placemark, or null when it names
  /// nothing usable.
  static Place? placeFromPlacemark(Placemark mark) {
    final street = _street(mark.thoroughfare) ?? _street(mark.street);
    final barangay = _clean(mark.subLocality);
    final city = _clean(mark.locality);
    final subAdministrative = _clean(mark.subAdministrativeArea);
    final administrative = _clean(mark.administrativeArea);
    final province = subAdministrative ?? administrative;
    final region =
        subAdministrative != null && administrative != null && administrative != subAdministrative
            ? administrative
            : null;

    Place build(String name, PlaceLevel level) => Place(
          id: '',
          name: name,
          level: level,
          street: level == PlaceLevel.street ? name : null,
          barangay: barangay,
          cityMunicipality: city,
          province: province,
          region: region,
        );

    if (street != null && street != barangay && street != city) return build(street, PlaceLevel.street);
    if (barangay != null && barangay != city) return build(barangay, PlaceLevel.barangay);
    if (city != null) return build(city, PlaceLevel.cityMunicipality);
    if (province != null) return build(province, PlaceLevel.province);
    if (region != null) return build(region, PlaceLevel.region);
    return null;
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// Plus Codes ("8C7Q+XX") and "Unnamed Road" are what a geocoder says when
  /// it has no street name. Neither is a street anyone would recognise.
  static final RegExp _plusCode = RegExp(r'^[23456789CFGHJMPQRVWX]{4,8}\+[23456789CFGHJMPQRVWX]{2,3}', caseSensitive: false);

  static String? _street(String? value) {
    final cleaned = _clean(value);
    if (cleaned == null) return null;
    if (cleaned.toLowerCase() == 'unnamed road') return null;
    if (_plusCode.hasMatch(cleaned)) return null;
    return cleaned;
  }
}
