import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  TEXT STYLE MODIFIER
// ═══════════════════════════════════════════════════════════════════════════
//
//  WHAT THIS IS
//  Every piece of text in On Go — phone app and admin console — belongs to one
//  of the categories defined below. This file is where they are defined.
//  Change a number here and every screen using that category follows.
//
//  This is NOT the colour system. Colours live in `app_palette.dart` and are
//  chosen by the user's theme; this file decides SIZE, WEIGHT and TYPEFACE
//  only. The two never touch, so you can restyle the type without disturbing
//  a single colour.
//
//  ───────────────────────────────────────────────────────────────────────────
//  THE FOUR THINGS YOU CAN CHANGE
//
//   1. FONT SIZE      → the `size:` line of a category below.
//   2. FONT WEIGHT    → the `weight:` line of a category below.
//   3. FONT/TYPEFACE  → `AppTextStyles.fontFamily` for everything, or the
//                       `fontFamily:` line of a single category for just that
//                       one. See "CHANGING THE FONT" below.
//   4. WHICH TEXT USES WHICH CATEGORY
//                     → each category carries a "Used for:" comment listing
//                       real text from the app. To move a piece of text to a
//                       different category, change the style it is given on
//                       its screen to `AppText.<category>(context)`.
//
//  ───────────────────────────────────────────────────────────────────────────
//  THE CATEGORIES AT A GLANCE
//
//    display      28  Bold        ₱ figures, "Welcome!", the rating average
//    headline     20  Bold        the big title at the top of a screen
//    title        18  ExtraBold   app bar titles, the name on a job card
//    sectionTitle 16  ExtraBold   "Top Mechanics", "Personal Information"
//    subtitle     15  SemiBold    settings rows — "Themes", "Change Password"
//    label        14  SemiBold    buttons, tabs, field-group headings
//    body         13  Regular     ordinary text — the default
//    bodySmall    12  Regular     secondary and helper text
//    caption      11  Regular     status chips, timestamps, small print
//    overline     11  SemiBold    UPPERCASE group headings, letter-spaced
//    micro        10  SemiBold    badge counts and the smallest tags
//
//  Eleven, not five, because that is what the app actually uses: a count of
//  every `fontSize:` in the project turns up twelve distinct sizes, with 12,
//  11 and 13 the three most common by a wide margin. Collapsing those into a
//  five-step scale would have meant resizing text that is fine as it is.
//
//  The numbers above ARE the app's current numbers, so nothing moved when this
//  file was written. They are the starting point, not a recommendation.
//
//  ───────────────────────────────────────────────────────────────────────────
//  HOW TO USE A CATEGORY ON A SCREEN
//
//      Text('Service History', style: AppText.sectionTitle(context))
//      Text('₱500',            style: AppText.display(context))
//
//  …or take a category and adjust one thing for this one place:
//
//      Text('Paid', style: AppText.caption(context).copyWith(color: c.success))
//
//  Passing `context` is what makes the text grow on a tablet or a desktop —
//  see [AppTextScale] at the bottom of this file.
//
//  Prefer these over writing `TextStyle(fontSize: 13)` on a screen: a literal
//  size is invisible to this file and will not follow anything you change here.
// ═══════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════
//  CHANGING THE FONT
// ═══════════════════════════════════════════════════════════════════════════
//
//  EVERYTHING AT ONCE — one line in `main()`, before `runApp`:
//
//      AppTextStyles.fontFamily = 'Inter';
//
//  ONE CATEGORY ONLY — uncomment that category's `fontFamily:` line:
//
//      static AppTextSpec display = const AppTextSpec(
//        size: 28,
//        weight: AppFontWeight.extraBold,
//        fontFamily: 'Roboto Mono',   // figures line up in a column
//      );
//
//  A category's own `fontFamily` always wins; leaving it null (the default)
//  means "use AppTextStyles.fontFamily". Every category supports this, so you
//  can pair a display face with a plain body face without touching a screen.
//
//  ⚠ A FONT NAME ONLY WORKS IF THE FONT IS ACTUALLY AVAILABLE.
//  On Go currently bundles NO font files — `pubspec.yaml` has no `fonts:`
//  section — so 'Roboto' below is really "whatever the platform calls Roboto",
//  which is the system face on Android and a fallback elsewhere. Setting
//  `fontFamily = 'Inter'` today would silently fall back to the system font.
//  To make a new font real, do ONE of these first:
//
//    A. Bundle the files. Drop the .ttf files in `assets/fonts/` and add to
//       `pubspec.yaml` (the app's, and `on_go_console/pubspec.yaml` for the
//       console — both front ends need it):
//
//           flutter:
//             fonts:
//               - family: Inter
//                 fonts:
//                   - asset: assets/fonts/Inter-Regular.ttf
//                   - asset: assets/fonts/Inter-SemiBold.ttf
//                     weight: 600
//                   - asset: assets/fonts/Inter-Bold.ttf
//                     weight: 700
//
//       Include a file for every weight this file asks for, or Flutter will
//       fake the missing ones and they will look wrong.
//
//    B. Add the `google_fonts` package and set
//       `AppTextStyles.fontFamily = GoogleFonts.inter().fontFamily;`
//       Convenient, but it downloads the font at runtime the first time.
//
//  ───────────────────────────────────────────────────────────────────────────
//  RECOMMENDED FONTS FOR THIS PROJECT
//
//  On Go's look is rounded and high-contrast: pill buttons, generous corner
//  radii, big ExtraBold peso figures over small quiet labels. It is also a
//  roadside app read one-handed, outdoors, often in a hurry — so legibility at
//  10–13 pt matters more than personality. Faces that suit that:
//
//    - Inter      — clean and modern; drawn for screens, excellent at small
//                   sizes, has a true 800 weight for the ₱ figures. The
//                   safest upgrade from the current look.
//    - Roboto     — simple and highly readable; what the app effectively uses
//                   today, so choosing it changes nothing.
//    - Poppins    — rounded and friendly; geometric circles echo the pill
//                   buttons. Wider than Inter, so check the tight console
//                   tables before committing.
//    - Manrope    — modern and polished; semi-rounded, a little more character
//                   than Inter while staying quiet in body text.
//    - Plus Jakarta Sans — friendly and slightly sporty; good if you want the
//                   headings to feel more branded than the body.
//    - DM Sans    — geometric and compact; the most economical of these in a
//                   narrow column, which suits the console's dense tables.
//
//  All six are free on Google Fonts and ship the 400/500/600/700/800 weights
//  this file uses. Avoid display or condensed faces here — the app's smallest
//  categories (micro 10, caption 11) are where they fall apart.
// ═══════════════════════════════════════════════════════════════════════════

/// The weights, in plain words.
///
/// Flutter's own scale runs w100–w900, which is hard to remember and easy to
/// get wrong. These are the seven On Go uses, and they cover every weight the
/// app currently sets by hand.
///
/// Note [bold] is w700 — the same thing Flutter's own `FontWeight.bold` means —
/// and [extraBold] is w800, the heavier weight the peso figures and screen
/// titles use.
enum AppFontWeight {
  /// w200 — the lightest. Very large numbers only; it disappears at body size.
  thin,

  /// w300 — a softer body, for long passages.
  light,

  /// w400 — the default for ordinary text.
  regular,

  /// w500 — barely heavier than regular. Useful to nudge a label without
  /// making it look like a heading.
  medium,

  /// w600 — labels, settings rows, card titles: stands out a little.
  semiBold,

  /// w700 — genuinely bold. Buttons, amounts, names.
  bold,

  /// w800 — the heaviest On Go uses. Screen titles and the big figures.
  extraBold,
}

extension AppFontWeightValue on AppFontWeight {
  /// The Flutter weight this maps to.
  FontWeight get value {
    switch (this) {
      case AppFontWeight.thin:
        return FontWeight.w200;
      case AppFontWeight.light:
        return FontWeight.w300;
      case AppFontWeight.regular:
        return FontWeight.w400;
      case AppFontWeight.medium:
        return FontWeight.w500;
      case AppFontWeight.semiBold:
        return FontWeight.w600;
      case AppFontWeight.bold:
        return FontWeight.w700;
      case AppFontWeight.extraBold:
        return FontWeight.w800;
    }
  }
}

/// One text category's settings.
///
/// [size] is the size on a PHONE. Tablets and desktops scale up from it — see
/// [AppTextScale] — so you only ever tune the phone number.
@immutable
class AppTextSpec {
  /// Phone size, in logical pixels.
  final double size;

  final AppFontWeight weight;

  /// Typeface for this category alone. Null means "use
  /// [AppTextStyles.fontFamily]".
  ///
  /// Set it when one category should differ from the rest — a monospaced face
  /// for a figure column, a display face for headlines. See "CHANGING THE
  /// FONT" at the top of this file.
  final String? fontFamily;

  /// Line height as a multiple of [size]. Null leaves it to the font.
  final double? height;

  /// Extra space between letters. Small positive values suit uppercase
  /// labels; leave null for body text.
  final double? letterSpacing;

  const AppTextSpec({
    required this.size,
    this.weight = AppFontWeight.regular,
    this.fontFamily,
    this.height,
    this.letterSpacing,
  });

  AppTextSpec copyWith({
    double? size,
    AppFontWeight? weight,
    String? fontFamily,
    double? height,
    double? letterSpacing,
  }) =>
      AppTextSpec(
        size: size ?? this.size,
        weight: weight ?? this.weight,
        fontFamily: fontFamily ?? this.fontFamily,
        height: height ?? this.height,
        letterSpacing: letterSpacing ?? this.letterSpacing,
      );

  /// This category as a [TextStyle], at [scale].
  ///
  /// No colour: colour comes from the theme, and a style that carried one
  /// would fight it. Callers `copyWith(color: …)` where they need a specific
  /// palette role.
  TextStyle resolve({double scale = 1, String? fallbackFamily}) => TextStyle(
        fontSize: size * scale,
        fontWeight: weight.value,
        fontFamily: fontFamily ?? fallbackFamily,
        height: height,
        letterSpacing: letterSpacing,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
//  ▼▼▼  THE CATEGORIES — EDIT THESE  ▼▼▼
// ═══════════════════════════════════════════════════════════════════════════

/// The type scale, and the one place to change it.
///
/// Every default below was taken from the app as it already looks, so adopting
/// this system changed nothing on screen. Change one and every screen using
/// that category follows.
class AppTextStyles {
  AppTextStyles._();

  /// The typeface for every category that does not name its own.
  ///
  /// Null uses the platform default. To change the whole product's face, set
  /// this once in `main()` — and read the ⚠ note at the top of this file
  /// first, because no font is bundled yet:
  ///
  ///     AppTextStyles.fontFamily = 'Inter';
  static String? fontFamily = 'Roboto';

  // ── DISPLAY ──────────────────────────────────────────────────────────────
  //  Used for: "₱1,240.00" available balance and the points total (Mechanic →
  //            Earnings), the amount on the payment sheet, "Welcome!" on the
  //            welcome screen, the "4.8" rating average on a mechanic profile
  //  Size 28 · Weight Bold · Font default
  //  One per screen at most — this is the thing the eye lands on first.
  //  Bold, not ExtraBold: on a plain white surface the heaviest weight reads
  //  as shouting, and a big figure is already the loudest thing on the page.
  static AppTextSpec display = const AppTextSpec(
    size: 28,
    weight: AppFontWeight.bold,
    letterSpacing: -0.4,
    //fontFamily: 'Roboto Mono',   // ← this category only
  );

  // ── HEADLINE ─────────────────────────────────────────────────────────────
  //  Used for: "On Go Registration", "Quotes", "Service History" — the large
  //            title at the top of a full screen, above the content
  //  Size 20 · Weight ExtraBold · Font default
  static AppTextSpec headline = const AppTextSpec(
    size: 20,
    weight: AppFontWeight.bold,
    letterSpacing: -0.2,
    //fontFamily: 'Poppins',       // ← this category only
  );

  // ── TITLE ────────────────────────────────────────────────────────────────
  //  Used for: app bar titles; the person's name at the top of a job or quote
  //            card ("Ana Reyes"); the figure in a profile stat block
  //  Size 18 · Weight ExtraBold · Font default
  static AppTextSpec title = const AppTextSpec(
    size: 18,
    weight: AppFontWeight.semiBold,
    //fontFamily: 'Poppins',       // ← this category only
  );

  // ── SECTION TITLE ────────────────────────────────────────────────────────
  //  Used for: "Top Mechanics", "Service History", "Personal Information",
  //            "How pricing works", "Create Your Account", "Total"
  //  Size 16 · Weight ExtraBold · Font default
  //  The heading over a group of cards, inside a scrolling screen.
  static AppTextSpec sectionTitle = const AppTextSpec(
    size: 16,
    weight: AppFontWeight.semiBold,
    //fontFamily: 'Poppins',       // ← this category only
  );

  // ── SUBTITLE ─────────────────────────────────────────────────────────────
  //  Used for: the label on a settings or sheet row — "Themes", "Change
  //            Password", "Emergency job alerts", "Sort by", "Filter"
  //  Size 15 · Weight SemiBold · Font default
  static AppTextSpec subtitle = const AppTextSpec(
    size: 15,
    weight: AppFontWeight.semiBold,
    //fontFamily: 'Inter',         // ← this category only
  );

  // ── LABEL ────────────────────────────────────────────────────────────────
  //  Used for: button text; tab labels; the heading above a group of fields —
  //            "Details", "Certifications", "Payment", "Common Issues",
  //            "Describe the Problem", "How you earn", "How you spend"
  //  Size 14 · Weight SemiBold · Font default
  static AppTextSpec label = const AppTextSpec(
    size: 14,
    weight: AppFontWeight.semiBold,
    //fontFamily: 'Inter',         // ← this category only
  );

  // ── BODY ─────────────────────────────────────────────────────────────────
  //  Used for: ordinary text — "Available Balance", "Points", "Sex",
  //            "Forgot Password?", "Back to Sign In", "No reviews yet.",
  //            "Face Verification", "Profile Picture"
  //  Size 13 · Weight Regular · Font default
  //  The default for anything with no reason to be anything else.
  static AppTextSpec body = const AppTextSpec(
    size: 13,
    weight: AppFontWeight.regular,
    //fontFamily: 'Inter',         // ← this category only
  );

  // ── BODY SMALL ───────────────────────────────────────────────────────────
  //  Used for: secondary and helper text sitting under something else —
  //            "Need help?", "Contact Support", "Complete all steps to provide
  //            services", "Completed and paid jobs will show up here."
  //  Size 12 · Weight Regular · Font default
  //  The most-used size in the app; if you are unsure between this and body,
  //  body is the one that carries meaning and this is the one that explains it.
  static AppTextSpec bodySmall = const AppTextSpec(
    size: 12,
    weight: AppFontWeight.regular,
    //fontFamily: 'Inter',         // ← this category only
  );

  // ── CAPTION ──────────────────────────────────────────────────────────────
  //  Used for: status chips and small print — "Accepted", "Completed",
  //            "Paid", "ETA", "Location", "Mechanic", and the "09/10/2026"
  //            timestamps down the side of history rows
  //  Size 11 · Weight Regular · Font default
  static AppTextSpec caption = const AppTextSpec(
    size: 11,
    weight: AppFontWeight.regular,
    //fontFamily: 'Inter',         // ← this category only
  );

  // ── OVERLINE ─────────────────────────────────────────────────────────────
  //  Used for: the UPPERCASE heading above a block of fields — "ACCOUNT
  //            INFORMATION" on both profile screens, "APPEARANCE" in settings
  //  Size 11 · Weight SemiBold · Letter spacing 0.6 · Font default
  //  Same size as caption, deliberately: it is the weight and the letter
  //  spacing that make it read as a heading rather than as small print.
  //  Write the text itself in capitals — this style does not capitalise.
  static AppTextSpec overline = const AppTextSpec(
    size: 11,
    weight: AppFontWeight.semiBold,
    letterSpacing: 0.6,
    //fontFamily: 'Inter',         // ← this category only
  );

  // ── MICRO ────────────────────────────────────────────────────────────────
  //  Used for: the smallest tags and counters — the "You" tag on the mechanic
  //            leaderboard, the unread count in the chat badge, "12 reviews"
  //  Size 10 · Weight SemiBold · Font default
  //  Nothing that must be read should be smaller than this.
  static AppTextSpec micro = const AppTextSpec(
    size: 10,
    weight: AppFontWeight.semiBold,
    //fontFamily: 'Inter',         // ← this category only
  );

  // ═════════════════════════════════════════════════════════════════════════
  //  Below here is plumbing — adding a category means adding it to `all` and
  //  to `resetToDefaults`, and adding a getter to [AppText].
  // ═════════════════════════════════════════════════════════════════════════

  /// Every category, largest first.
  ///
  /// This is what makes bulk operations possible without listing the
  /// categories again in three places — see [scaleAll] and [applyFontFamily].
  static List<AppTextSpec> get all => [
        display,
        headline,
        title,
        sectionTitle,
        subtitle,
        label,
        body,
        bodySmall,
        caption,
        overline,
        micro,
      ];

  /// Replaces every category, in the order of [all].
  ///
  /// Private on purpose: bulk edits go through [scaleAll] or
  /// [applyFontFamily], so there is no way to get the order wrong.
  static void _setAll(List<AppTextSpec> specs) {
    display = specs[0];
    headline = specs[1];
    title = specs[2];
    sectionTitle = specs[3];
    subtitle = specs[4];
    label = specs[5];
    body = specs[6];
    bodySmall = specs[7];
    caption = specs[8];
    overline = specs[9];
    micro = specs[10];
  }

  /// Multiplies every category's size by [factor].
  ///
  ///     AppTextStyles.scaleAll(1.1);   // everything 10% larger
  ///
  /// The relationships between the categories are kept; only the overall size
  /// moves. For a permanent change, edit the sizes above instead.
  static void scaleAll(double factor) =>
      _setAll(all.map((s) => s.copyWith(size: s.size * factor)).toList());

  /// Gives every category the same [family], overriding any per-category face.
  ///
  /// Usually you want [fontFamily] instead — that leaves per-category faces
  /// alone. Use this when you want one face and no exceptions.
  static void applyFontFamily(String family) {
    fontFamily = family;
    _setAll(all.map((s) => s.copyWith(fontFamily: family)).toList());
  }

  /// Puts every category back to the shipped defaults — the values written
  /// above. Useful in tests, and as a way back if an experiment goes wrong.
  static void resetToDefaults() {
    fontFamily = 'Roboto';
    display = const AppTextSpec(size: 28, weight: AppFontWeight.bold, letterSpacing: -0.4);
    headline = const AppTextSpec(size: 20, weight: AppFontWeight.bold, letterSpacing: -0.2);
    title = const AppTextSpec(size: 18, weight: AppFontWeight.semiBold);
    sectionTitle = const AppTextSpec(size: 16, weight: AppFontWeight.semiBold);
    subtitle = const AppTextSpec(size: 15, weight: AppFontWeight.semiBold);
    label = const AppTextSpec(size: 14, weight: AppFontWeight.semiBold);
    body = const AppTextSpec(size: 13, weight: AppFontWeight.regular);
    bodySmall = const AppTextSpec(size: 12, weight: AppFontWeight.regular);
    caption = const AppTextSpec(size: 11, weight: AppFontWeight.regular);
    overline = const AppTextSpec(
      size: 11,
      weight: AppFontWeight.semiBold,
      letterSpacing: 0.6,
    );
    micro = const AppTextSpec(size: 10, weight: AppFontWeight.semiBold);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SCALING — how the sizes change with the screen
// ═══════════════════════════════════════════════════════════════════════════

/// How much to multiply a phone size by, given the width of the window.
///
/// A console on a 27-inch monitor is read from much further away than a phone
/// in someone's hand, so the same 13-point body text is genuinely harder to
/// read there. These multipliers are deliberately gentle — big enough to help,
/// small enough that a layout tuned on a phone does not break on a desktop.
///
/// To change how aggressively type grows, edit the three numbers below.
class AppTextScale {
  AppTextScale._();

  /// Below this width the window is a phone.
  static double tabletMinWidth = 600;

  /// At or above this width it is a desktop.
  static double desktopMinWidth = 1024;

  /// Phone: the sizes exactly as written in [AppTextStyles].
  static double phone = 1.0;

  /// Tablet: a little larger.
  static double tablet = 1.05;

  /// Desktop and web: larger again.
  static double desktop = 1.12;

  /// The multiplier for a window [width] logical pixels across.
  static double forWidth(double width) {
    if (width >= desktopMinWidth) return desktop;
    if (width >= tabletMinWidth) return tablet;
    return phone;
  }

  /// The multiplier for the window [context] is in.
  static double of(BuildContext context) =>
      forWidth(MediaQuery.sizeOf(context).width);
}

// ═══════════════════════════════════════════════════════════════════════════
//  USING THE STYLES
// ═══════════════════════════════════════════════════════════════════════════

/// The categories, resolved for the screen they are being drawn on.
///
///     Text('Jobs Done', style: AppText.caption(context))
///
/// Each of these already accounts for screen size. Pass a [BuildContext] and
/// you get the right size for a phone, a tablet or a desktop without asking
/// which one you are on.
class AppText {
  AppText._();

  static TextStyle display(BuildContext context) => _resolve(AppTextStyles.display, context);
  static TextStyle headline(BuildContext context) => _resolve(AppTextStyles.headline, context);
  static TextStyle title(BuildContext context) => _resolve(AppTextStyles.title, context);
  static TextStyle sectionTitle(BuildContext context) => _resolve(AppTextStyles.sectionTitle, context);
  static TextStyle subtitle(BuildContext context) => _resolve(AppTextStyles.subtitle, context);
  static TextStyle label(BuildContext context) => _resolve(AppTextStyles.label, context);
  static TextStyle body(BuildContext context) => _resolve(AppTextStyles.body, context);
  static TextStyle bodySmall(BuildContext context) => _resolve(AppTextStyles.bodySmall, context);
  static TextStyle caption(BuildContext context) => _resolve(AppTextStyles.caption, context);
  static TextStyle overline(BuildContext context) => _resolve(AppTextStyles.overline, context);
  static TextStyle micro(BuildContext context) => _resolve(AppTextStyles.micro, context);

  static TextStyle _resolve(AppTextSpec spec, BuildContext context) =>
      spec.resolve(
        scale: AppTextScale.of(context),
        fallbackFamily: AppTextStyles.fontFamily,
      );

  /// The categories as a Material [TextTheme], for a [ThemeData].
  ///
  /// This is what makes the system reach text that never mentions it: anything
  /// already reading `Theme.of(context).textTheme.bodyMedium` picks up these
  /// settings automatically.
  ///
  /// Material has thirteen slots and On Go has eleven categories, so the
  /// mapping is not one-to-one — `headline`, `bodySmall` and `micro` have no
  /// natural Material slot and are reached through [AppText] instead. The
  /// slots below are mapped to keep every Material widget rendering at exactly
  /// the size it did before this file existed.
  ///
  /// [scale] is fixed at build time here, because a `ThemeData` is built
  /// before there is a window to measure. Each app passes the scale for the
  /// device it is on; a screen wanting live scaling uses [AppText] directly.
  static TextTheme textTheme({double scale = 1, Color? color, Color? mutedColor}) {
    TextStyle style(AppTextSpec spec, Color? c) => spec
        .resolve(scale: scale, fallbackFamily: AppTextStyles.fontFamily)
        .copyWith(color: c);

    return TextTheme(
      // Display → the largest Material slots.
      displayLarge: style(AppTextStyles.display, color),
      displayMedium: style(AppTextStyles.display, color),
      displaySmall: style(AppTextStyles.display, color),
      headlineLarge: style(AppTextStyles.display, color),
      headlineMedium: style(AppTextStyles.display, color),
      headlineSmall: style(AppTextStyles.title, color),
      // Title → Material's title slots.
      titleLarge: style(AppTextStyles.title, color),
      titleMedium: style(AppTextStyles.subtitle, color),
      titleSmall: style(AppTextStyles.subtitle, color),
      // Body → Material's body slots. `bodyLarge` sits one step above body,
      // which is the `label` size at body's weight.
      bodyLarge: style(
        AppTextStyles.body.copyWith(size: AppTextStyles.label.size),
        color,
      ),
      bodyMedium: style(AppTextStyles.body, color),
      // Material's `bodySmall` is the muted small print every screen uses for
      // hints and timestamps — which in this app is the `caption` size, not
      // the `bodySmall` category. Named by Material, not by us.
      bodySmall: style(AppTextStyles.caption, mutedColor ?? color),
      // Labels.
      labelLarge: style(AppTextStyles.subtitle, color),
      labelMedium: style(AppTextStyles.caption, color),
      labelSmall: style(AppTextStyles.overline, mutedColor ?? color),
    );
  }
}
