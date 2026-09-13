import 'package:flutter/foundation.dart';

import 'place_directory.dart';

/// The place data this app is configured with.
///
/// Both are null until a real source is connected — a bundled geographic
/// dataset, a search service, or the backend. Nothing is invented in the
/// meantime: with no directory the location selector offers typing only, and
/// with no geocoder a GPS position is shown as the coordinates it really is
/// rather than a guessed address.
///
/// Configured once at startup, the same way `MobileBackend.configure` is.
class PlaceSources {
  PlaceSources._();

  static PlaceDirectory? _directory;
  static ReverseGeocoder? _geocoder;

  static PlaceDirectory? get directory => _directory;
  static ReverseGeocoder? get geocoder => _geocoder;

  static void configure({PlaceDirectory? directory, ReverseGeocoder? geocoder}) {
    if (directory != null) _directory = directory;
    if (geocoder != null) _geocoder = geocoder;
  }

  @visibleForTesting
  static void debugReset() {
    _directory = null;
    _geocoder = null;
  }
}
