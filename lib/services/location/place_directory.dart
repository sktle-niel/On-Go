import 'package:on_go_shared/on_go_shared.dart';

/// Where place names come from.
///
/// The location selector asks this for places and knows nothing about where
/// they are stored — a bundled Philippine geographic dataset, a search
/// service, or the backend later on. Swapping the source is an implementation
/// of this interface; the selector, the ranking and the Client Home screen do
/// not change.
abstract interface class PlaceDirectory {
  /// Whether this directory can answer at all right now — loaded, reachable.
  /// The selector falls back to plain typing when it cannot.
  Future<bool> isAvailable();

  /// Places whose names match [query], best first, at most [limit].
  ///
  /// [near] is where the user is, when known. A directory with a large
  /// dataset must use it when it cuts results down to [limit]: across the
  /// whole country there are thousands of "San …" barangays, and a cut made
  /// without knowing where the user is would drop the nearby ones before the
  /// selector ever ranked them.
  Future<List<Place>> search(String query, {Place? near, int limit = 200});

  /// The broadest places, to start browsing from.
  Future<List<Place>> topLevel();

  /// The places directly inside [parent] — a province's cities, a city's
  /// barangays.
  Future<List<Place>> childrenOf(Place parent);

  /// Places around [anchor] worth offering before anything is typed: its
  /// siblings and its containing places. Unranked.
  Future<List<Place>> around(Place anchor, {int limit = 200});

  /// The directory's own record for a place described by name — how a GPS
  /// position, once turned into names, is placed into the directory.
  Future<Place?> match({
    String? barangay,
    String? cityMunicipality,
    String? province,
    String? region,
  });
}

/// Turns a coordinate into a readable place.
abstract interface class ReverseGeocoder {
  /// The place at [point], or null when it cannot be resolved — no network,
  /// no result, or no geocoder on this device. Never throws.
  Future<Place?> placeAt(GeoPoint point);
}
