import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:on_go/services/location/platform_reverse_geocoder.dart';
import 'package:on_go_shared/on_go_shared.dart';

void main() {
  test('a Philippine placemark becomes the street with its whole hierarchy', () {
    final place = PlatformReverseGeocoder.placeFromPlacemark(const Placemark(
      thoroughfare: 'Rizal Avenue',
      subLocality: 'San Pedro',
      locality: 'Puerto Princesa',
      subAdministrativeArea: 'Palawan',
      administrativeArea: 'Mimaropa',
      isoCountryCode: 'PH',
    ))!;

    expect(place.level, PlaceLevel.street);
    expect(place.name, 'Rizal Avenue');
    expect(place.barangay, 'San Pedro');
    expect(place.cityMunicipality, 'Puerto Princesa');
    expect(place.province, 'Palawan');
    expect(place.region, 'Mimaropa');
    expect(place.label, 'Rizal Avenue, San Pedro, Puerto Princesa, Palawan');
  });

  test('no street name is not invented: "Unnamed Road" and Plus Codes are skipped', () {
    for (final junk in ['Unnamed Road', '8C7Q+XX', '8C7Q+X2 Puerto Princesa']) {
      final place = PlatformReverseGeocoder.placeFromPlacemark(Placemark(
        thoroughfare: junk,
        subLocality: 'San Pedro',
        locality: 'Puerto Princesa',
        subAdministrativeArea: 'Palawan',
      ))!;
      expect(place.level, PlaceLevel.barangay, reason: '"$junk" is not a street');
      expect(place.name, 'San Pedro');
    }
  });

  test('a sparse answer still gives the narrowest place it names', () {
    final city = PlatformReverseGeocoder.placeFromPlacemark(
        const Placemark(locality: 'Puerto Princesa', administrativeArea: 'Palawan'))!;
    expect(city.level, PlaceLevel.cityMunicipality);
    expect(city.province, 'Palawan');
    expect(city.region, isNull, reason: 'one administrative area is the province, not also the region');

    final province = PlatformReverseGeocoder.placeFromPlacemark(const Placemark(administrativeArea: 'Palawan'))!;
    expect(province.level, PlaceLevel.province);
  });

  test('an empty answer is no place at all', () {
    expect(PlatformReverseGeocoder.placeFromPlacemark(const Placemark()), isNull);
    expect(PlatformReverseGeocoder.placeFromPlacemark(const Placemark(street: '  ', locality: '')), isNull);
  });

  test('no geocoder on the device: null, never a crash', () async {
    // No plugin is registered under test — exactly the "not available" case.
    final geocoder = PlatformReverseGeocoder(timeout: const Duration(milliseconds: 200));
    expect(await geocoder.placeAt(const GeoPoint(9.7392, 118.7353)), isNull);
  });

  test('a nonsense coordinate is not sent to the geocoder', () async {
    expect(await PlatformReverseGeocoder().placeAt(const GeoPoint(999, 999)), isNull);
  });
}
