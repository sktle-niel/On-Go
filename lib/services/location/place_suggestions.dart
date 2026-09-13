import 'package:on_go_shared/on_go_shared.dart';

/// Orders place suggestions — the rules, with no data and no UI in them.
///
/// Two modes, matching how the selector is used:
///
/// * **Nothing typed** ([around]): what is near the user, nearest first — their
///   barangay, the barangays beside it, their city, the cities beside it,
///   their province, their region.
/// * **Something typed** ([search]): how well the name matches comes FIRST,
///   and only then how near it is. Someone in Palawan who types "Cebu" wants
///   Cebu; the Palawan places that merely contain those letters come after.
///   Among equally good matches, nearer wins, then narrower places
///   (barangay → city → province → region).
class PlaceSuggestions {
  const PlaceSuggestions._();

  // --------------------------------------------------------------- typing ---

  /// [candidates] that match [query], best first, at most [limit].
  static List<Place> search({
    required String query,
    required Iterable<Place> candidates,
    Place? anchor,
    int limit = 30,
  }) {
    final q = normalize(query);
    if (q.isEmpty) {
      return anchor == null ? const [] : around(candidates: candidates, anchor: anchor, limit: limit);
    }
    final qWords = q.split(' ');

    final scored = <_Scored>[];
    final seen = <Place>{};
    for (final place in candidates) {
      if (!seen.add(place)) continue;
      final tier = _matchTier(place, q, qWords);
      if (tier == null) continue;
      scored.add(_Scored(place, [
        tier,
        _proximity(place, anchor),
        _levelOrder(place.level),
        place.name.length,
      ]));
    }
    scored.sort(_Scored.compare);
    return [for (final s in scored.take(limit)) s.place];
  }

  /// How strongly [place]'s name matches, 0 best; null for no match.
  static int? _matchTier(Place place, String q, List<String> qWords) {
    final name = normalize(place.name);
    if (name == q) return 0;
    if (name.startsWith(q)) {
      // "Cebu City" for "cebu" is a whole-word match; "Cebuano" is not.
      return name.length == q.length || name[q.length] == ' ' ? 1 : 2;
    }
    final inner = name.indexOf(' $q');
    if (inner >= 0) {
      final end = inner + 1 + q.length;
      return end == name.length || name[end] == ' ' ? 3 : 4;
    }
    // Every typed word found across the place and what contains it —
    // "san jose palawan".
    if (qWords.length > 1) {
      final labelWords = normalize(place.label).split(' ');
      if (qWords.every((w) => labelWords.any((lw) => lw.startsWith(w)))) return 5;
    }
    if (name.contains(q)) return 6;
    return null;
  }

  // -------------------------------------------------------- nothing typed ---

  /// Places near [anchor], nearest first.
  static List<Place> around({
    required Iterable<Place> candidates,
    required Place anchor,
    int limit = 30,
  }) {
    final scored = <_Scored>[];
    final seen = <Place>{};
    for (final place in candidates) {
      if (!seen.add(place)) continue;
      final group = _nearbyGroup(place, anchor);
      if (group == null) continue;
      scored.add(_Scored(place, [group, 0, 0, 0], tieBreak: normalize(place.name)));
    }
    scored.sort(_Scored.compare);
    return [for (final s in scored.take(limit)) s.place];
  }

  static int? _nearbyGroup(Place place, Place anchor) {
    if (_same(place, anchor)) return 0;
    final level = place.level;
    if ((level == PlaceLevel.barangay || level == PlaceLevel.street) &&
        _sameChain(place, anchor, PlaceLevel.cityMunicipality)) {
      return 1;
    }
    if (level == PlaceLevel.cityMunicipality && _sameChain(place, anchor, PlaceLevel.cityMunicipality)) {
      return 2;
    }
    if (level == PlaceLevel.cityMunicipality) {
      if (_sameChain(place, anchor, PlaceLevel.province)) return 3;
      // Metro Manila has no province: its cities are neighbours by region.
      if (place.province == null && anchor.nameAt(PlaceLevel.province) == null &&
          _sameChain(place, anchor, PlaceLevel.region)) {
        return 3;
      }
    }
    if (level == PlaceLevel.province && _sameChain(place, anchor, PlaceLevel.province)) return 4;
    if (level == PlaceLevel.region && _sameChain(place, anchor, PlaceLevel.region)) return 5;
    return null;
  }

  // -------------------------------------------------------------- shared ---

  /// 0 when [place] is in the anchor's barangay, 1 its city, 2 its province,
  /// 3 its region, 4 elsewhere or with no anchor.
  static int _proximity(Place place, Place? anchor) {
    if (anchor == null) return 4;
    if (_sameChain(place, anchor, PlaceLevel.barangay)) return 0;
    if (_sameChain(place, anchor, PlaceLevel.cityMunicipality)) return 1;
    if (_sameChain(place, anchor, PlaceLevel.province)) return 2;
    if (_sameChain(place, anchor, PlaceLevel.region)) return 3;
    return 4;
  }

  static int _levelOrder(PlaceLevel level) => switch (level) {
        PlaceLevel.street => 0,
        PlaceLevel.barangay => 0,
        PlaceLevel.cityMunicipality => 1,
        PlaceLevel.province => 2,
        PlaceLevel.region => 3,
      };

  static bool _same(Place a, Place b) {
    if (a.id.isNotEmpty && b.id.isNotEmpty) return a.id == b.id;
    return a.level == b.level && _sameChain(a, b, a.level);
  }

  /// Whether [a] and [b] are in the same place at [level] — the names match
  /// there, and nothing above it contradicts. Two barangays named "San Jose"
  /// in different cities are not the same barangay.
  static bool _sameChain(Place a, Place b, PlaceLevel level) {
    final x = a.nameAt(level);
    final y = b.nameAt(level);
    if (x == null || y == null || normalize(x) != normalize(y)) return false;
    for (var i = level.index - 1; i >= 0; i--) {
      final above = PlaceLevel.values[i];
      final ax = a.nameAt(above);
      final by = b.nameAt(above);
      if (ax != null && by != null && normalize(ax) != normalize(by)) return false;
    }
    return true;
  }

  static const String _accented = 'áàâäãéèêëíìîïóòôöõúùûüñç';
  static const String _plain = 'aaaaaeeeeiiiiooooouuuunc';

  /// Lower-cased, unaccented, punctuation-free, with the prefixes people type
  /// or leave out ("Brgy.", "City of") removed — so "Brgy. Sta. Niño" and
  /// "sta nino" meet.
  static String normalize(String input) {
    var s = input.toLowerCase();
    for (var i = 0; i < _accented.length; i++) {
      s = s.replaceAll(_accented[i], _plain[i]);
    }
    s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceFirst(RegExp(r'^(brgy|bgy|barangay)\s+'), '');
    s = s.replaceFirst(RegExp(r'^(city of|municipality of)\s+'), '');
    return s;
  }
}

class _Scored {
  _Scored(this.place, this.keys, {String? tieBreak}) : tieBreak = tieBreak ?? '';

  final Place place;
  final List<int> keys;
  final String tieBreak;

  static int compare(_Scored a, _Scored b) {
    for (var i = 0; i < a.keys.length; i++) {
      final c = a.keys[i].compareTo(b.keys[i]);
      if (c != 0) return c;
    }
    final t = a.tieBreak.compareTo(b.tieBreak);
    if (t != 0) return t;
    return a.place.label.compareTo(b.place.label);
  }
}
