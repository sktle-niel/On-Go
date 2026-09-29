import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  CONTAINER STYLE MODIFIER
// ═══════════════════════════════════════════════════════════════════════════
//
//  WHAT THIS IS
//  Every boxed surface in On Go — cards, dialogs, sheets, inputs, badges,
//  buttons, list rows — is one of the types below. This file decides their
//  SHAPE: corner radius, outline width, outline style.
//
//  It does NOT decide colour. Fill and outline colour come from the active
//  theme's palette, exactly as before. That separation is the point: you can
//  square off every corner in the product without touching a single colour,
//  and the user can switch to Forest Night without changing a single radius.
//
//  ───────────────────────────────────────────────────────────────────────────
//  OUTLINED vs FILLED — why there are two lists
//
//  Some containers are drawn as an outline (an input field, a chip, a plain
//  list row); others are a filled surface with no outline at all (a dialog, a
//  bottom sheet, a primary button). They are configured separately so that
//  turning outlines off — or making every outline 2px — cannot accidentally
//  put a border around a bottom sheet.
//
//      [AppOutlinedContainers]  → shapes that HAVE an outline
//      [AppFilledContainers]    → shapes that do NOT
//
//  ───────────────────────────────────────────────────────────────────────────
//  HOW TO MODIFY
//
//  Square off every card:
//      AppOutlinedContainers.card = AppContainerSpec(radius: 0, ...)
//
//  Make every outline thicker:
//      AppOutlinedContainers.scaleOutlines(2);
//
//  Remove outlines entirely without changing anything else:
//      AppOutlinedContainers.hideOutlines();
//
//  Add a new container type:
//      add a field to whichever of the two classes it belongs in. Nothing
//      else needs to know it exists.
//
//  ───────────────────────────────────────────────────────────────────────────
//  HOW TO USE IT
//
//      Container(
//        decoration: AppOutlinedContainers.card.decoration(
//          fill: c.surface,           // ← colour still comes from the palette
//          outline: c.textmedium,
//        ),
//      )
//
//      // or, where a widget wants a ShapeBorder:
//      shape: AppFilledContainers.dialog.shape()
// ═══════════════════════════════════════════════════════════════════════════

/// How an outline is drawn.
///
/// Flutter can only paint a solid line or nothing at all, so those are the two
/// real options — [none] is how you switch a type's outline off while leaving
/// its radius alone.
enum AppOutlineStyle {
  /// A continuous line. The normal choice.
  solid,

  /// No line at all, whatever the width says.
  none,
}

/// One container type's shape.
@immutable
class AppContainerSpec {
  /// Corner radius, in logical pixels. 0 is a square corner.
  ///
  /// For a fully rounded "pill" — a badge or a stadium button — use a large
  /// number such as 999 rather than trying to guess the widget's height.
  final double radius;

  /// Outline thickness. Ignored when [outlineStyle] is
  /// [AppOutlineStyle.none].
  final double outlineWidth;

  final AppOutlineStyle outlineStyle;

  const AppContainerSpec({
    required this.radius,
    this.outlineWidth = 0,
    this.outlineStyle = AppOutlineStyle.none,
  });

  bool get hasOutline =>
      outlineStyle != AppOutlineStyle.none && outlineWidth > 0;

  AppContainerSpec copyWith({
    double? radius,
    double? outlineWidth,
    AppOutlineStyle? outlineStyle,
  }) =>
      AppContainerSpec(
        radius: radius ?? this.radius,
        outlineWidth: outlineWidth ?? this.outlineWidth,
        outlineStyle: outlineStyle ?? this.outlineStyle,
      );

  BorderRadius get borderRadius => BorderRadius.circular(radius);

  /// The outline, in [color]. Null when this type has none.
  Border? border(Color color) => hasOutline
      ? Border.all(color: color, width: outlineWidth)
      : null;

  /// A ready [BoxDecoration]. Pass the colours from the palette — this file
  /// never chooses one.
  BoxDecoration decoration({Color? fill, Color? outline, List<BoxShadow>? shadows}) =>
      BoxDecoration(
        color: fill,
        borderRadius: borderRadius,
        border: outline == null ? null : border(outline),
        boxShadow: shadows,
      );

  /// The same shape as a [ShapeBorder], for widgets that take one — dialogs,
  /// sheets, buttons, `Material`.
  RoundedRectangleBorder shape({Color? outline}) => RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: (outline != null && hasOutline)
            ? BorderSide(color: outline, width: outlineWidth)
            : BorderSide.none,
      );

  /// The shape as an [OutlineInputBorder], for text fields.
  OutlineInputBorder inputBorder({required Color outline, double? width}) =>
      OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: hasOutline
            ? BorderSide(color: outline, width: width ?? outlineWidth)
            : BorderSide.none,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
//  ▼▼▼  CONTAINERS THAT HAVE AN OUTLINE — EDIT THESE  ▼▼▼
// ═══════════════════════════════════════════════════════════════════════════

/// Shapes drawn with a visible outline.
///
/// Defaults are the values On Go already used, so adopting this changes
/// nothing on screen until you change something here.
class AppOutlinedContainers {
  AppOutlinedContainers._();

  /// **CARD** — the bordered card that most content sits in: a profile
  /// header, a notification, an audit entry.
  static AppContainerSpec card = const AppContainerSpec(
    radius: 12,
    outlineWidth: 1,
    outlineStyle: AppOutlineStyle.solid,
  );

  /// **FIELD** — text inputs and anything shaped like one.
  static AppContainerSpec field = const AppContainerSpec(
    radius: 10,
    outlineWidth: 1,
    outlineStyle: AppOutlineStyle.solid,
  );

  /// **TILE** — a bordered row inside a card: a credential, a detail line.
  static AppContainerSpec tile = const AppContainerSpec(
    radius: 10,
    outlineWidth: 1,
    outlineStyle: AppOutlineStyle.solid,
  );

  /// **CHIP** — filter chips and other tappable pills that carry an outline
  /// when unselected.
  static AppContainerSpec chip = const AppContainerSpec(
    radius: 999,
    outlineWidth: 1,
    outlineStyle: AppOutlineStyle.solid,
  );

  /// **OUTLINED BUTTON** — a secondary action.
  static AppContainerSpec button = const AppContainerSpec(
    radius: 999,
    outlineWidth: 1,
    outlineStyle: AppOutlineStyle.solid,
  );

  /// Every outlined type, so a bulk change can walk them.
  static List<AppContainerSpec> get all => [card, field, tile, chip, button];

  /// Multiplies every outline width by [factor]. `scaleOutlines(2)` doubles
  /// every border in the product.
  static void scaleOutlines(double factor) {
    card = card.copyWith(outlineWidth: card.outlineWidth * factor);
    field = field.copyWith(outlineWidth: field.outlineWidth * factor);
    tile = tile.copyWith(outlineWidth: tile.outlineWidth * factor);
    chip = chip.copyWith(outlineWidth: chip.outlineWidth * factor);
    button = button.copyWith(outlineWidth: button.outlineWidth * factor);
  }

  /// Turns every outline off, leaving radii untouched.
  static void hideOutlines() {
    card = card.copyWith(outlineStyle: AppOutlineStyle.none);
    field = field.copyWith(outlineStyle: AppOutlineStyle.none);
    tile = tile.copyWith(outlineStyle: AppOutlineStyle.none);
    chip = chip.copyWith(outlineStyle: AppOutlineStyle.none);
    button = button.copyWith(outlineStyle: AppOutlineStyle.none);
  }

  static void resetToDefaults() {
    card = const AppContainerSpec(
        radius: 12, outlineWidth: 1, outlineStyle: AppOutlineStyle.solid);
    field = const AppContainerSpec(
        radius: 10, outlineWidth: 1, outlineStyle: AppOutlineStyle.solid);
    tile = const AppContainerSpec(
        radius: 10, outlineWidth: 1, outlineStyle: AppOutlineStyle.solid);
    chip = const AppContainerSpec(
        radius: 999, outlineWidth: 1, outlineStyle: AppOutlineStyle.solid);
    button = const AppContainerSpec(
        radius: 999, outlineWidth: 1, outlineStyle: AppOutlineStyle.solid);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  ▼▼▼  CONTAINERS WITH NO OUTLINE — EDIT THESE  ▼▼▼
// ═══════════════════════════════════════════════════════════════════════════

/// Shapes drawn as a plain filled surface.
///
/// None of these carries an outline, which is why they are kept apart: a
/// bulk change to outlines above cannot reach them.
class AppFilledContainers {
  AppFilledContainers._();

  /// **SURFACE** — a filled panel inside a screen, with no border.
  static AppContainerSpec surface = const AppContainerSpec(radius: 12);

  /// **DIALOG** — an alert or a confirmation.
  static AppContainerSpec dialog = const AppContainerSpec(radius: 16);

  /// **SHEET** — a bottom sheet. Only its top corners are rounded; see
  /// [sheetTopRadius].
  static AppContainerSpec sheet = const AppContainerSpec(radius: 20);

  /// **BADGE** — a status pill: `active`, `Moderator`, a notification count.
  static AppContainerSpec badge = const AppContainerSpec(radius: 999);

  /// **PRIMARY BUTTON** — the filled call to action.
  static AppContainerSpec button = const AppContainerSpec(radius: 999);

  /// **SNACKBAR / TOOLTIP** — transient overlays.
  static AppContainerSpec overlay = const AppContainerSpec(radius: 10);

  /// A sheet's corners: rounded on top, square where it meets the edge.
  static BorderRadius get sheetTopRadius =>
      BorderRadius.vertical(top: Radius.circular(sheet.radius));

  static List<AppContainerSpec> get all =>
      [surface, dialog, sheet, badge, button, overlay];

  static void resetToDefaults() {
    surface = const AppContainerSpec(radius: 12);
    dialog = const AppContainerSpec(radius: 16);
    sheet = const AppContainerSpec(radius: 20);
    badge = const AppContainerSpec(radius: 999);
    button = const AppContainerSpec(radius: 999);
    overlay = const AppContainerSpec(radius: 10);
  }
}
