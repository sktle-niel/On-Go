/// The On Go design system, shared by both front ends.
///
/// The product ships as two applications — the mobile app (Client + Mechanic)
/// and the admin console website (Admin + Moderator) — and they are meant to
/// look like one product. This package is what makes that true rather than
/// merely intended: the theme registry, the palettes, the design tokens and
/// the controller all live here once, so there is no second copy to drift.
///
/// What each app still owns is its own [ThemeData], built from these palettes.
/// A phone wants full-width pill buttons at arm's length; a console wants
/// tighter type and denser controls under a mouse. Same colours, same theme
/// names, same Dark Mode / Dynamic Themes / Warm Filter — different density.
///
/// Adding a theme means appending one [AppThemeOption] to [AppThemes.all].
/// Both applications pick it up with no further change, because both build
/// their pickers from that list.
library;

export 'src/app_chrome.dart';
export 'src/app_colors.dart';
export 'src/app_palette.dart';
export 'src/design_tokens.dart';
export 'src/on_go_bottom_nav.dart';
export 'src/press_scale.dart';
export 'src/theme_controller.dart';
export 'src/ui_container_styles.dart';
export 'src/ui_icon_styles.dart';
export 'src/ui_style.dart';
export 'src/ui_text_styles.dart';
export 'src/warm_filter_slider.dart';
