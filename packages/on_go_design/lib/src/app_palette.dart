import 'package:flutter/material.dart';

/// One complete set of app colors.
///
/// Every theme in [AppThemes.all] supplies the exact same properties, so any
/// screen that reads `AppColors.<name>` keeps working no matter which theme is
/// active. The names are semantic, not literal — in a dark palette [textdark]
/// is a *light* color, because its job is "high-emphasis text drawn on
/// [background] / [surface]", not "a dark color".
@immutable
class AppPalette {
  /// Brand color: app bars, primary buttons, drawer headers, accents.
  final Color primary;

  /// A deeper shade of [primary] for pressed states, gradients and headers.
  final Color primarydark;

  /// The scaffold background behind cards and lists.
  final Color background;

  /// Cards, sheets and other raised surfaces sitting on [background].
  final Color surface;

  /// High-emphasis text/icons on [background] and [surface].
  final Color textdark;

  /// Secondary text, hints, dividers and disabled states.
  final Color textmedium;

  /// Text/icons drawn on top of [primary] (app bar titles, drawer header).
  final Color textlight;

  /// Informational accents.
  final Color info;

  /// Positive/approved accents.
  final Color success;

  /// Caution/pending accents.
  final Color warning;

  /// Failure/rejected accents.
  final Color error;

  const AppPalette({
    required this.primary,
    required this.primarydark,
    required this.background,
    required this.surface,
    required this.textdark,
    required this.textmedium,
    required this.textlight,
    required this.info,
    required this.success,
    required this.warning,
    required this.error,
  });
}

/// A theme the user can pick from the Themes screen.
@immutable
class AppThemeOption {
  /// Stable key persisted to storage — never rename an existing one.
  final String id;

  /// The light/dark pair this theme belongs to. Both members share one visual
  /// identity, and Dark Mode / Dynamic Themes swap between them, so a family
  /// should always have exactly one light and one dark member.
  final String family;

  /// Label shown in the Themes list.
  final String label;

  /// One-line description shown under [label].
  final String description;

  /// The colors this theme applies.
  final AppPalette palette;

  /// Whether [background]/[surface] are dark, so Material picks matching
  /// defaults for things we don't style ourselves (ripples, scrollbars…).
  final bool isDark;

  const AppThemeOption({
    required this.id,
    required this.family,
    required this.label,
    required this.description,
    required this.palette,
    this.isDark = false,
  });
}

/// The theme registry.
///
/// To add a theme later: append one [AppThemeOption] to [all] with a new [id]
/// and a full [AppPalette]. Nothing else in the app needs to change — the
/// Themes screen builds itself from this list.
class AppThemes {
  AppThemes._();

  /// Fallback used before storage is read and whenever a saved id is unknown.
  static const String defaultId = 'default';

  static const AppThemeOption _default = AppThemeOption(
    id: defaultId,
    family: 'classic',
    label: 'Default',
    description: 'On Go red on white, with a light grey canvas.',
    // Neutral greys rather than warm ones: the surfaces are meant to
    // disappear so the red, used only where something acts, can carry the
    // brand on its own.
    palette: AppPalette(
      primary: Color(0xFFD11D28),
      primarydark: Color(0xFFA80011),
      background: Color(0xFFF5F5F7),
      surface: Color(0xFFFFFFFF),
      textdark: Color(0xFF1C1C1E),
      textmedium: Color(0xFF6E6E73),
      textlight: Color(0xFFFFFFFF),
      info: Color(0xFF2F6FED),
      success: Color(0xFF1E9E5A),
      warning: Color(0xFFE59500),
      error: Color(0xFFD93025),
    ),
  );

  static const AppThemeOption _dark = AppThemeOption(
    id: 'dark',
    family: 'classic',
    label: 'Dark Default',
    description: 'Low-light palette for night driving and roadside work.',
    isDark: true,
    // The same neutrality after dark: near-black canvas, a slightly lighter
    // surface, and the red lifted a step so it holds its weight on it.
    palette: AppPalette(
      primary: Color(0xFFE0323D),
      primarydark: Color(0xFFB01521),
      background: Color(0xFF121214),
      surface: Color(0xFF1C1C1F),
      textdark: Color(0xFFF2F2F4),
      textmedium: Color(0xFF9C9CA3),
      textlight: Color(0xFFFFFFFF),
      info: Color(0xFF5B9CFF),
      success: Color(0xFF34C77B),
      warning: Color(0xFFF2B33D),
      error: Color(0xFFF0605A),
    ),
  );

  static const AppThemeOption _blue = AppThemeOption(
    id: 'blue',
    family: 'blue',
    label: 'Calm Blue',
    description: 'Calm blue accents on a cool light background.',
    palette: AppPalette(
      primary: Color.fromARGB(255, 21, 101, 192),
      primarydark: Color.fromARGB(255, 13, 71, 161),
      background: Color.fromARGB(255, 240, 244, 250),
      surface: Color.fromARGB(255, 255, 255, 255),
      textdark: Color.fromARGB(255, 15, 23, 42),
      textmedium: Color.fromARGB(255, 100, 116, 139),
      textlight: Color.fromARGB(255, 248, 250, 252),
      info: Color.fromARGB(255, 2, 132, 199),
      success: Color.fromARGB(255, 0, 148, 68),
      warning: Color.fromARGB(255, 234, 158, 0),
      error: Color.fromARGB(255, 208, 32, 47),
    ),
  );

  /// Calm Blue in dark mode: the same blue identity, lifted just enough to
  /// read against a cool near-black while white still sits legibly on it.
  static const AppThemeOption _blueDark = AppThemeOption(
    id: 'blue_dark',
    family: 'blue',
    label: 'Cold Blue',
    description: 'Calm Blue after hours — cool blue on a deep slate ground.',
    isDark: true,
    palette: AppPalette(
      primary: Color.fromARGB(255, 59, 123, 221),
      primarydark: Color.fromARGB(255, 34, 88, 168),
      background: Color.fromARGB(255, 15, 18, 26),
      surface: Color.fromARGB(255, 26, 31, 43),
      textdark: Color.fromARGB(255, 236, 240, 247),
      textmedium: Color.fromARGB(255, 148, 158, 176),
      textlight: Color.fromARGB(255, 248, 250, 252),
      info: Color.fromARGB(255, 56, 176, 233),
      success: Color.fromARGB(255, 46, 196, 130),
      warning: Color.fromARGB(255, 245, 176, 65),
      error: Color.fromARGB(255, 240, 90, 90),
    ),
  );

  /// Ember in light mode: the same orange as [_ember], on the warm off-white
  /// its dark sibling's greys are tinted towards.
  static const AppThemeOption _emberLight = AppThemeOption(
    id: 'ember_light',
    family: 'ember',
    label: 'Ember Light',
    description: 'Ember by daylight — vivid orange on a warm off-white.',
    palette: AppPalette(
      primary: Color.fromARGB(255, 240, 78, 20),
      primarydark: Color.fromARGB(255, 186, 52, 8),
      background: Color.fromARGB(255, 250, 246, 243),
      surface: Color.fromARGB(255, 255, 253, 251),
      textdark: Color.fromARGB(255, 26, 22, 20),
      textmedium: Color.fromARGB(255, 120, 110, 104),
      textlight: Color.fromARGB(255, 255, 250, 247),
      info: Color.fromARGB(255, 33, 118, 214),
      success: Color.fromARGB(255, 24, 150, 82),
      warning: Color.fromARGB(255, 214, 146, 0),
      error: Color.fromARGB(255, 214, 45, 35),
    ),
  );

  static const AppThemeOption _ember = AppThemeOption(
    id: 'ember',
    family: 'ember',
    label: 'Ember',
    description: 'Vivid orange on near-black, with warm off-white text.',
    isDark: true,
    palette: AppPalette(
      primary: Color.fromARGB(255, 240, 78, 20),
      primarydark: Color.fromARGB(255, 186, 52, 8),
      background: Color.fromARGB(255, 13, 13, 14),
      surface: Color.fromARGB(255, 28, 28, 31),
      textdark: Color.fromARGB(255, 245, 244, 242),
      textmedium: Color.fromARGB(255, 154, 152, 148),
      textlight: Color.fromARGB(255, 255, 250, 247),
      info: Color.fromARGB(255, 90, 169, 255),
      success: Color.fromARGB(255, 46, 196, 110),
      warning: Color.fromARGB(255, 250, 176, 5),
      error: Color.fromARGB(255, 255, 92, 82),
    ),
  );

  static const AppThemeOption _forestLight = AppThemeOption(
    id: 'forest',
    family: 'forest',
    label: 'Forest',
    description: 'Deep forest green on a pale green ground.',
    palette: AppPalette(
      primary: Color.fromARGB(255, 52, 172, 22),
      primarydark: Color.fromARGB(255, 26, 106, 9),
      background: Color.fromARGB(255, 253, 255, 250),
      surface: Color.fromARGB(255, 254, 255, 252),
      textdark: Color(0xFF031C04),
      textmedium: Color(0xFF435559),
      textlight: Color(0xFFF4F9EA),
      info: Color.fromARGB(255, 64, 171, 193),
      success: Color.fromARGB(255, 52, 172, 22),
      warning: Color.fromARGB(255, 230, 205, 40),
      error: Color.fromARGB(255, 220, 30, 20),
    ),
  );

  /// Forest after dark: the same colours, with the deep green
  static const AppThemeOption _forestDark = AppThemeOption(
    id: 'forest_dark',
    family: 'forest',
    label: 'Forest Night',
    description: 'The same greens after dark, on deep forest shadow.',
    isDark: true,
    palette: AppPalette(
      primary: Color.fromARGB(255, 52, 172, 22),
      primarydark: Color.fromARGB(255, 34, 132, 12),
      background: Color.fromARGB(255, 13, 15, 16),
      surface: Color.fromARGB(255, 30, 32, 34),
      textdark: Color.fromARGB(255, 245, 255, 252),
      textmedium: Color.fromARGB(255, 152, 156, 155),
      textlight: Color.fromARGB(255, 249, 255, 254),
      info: Color.fromARGB(255, 77, 168, 191),
      success: Color.fromARGB(255, 52, 172, 22),
      warning: Color.fromARGB(255, 230, 205, 40),
      error: Color.fromARGB(255, 214, 53, 41),
    ),
  );

  /// Every selectable theme, in the order the Themes screen lists them —
  /// each family's light mode followed by its dark mode.
  static const List<AppThemeOption> all = [
    _default,
    _dark,
    _blue,
    _blueDark,
    _emberLight,
    _ember,
    _forestLight,
    _forestDark,
  ];

  /// The theme registered under [id], or the Default theme if there is none.
  static AppThemeOption byId(String? id) {
    for (final option in all) {
      if (option.id == id) return option;
    }
    return _default;
  }

  /// Every theme of one brightness, in registry order — what the Themes screen
  /// offers while Dark Mode is off (light) or on (dark).
  static List<AppThemeOption> forBrightness({required bool dark}) =>
      all.where((option) => option.isDark == dark).toList(growable: false);

  /// [option]'s counterpart in the requested brightness — the same visual
  /// identity in its other mode. Returns [option] unchanged if its family has
  /// no member of that brightness.
  static AppThemeOption variantOf(AppThemeOption option, {required bool dark}) {
    if (option.isDark == dark) return option;
    for (final candidate in all) {
      if (candidate.family == option.family && candidate.isDark == dark) {
        return candidate;
      }
    }
    return option;
  }
}
