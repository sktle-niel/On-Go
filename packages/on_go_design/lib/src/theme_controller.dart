import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_palette.dart';

/// Holds the theme the user picked, the appearance switches that go with it,
/// and persists all of it across restarts.
///
/// Follows the same singleton-[ChangeNotifier] pattern as the stores in
/// `lib/data/`: screens read `ThemeController.instance` directly and listen to
/// it when they need to rebuild. `AppColors` reads its colors from here, so
/// every screen picks up a new theme without changing how it reads colors.
///
/// Everything is stored in shared_preferences (already a dependency, see
/// `pubspec.yaml`).
class ThemeController extends ChangeNotifier {
  ThemeController._internal();
  static final ThemeController instance = ThemeController._internal();

  static const String _themeKey = 'app_theme_id';
  static const String _darkModeKey = 'app_dark_mode';
  static const String _dynamicKey = 'app_dynamic_themes';
  static const String _warmKey = 'app_warm_filter';

  /// Dynamic Themes treats this hour (inclusive) as the start of daytime.
  static const int dayStartHour = 6;

  /// …and this hour (inclusive) as the start of night.
  static const int nightStartHour = 18;

  /// Top of the Warm Filter range; 0 means the filter is off.
  ///
  /// The range is continuous — any value between 0 and this is valid, not
  /// just the whole numbers. It stays a 0..10 scale purely because that is
  /// what the readout shows.
  static const double maxWarmFilter = 10;

  /// How often Dynamic Themes re-checks the clock. Only the day/night boundary
  /// matters, so a minute is plenty.
  static const Duration _dynamicTick = Duration(minutes: 1);

  AppThemeOption _selected = AppThemes.byId(AppThemes.defaultId);
  bool _darkMode = false;
  bool _dynamicThemes = false;
  double _warmFilter = 0;
  Timer? _dynamicTimer;

  /// The active theme option (Default until [load] finds a saved one).
  AppThemeOption get selected => _selected;

  /// Id of the active theme — what the Themes screen ticks.
  String get selectedId => _selected.id;

  /// The colors every screen draws with, via `AppColors`.
  AppPalette get palette => _selected.palette;

  /// The Dark Mode switch. Off by default. Ignored while [dynamicThemes] is on
  /// — the clock decides then — but kept so it applies again when that is
  /// switched back off.
  bool get darkMode => _darkMode;

  /// The Dynamic Themes switch: follow the time of day instead of [darkMode].
  bool get dynamicThemes => _dynamicThemes;

  /// Warm Filter strength, 0 (off) to [maxWarmFilter] (warmest).
  ///
  /// Continuous: any value in the range, not only the whole numbers, so the
  /// tint follows the slider exactly as it is dragged.
  double get warmFilter => _warmFilter;

  /// [warmFilter] as the readout shows it: `Off` at zero, otherwise the level
  /// to at most one decimal place — `3` at a whole number, `3.4` between two.
  ///
  /// Lives here so the Themes screen, the console's Appearance page and the
  /// console's settings summary all phrase it identically.
  String get warmFilterLabel {
    if (_warmFilter <= 0) return 'Off';
    final rounded = (_warmFilter * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
  }

  /// Whether dark themes are in force right now — the clock while Dynamic
  /// Themes is on, otherwise the Dark Mode switch.
  bool get isDarkModeActive => _dynamicThemes ? isNightNow : _darkMode;

  /// True between [nightStartHour] and [dayStartHour].
  static bool get isNightNow {
    final hour = DateTime.now().hour;
    return hour < dayStartHour || hour >= nightStartHour;
  }

  /// The themes the picker offers right now: those matching
  /// [isDarkModeActive], so the list is all-light or all-dark.
  List<AppThemeOption> get availableThemes =>
      AppThemes.forBrightness(dark: isDarkModeActive);

  /// Reads everything saved. Safe to call before `runApp`; a storage failure
  /// just leaves the defaults in place rather than blocking startup.
  ///
  /// [darkByDefault] is where the Dark Mode switch starts for someone who has
  /// never touched it: the mobile app opens dark, the console light. A saved
  /// choice always wins.
  Future<void> load({bool darkByDefault = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedId = prefs.getString(_themeKey);

      _darkMode = prefs.getBool(_darkModeKey) ?? darkByDefault;
      _dynamicThemes = prefs.getBool(_dynamicKey) ?? false;
      // Read untyped: the level used to be stored as a whole number, so an
      // install from before it went continuous still has an int under this
      // key and `getDouble` would throw on it.
      final storedWarm = prefs.get(_warmKey);
      _warmFilter = storedWarm is num ? storedWarm.toDouble().clamp(0.0, maxWarmFilter) : 0.0;
      // Land on the variant the current mode calls for, so a night-time start
      // with Dynamic Themes on opens dark rather than flipping a beat later.
      _selected = AppThemes.variantOf(AppThemes.byId(storedId), dark: isDarkModeActive);

      if (_dynamicThemes) _startDynamicTimer();
      notifyListeners();

      // The stored id either named a theme that no longer exists, or named the
      // other half of the family we just switched to. Either way, write back
      // what is actually in force.
      if (storedId != _selected.id) {
        await prefs.setString(_themeKey, _selected.id);
      }
    } catch (_) {
      // No stored preference available — keep the defaults.
    }
  }

  /// Switches to the theme registered under [id] and remembers the choice.
  /// An unknown id falls back to the Default theme.
  Future<void> select(String id) async {
    final option = AppThemes.byId(id);
    if (option.id == _selected.id) return;
    _selected = option;
    notifyListeners();
    await _writeThemeId();
  }

  /// Turns Dark Mode on or off, carrying the current theme over to its
  /// counterpart in the new mode. A no-op while [dynamicThemes] owns the mode.
  Future<void> setDarkMode(bool value) async {
    if (_dynamicThemes || _darkMode == value) return;
    _darkMode = value;
    _applyBrightness();
    await _write((prefs) => prefs.setBool(_darkModeKey, value));
    await _writeThemeId();
  }

  /// Turns Dynamic Themes on or off. Switching it off leaves the brightness
  /// where the clock had it rather than snapping back, so nothing jumps.
  Future<void> setDynamicThemes(bool value) async {
    if (_dynamicThemes == value) return;
    _dynamicThemes = value;
    if (value) {
      _startDynamicTimer();
    } else {
      _stopDynamicTimer();
      _darkMode = _selected.isDark;
    }
    _applyBrightness();
    await _write((prefs) async {
      await prefs.setBool(_dynamicKey, value);
      await prefs.setBool(_darkModeKey, _darkMode);
    });
    await _writeThemeId();
  }

  /// Sets the Warm Filter strength, clamped to 0..[maxWarmFilter]. Any value
  /// in the range is allowed, not just whole numbers.
  ///
  /// Pass `save: false` while a drag is in flight: the level applies and the
  /// tint updates as usual, but nothing is written to storage. A drag emits a
  /// value every frame, and each one would otherwise be a separate write.
  /// Call once more without it when the drag ends to record where it landed.
  Future<void> setWarmFilter(double level, {bool save = true}) async {
    final clamped = level.clamp(0.0, maxWarmFilter);
    if (clamped != _warmFilter) {
      _warmFilter = clamped;
      notifyListeners();
    }
    // Deliberately outside that check: the end of a drag asks to save a level
    // the last frame already applied, and skipping it would lose the setting.
    if (save) await _write((prefs) => prefs.setDouble(_warmKey, clamped));
  }

  /// Moves [_selected] to whichever variant the current mode calls for.
  void _applyBrightness() {
    final wanted = AppThemes.variantOf(_selected, dark: isDarkModeActive);
    if (wanted.id != _selected.id) _selected = wanted;
    notifyListeners();
  }

  void _startDynamicTimer() {
    _dynamicTimer?.cancel();
    _dynamicTimer = Timer.periodic(_dynamicTick, (_) => _onDynamicTick());
  }

  void _stopDynamicTimer() {
    _dynamicTimer?.cancel();
    _dynamicTimer = null;
  }

  void _onDynamicTick() {
    if (!_dynamicThemes) return;
    final wanted = AppThemes.variantOf(_selected, dark: isDarkModeActive);
    if (wanted.id == _selected.id) return;
    _selected = wanted;
    notifyListeners();
    _writeThemeId();
  }

  Future<void> _writeThemeId() => _write((prefs) => prefs.setString(_themeKey, _selected.id));

  Future<void> _write(Future<void> Function(SharedPreferences prefs) action) async {
    try {
      await action(await SharedPreferences.getInstance());
    } catch (_) {
      // The change still applies for this session even if it can't be saved.
    }
  }

  @visibleForTesting
  void debugTickDynamicThemes() => _onDynamicTick();
}
