import 'package:flutter/material.dart';

/// Corner radius scale. Every rounded surface in the app should land on one of
/// these steps rather than picking its own number.
///
/// [pill] is the shape for buttons and badges — fully rounded ends, sized from
/// the widget's own height.
class AppRadii {
  AppRadii._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  static BorderRadius get borderXs => BorderRadius.circular(xs);
  static BorderRadius get borderSm => BorderRadius.circular(sm);
  static BorderRadius get borderMd => BorderRadius.circular(md);
  static BorderRadius get borderLg => BorderRadius.circular(lg);
  static BorderRadius get borderXl => BorderRadius.circular(xl);

  /// Top-rounded sheet corners.
  static BorderRadius get sheetTop => const BorderRadius.vertical(top: Radius.circular(xl));

  static const StadiumBorder pill = StadiumBorder();
}

/// Border thickness scale: hairline dividers and outlines, standard control
/// outlines, and the heavy rule used to underline a section.
class AppBorders {
  AppBorders._();

  static const double thin = 1;
  static const double regular = 2;
  static const double thick = 4;
}

/// The one-pixel rule a minimal surface sits on instead of a shadow.
///
/// A card, the app bar, the navigation bar and a drawer header are all told
/// apart from the page by a hairline in the palette's secondary text colour at
/// low opacity, so the same line reads correctly on a light and a dark theme.
/// Controls that need a firmer edge — an input, an outlined button — use
/// [outline], a step darker.
class AppHairline {
  AppHairline._();

  /// Opacity of a hairline, applied to the palette's `textmedium`.
  static const double alpha = 0.16;

  /// Opacity of a control outline, applied to the same colour.
  static const double outlineAlpha = 0.30;

  static Color of(Color base) => base.withValues(alpha: alpha);

  static Color outline(Color base) => base.withValues(alpha: outlineAlpha);

  static BorderSide side(Color base, {double width = AppBorders.thin}) =>
      BorderSide(color: of(base), width: width);
}

/// Elevation levels, as Material elevation values.
///
/// * [flat] — sits directly on the page. Cards live here now: a hairline, not
///   a shadow, is what sets them apart from the page.
/// * [hover] — a control that has lifted slightly.
/// * [raised] — a floating panel, such as a suggestion list over a form.
/// * [modal] — dialogs and sheets over the page.
/// * [popover] — tooltips, toasts and menus above everything.
class AppElevation {
  AppElevation._();

  static const double flat = 0;
  static const double hover = 1;
  static const double raised = 3;
  static const double modal = 8;
  static const double popover = 12;
}

/// Hand-rolled shadows for the widgets that paint their own surface instead of
/// going through Material elevation. The tones mirror [AppElevation].
///
/// Deliberately faint: on a minimal surface a shadow says "this floats", and
/// only panels that really do — a popover, a sheet — should say it. Black
/// rather than a palette color, so the shadow disappears against a dark theme
/// instead of glowing.
class AppShadows {
  AppShadows._();

  static const List<BoxShadow> flat = [];

  static const List<BoxShadow> hover = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 3)),
  ];

  static const List<BoxShadow> modal = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 20, offset: Offset(0, 8)),
  ];

  static const List<BoxShadow> popover = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, 10)),
  ];
}

/// Motion: the few timings and curves the product uses.
///
/// Everything that enters or changes state eases out — it starts at once and
/// settles — because that is what makes an interface feel like it heard the
/// tap. Nothing in the UI runs longer than [slow]; a screen someone opens
/// fifty times a day has no business making them wait for a curve.
class AppMotion {
  AppMotion._();

  /// A pressed control answering the finger.
  static const Duration press = Duration(milliseconds: 120);

  /// A small state change: a colour, a chip, a badge.
  static const Duration fast = Duration(milliseconds: 160);

  /// A panel or a row entering or leaving.
  static const Duration normal = Duration(milliseconds: 220);

  /// A sheet or a drawer.
  static const Duration slow = Duration(milliseconds: 280);

  /// For anything entering, appearing or answering a tap.
  static const Curve enter = Curves.easeOutCubic;

  /// For something already on screen moving to a new place.
  static const Curve move = Curves.easeInOutCubic;

  /// How far a pressed control shrinks: felt more than seen.
  static const double pressScale = 0.97;
}
