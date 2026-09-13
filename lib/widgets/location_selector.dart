import 'dart:async';

import 'package:flutter/material.dart';
import 'package:on_go_shared/on_go_shared.dart';

import '../services/location/location_service.dart';
import '../services/location/place_directory.dart';
import '../services/location/place_suggestions.dart';
import '../theme/app_theme.dart';

/// What the location field holds right now.
class SelectedLocation {
  const SelectedLocation({required this.text, this.place, this.gps});

  /// Exactly what the field shows.
  final String text;

  /// The place chosen from suggestions, or resolved from GPS. Null for text
  /// the user typed and left as it is.
  final Place? place;

  /// The device fix, when the location came from GPS. The only source of
  /// coordinates precise enough to detect a mechanic's arrival.
  final LocationUpdate? gps;

  bool get isFromDevice => gps != null;
}

/// One location field that is a search box, a dropdown and a current-location
/// button at once.
///
/// * Tap it → nearby places (when the device's location is known) or the
///   broadest places to browse from.
/// * Type → matching places, ranked by how well they match and then by how
///   near they are.
/// * Pick one → it stays in the field; tap × to clear and start again.
/// * Browse → drill from province to city to barangay instead of scrolling.
/// * Use current location → the device's real position, kept up to date while
///   the field is following it; typing or picking a place stops following.
///
/// Nothing here reads GPS or permissions directly — that is
/// [LocationService]. Nothing here knows where place names come from — that
/// is [PlaceDirectory]. With no directory, the field is a plain text field
/// with a current-location button; with no [ReverseGeocoder], a GPS position
/// is shown as its coordinates.
class LocationSelector extends StatefulWidget {
  const LocationSelector({
    super.key,
    required this.controller,
    required this.onChanged,
    this.directory,
    this.geocoder,
    this.service,
    this.hintText = 'Search or type your location',
  });

  final TextEditingController controller;

  /// Called whenever what the field holds changes — typed, picked, located or
  /// cleared (null).
  final ValueChanged<SelectedLocation?> onChanged;

  final PlaceDirectory? directory;
  final ReverseGeocoder? geocoder;
  final LocationService? service;
  final String hintText;

  @override
  State<LocationSelector> createState() => _LocationSelectorState();
}

class _LocationSelectorState extends State<LocationSelector> {
  final _focus = FocusNode();
  final Object _tapGroup = Object();

  LocationService get _location => widget.service ?? LocationService.instance;

  bool _open = false;
  bool _directoryReady = false;
  bool _searching = false;
  List<Place> _results = const [];

  /// What the user typed since opening the list. Until they type, the field's
  /// existing value is a choice, not a query — tapping a filled field shows
  /// what is nearby rather than searching for its own label.
  bool _typedSinceOpen = false;
  String _lastText = '';
  bool _writingText = false;

  /// Browsing: the places drilled into, broadest first. [_browseAll] with an
  /// empty trail is the top of the hierarchy.
  List<Place> _trail = const [];
  bool _browseAll = false;

  /// Where the device is, in the directory's terms — what "nearby" means.
  Place? _anchor;

  bool _followingGps = false;
  bool _resolving = false;
  bool _tracking = false;
  LocationUpdate? _followed;

  String? _problem;
  LocationAccess? _problemAccess;

  Timer? _debounce;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _lastText = widget.controller.text;
    widget.controller.addListener(_onTextChanged);
    _location.addListener(_onLocationChanged);
    _focus.addListener(() {
      if (_focus.hasFocus) _openList();
    });
    _prepare();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onTextChanged);
    _location.removeListener(_onLocationChanged);
    _stopFollowing();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final directory = widget.directory;
    if (directory != null) {
      try {
        final ready = await directory.isAvailable();
        if (mounted) setState(() => _directoryReady = ready);
      } catch (_) {}
    }
    // "Nearby" from the last position this device knew — never a prompt.
    final known = _location.bestKnown;
    if (known != null) await _placeFor(known.point);
  }

  // ------------------------------------------------------------ the text ---

  void _onTextChanged() {
    final text = widget.controller.text;
    if (_writingText || text == _lastText) return;
    _lastText = text;

    // Typing over a GPS location makes it a location the user is writing.
    _stopFollowing();
    _problem = null;
    widget.onChanged(text.isEmpty ? null : SelectedLocation(text: text));

    if (text.isEmpty) {
      _typedSinceOpen = false;
    } else {
      _typedSinceOpen = true;
      _trail = const [];
      _browseAll = false;
      if (!_open) setState(() => _open = true);
    }
    _scheduleRefresh();
  }

  void _write(String text) {
    _writingText = true;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _lastText = text;
    _writingText = false;
  }

  void _clear() {
    _stopFollowing();
    _write('');
    widget.onChanged(null);
    setState(() {
      _problem = null;
      _typedSinceOpen = false;
      _trail = const [];
      _browseAll = false;
      _open = true;
    });
    _focus.requestFocus();
    _refresh();
  }

  // ------------------------------------------------------------ the list ---

  void _openList() {
    if (_open) return;
    setState(() {
      _open = true;
      _typedSinceOpen = false;
    });
    _refresh();
  }

  void _closeList() {
    if (!_open) return;
    setState(() {
      _open = false;
      _trail = const [];
      _browseAll = false;
    });
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), _refresh);
  }

  Future<void> _refresh() async {
    final directory = widget.directory;
    if (directory == null || !_directoryReady) {
      if (mounted) setState(() => _results = const []);
      return;
    }

    final query = _typedSinceOpen ? widget.controller.text.trim() : '';
    final generation = ++_generation;
    setState(() => _searching = true);

    List<Place> results;
    try {
      if (_trail.isNotEmpty) {
        final inside = await directory.childrenOf(_trail.last);
        results = query.isEmpty
            ? ([...inside]..sort((a, b) => a.name.compareTo(b.name)))
            : PlaceSuggestions.search(query: query, candidates: inside, anchor: _anchor, limit: 200);
      } else if (query.isNotEmpty) {
        results = PlaceSuggestions.search(
          query: query,
          candidates: await directory.search(query, near: _anchor),
          anchor: _anchor,
        );
      } else if (_anchor != null && !_browseAll) {
        results = PlaceSuggestions.around(
          candidates: await directory.around(_anchor!),
          anchor: _anchor!,
        );
      } else {
        results = [...await directory.topLevel()]..sort((a, b) => a.name.compareTo(b.name));
      }
    } catch (_) {
      results = const [];
    }

    if (!mounted || generation != _generation) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  void _pick(Place place) {
    _stopFollowing();
    _write(place.label);
    widget.onChanged(SelectedLocation(text: place.label, place: place));
    _focus.unfocus();
    setState(() => _problem = null);
    _closeList();
  }

  void _browseInto(Place place) {
    setState(() {
      _trail = [..._trail, place];
      _typedSinceOpen = false;
    });
    _refresh();
  }

  void _browseTo(int depth) {
    setState(() {
      _trail = _trail.sublist(0, depth);
      _browseAll = true;
      _typedSinceOpen = false;
    });
    _refresh();
  }

  void _showNearby() {
    setState(() {
      _trail = const [];
      _browseAll = false;
      _typedSinceOpen = false;
    });
    _refresh();
  }

  // ------------------------------------------------------------- the GPS ---

  Future<void> _useCurrentLocation() async {
    setState(() {
      _problem = null;
      _followingGps = true;
    });
    final result = await _location.locate();
    if (!mounted) return;

    switch (result) {
      case LocationFound(:final update):
        if (!identical(update, _followed)) await _applyFix(update, fresh: true);
        _startFollowing();
      case LocationNotFound(:final failure):
        setState(() {
          _followingGps = false;
          _problem = failure.message;
          _problemAccess = _location.access;
        });
    }
  }

  void _onLocationChanged() {
    if (!mounted) return;
    setState(() {}); // the loading state and access hints repaint
    if (!_followingGps) return;
    final update = _location.current;
    if (update == null || identical(update, _followed)) return;
    _applyFix(update);
  }

  /// Puts a device fix in the field. A small move keeps the text and just
  /// refreshes the coordinates; a real one resolves the address again.
  Future<void> _applyFix(LocationUpdate update, {bool fresh = false}) async {
    final previous = _followed;
    _followed = update;

    if (!fresh && previous != null && previous.point.distanceTo(update.point) < 50) {
      widget.onChanged(SelectedLocation(text: widget.controller.text, place: _anchor, gps: update));
      return;
    }

    setState(() => _resolving = true);
    final place = await _placeFor(update.point);
    if (!mounted || !_followingGps || !identical(_followed, update)) return;

    final text = place?.label ??
        'Near ${update.point.latitude.toStringAsFixed(5)}, ${update.point.longitude.toStringAsFixed(5)}';
    _write(text);
    setState(() => _resolving = false);
    widget.onChanged(SelectedLocation(text: text, place: place, gps: update));
  }

  /// The readable place at [point], placed into the directory when possible —
  /// and remembered as the anchor "nearby" is measured from.
  Future<Place?> _placeFor(GeoPoint point) async {
    final geocoder = widget.geocoder;
    if (geocoder == null) return null;

    Place? resolved;
    try {
      resolved = await geocoder.placeAt(point);
    } catch (_) {
      resolved = null;
    }
    if (resolved == null) return null;

    Place? inDirectory;
    final directory = widget.directory;
    if (directory != null && _directoryReady) {
      try {
        inDirectory = await directory.match(
          barangay: resolved.nameAt(PlaceLevel.barangay),
          cityMunicipality: resolved.nameAt(PlaceLevel.cityMunicipality),
          province: resolved.nameAt(PlaceLevel.province),
          region: resolved.nameAt(PlaceLevel.region),
        );
      } catch (_) {}
    }

    if (mounted) {
      setState(() => _anchor = inDirectory ?? resolved);
      if (_open && !_typedSinceOpen && _trail.isEmpty) _refresh();
    }
    // Shown as the geocoder had it — it may know the street; ranked by the
    // directory's record of the same place.
    return resolved;
  }

  void _startFollowing() {
    if (_tracking) return;
    _tracking = true;
    _location.startTracking();
  }

  void _stopFollowing() {
    _followingGps = false;
    _followed = null;
    _resolving = false;
    if (_tracking) {
      _tracking = false;
      _location.stopTracking();
    }
  }

  // --------------------------------------------------------------- build ---

  @override
  Widget build(BuildContext context) {
    final locating = _location.isLocating;
    final busy = locating || _resolving;
    final muted = AppColors.textdark.withValues(alpha: 0.55);
    final fix = _followingGps ? _followed : null;
    final roughFix = fix != null && (fix.isPoorAccuracy || _location.isApproximate);

    return TapRegion(
      groupId: _tapGroup,
      onTapOutside: (_) {
        if (!_open) return;
        _focus.unfocus();
        _closeList();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: widget.controller,
            focusNode: _focus,
            groupId: _tapGroup,
            onTap: _openList,
            onTapOutside: (_) {},
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _closeList(),
            decoration: InputDecoration(
              hintText: widget.hintText,
              prefixIcon: Icon(
                _followingGps ? Icons.my_location : Icons.location_on_outlined,
                size: 20,
                color: _followingGps ? AppColors.primary : muted,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                      ),
                    )
                  else if (widget.controller.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear location',
                      icon: Icon(Icons.close, size: 18, color: muted),
                      onPressed: _clear,
                    ),
                  IconButton(
                    tooltip: _open ? 'Hide suggestions' : 'Show suggestions',
                    icon: Icon(_open ? Icons.expand_less : Icons.expand_more, color: muted),
                    onPressed: () {
                      if (_open) {
                        _focus.unfocus();
                        _closeList();
                      } else {
                        _focus.requestFocus();
                        _openList();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: locating ? null : _useCurrentLocation,
              icon: locating
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    )
                  : Icon(Icons.my_location, size: 16, color: AppColors.primary),
              label: Text(
                locating ? 'Getting location…' : 'Use Current Location',
                style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
            ),
          ),
          if (_problem != null) ...[
            const SizedBox(height: 4),
            _LocationProblem(
              message: _problem!,
              access: _problemAccess,
              onRetry: _useCurrentLocation,
              onOpenSettings: () => _location.openSettingsFor(_problemAccess ?? _location.access),
            ),
          ],
          if (roughFix) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.info_outline, size: 12, color: AppColors.warning),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    fix.accuracyMeters != null
                        ? 'Location is approximate (±${fix.accuracyMeters!.round()} m) — check it, or pick your barangay.'
                        : 'Location is approximate — check it, or pick your barangay.',
                    style: TextStyle(fontSize: 11, color: AppColors.warning),
                  ),
                ),
              ],
            ),
          ],
          if (_open) _panel(context, muted),
        ],
      ),
    );
  }

  Widget _panel(BuildContext context, Color muted) {
    final maxHeight = (MediaQuery.sizeOf(context).height * 0.42).clamp(220.0, 380.0);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.textdark.withValues(alpha: 0.15)),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _currentLocationRow(muted),
            Divider(height: 1, color: AppColors.textdark.withValues(alpha: 0.1)),
            if (widget.directory != null && _directoryReady && !_typedSinceOpen) _breadcrumbs(muted),
            Flexible(child: _body(muted)),
          ],
        ),
      ),
    );
  }

  Widget _currentLocationRow(Color muted) {
    final locating = _location.isLocating;
    final String title;
    String? subtitle;
    if (locating) {
      title = 'Finding your location…';
    } else if (_resolving) {
      title = 'Getting the address…';
    } else if (_followingGps) {
      title = 'Using your current location';
      subtitle = widget.controller.text;
    } else {
      title = 'Use current location';
      subtitle = switch (_location.access) {
        LocationAccess.notDetermined || LocationAccess.denied => 'Allow location access to fill this in',
        LocationAccess.deniedForever => 'Location is off for On Go in your phone\'s settings',
        LocationAccess.servicesDisabled => 'Location services are off on this device',
        _ => null,
      };
    }

    return InkWell(
      onTap: locating ? null : _useCurrentLocation,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Icon(_followingGps ? Icons.gps_fixed : Icons.my_location, size: 20, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary)),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: muted)),
                  ],
                ),
              ),
              if (locating || _resolving)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Near you · All places › Palawan › Puerto Princesa City" — where the
  /// list is, and a way back up.
  Widget _breadcrumbs(Color muted) {
    final chips = <Widget>[];
    void add(String label, bool selected, VoidCallback onTap) {
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          selected: selected,
          onSelected: (_) => onTap(),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.padded,
        ),
      ));
    }

    final browsing = _browseAll || _trail.isNotEmpty;
    if (_anchor != null) add('Near you', !browsing, _showNearby);
    add('All places', browsing && _trail.isEmpty, () => _browseTo(0));
    for (var i = 0; i < _trail.length; i++) {
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Icon(Icons.chevron_right, size: 16, color: muted),
      ));
      add(_trail[i].name, i == _trail.length - 1, () => _browseTo(i + 1));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
      child: Row(children: chips),
    );
  }

  Widget _body(Color muted) {
    Widget message(IconData icon, String text) => Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: muted),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: muted))),
            ],
          ),
        );

    if (widget.directory == null || !_directoryReady) {
      return message(
        Icons.edit_location_alt_outlined,
        'Place suggestions aren\'t available right now. Type your location, or use your current location.',
      );
    }
    if (_searching && _results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (_results.isEmpty) {
      final query = widget.controller.text.trim();
      return message(
        Icons.search_off,
        _typedSinceOpen && query.isNotEmpty
            ? 'No places match "$query". You can keep what you typed.'
            : 'Start typing to find your barangay, city or province.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 6),
      shrinkWrap: true,
      itemCount: _results.length,
      itemBuilder: (context, index) => _placeRow(_results[index], muted),
    );
  }

  Widget _placeRow(Place place, Color muted) {
    final canBrowse = place.level.index < PlaceLevel.barangay.index;
    return InkWell(
      onTap: () => _pick(place),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 6, canBrowse ? 2 : 14, 6),
          child: Row(
            children: [
              Icon(_iconFor(place.level), size: 20, color: muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(place.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(place.context,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: muted)),
                  ],
                ),
              ),
              if (canBrowse)
                IconButton(
                  tooltip: 'Places in ${place.name}',
                  icon: Icon(Icons.chevron_right, color: muted),
                  onPressed: () => _browseInto(place),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(PlaceLevel level) => switch (level) {
        PlaceLevel.region => Icons.public,
        PlaceLevel.province => Icons.map_outlined,
        PlaceLevel.cityMunicipality => Icons.location_city_outlined,
        PlaceLevel.barangay => Icons.location_on_outlined,
        PlaceLevel.street => Icons.signpost_outlined,
      };
}

/// Why the current location could not be used, and the one thing to do next.
class _LocationProblem extends StatelessWidget {
  const _LocationProblem({
    required this.message,
    required this.access,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final String message;
  final LocationAccess? access;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final needsSettings = access == LocationAccess.deniedForever || access == LocationAccess.servicesDisabled;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.location_off_outlined, size: 18, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 12, color: AppColors.textdark)),
          ),
          TextButton(
            onPressed: needsSettings ? onOpenSettings : onRetry,
            child: Text(needsSettings ? 'Settings' : 'Try again'),
          ),
        ],
      ),
    );
  }
}
