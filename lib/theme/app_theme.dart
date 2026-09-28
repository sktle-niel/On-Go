import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_go_design/on_go_design.dart';

/// The design system itself — the palettes, the theme registry, the tokens and
/// [ThemeController] — lives in `package:on_go_design`, shared with the admin
/// console website so both front ends are the same theme system rather than
/// two that resemble each other.
///
/// Re-exported here so every screen keeps importing one file, exactly as
/// before.
export 'package:on_go_design/on_go_design.dart';

export 'auth_background_controller.dart';

/// The responsive layout model — `context.layout`, [ResponsiveBody] and the
/// rest. Exported here so a screen that already imports this file gets it
/// without another import.
export 'app_layout.dart';

/// The mobile app's [ThemeData].
///
/// This is the half the app owns: the colours are shared, the density is not.
/// A phone gets full-width pill buttons and 48-point targets because it is
/// tapped at arm's length; the console builds its own [ThemeData] from the
/// same palettes for a mouse. See `On-Go-Console/lib/src/theme/console_theme.dart`.
///
/// The look is minimal on purpose: one white surface on a light canvas,
/// hairlines where there used to be shadows and bands, and the brand colour
/// kept for the few things that act — a primary button, the selected tab, a
/// badge, a focused field. Everything else is ink on paper.
class AppTheme {
  /// The tint to multiply the whole app by for a Warm Filter level.
  ///
  /// Kept here as the app's entry point into the shared implementation, which
  /// the console uses too — the filter has to behave identically on both.
  static Color? warmFilterTint(double level) => AppWarmFilter.tintFor(level);

  /// The [ThemeData] for the currently selected theme.
  static ThemeData get theme => themeFor(ThemeController.instance.selected);

  /// Builds the [ThemeData] for [option]. Every theme goes through here, so a
  /// new entry in [AppThemes.all] is styled without any extra work.
  static ThemeData themeFor(AppThemeOption option) {
    final c = option.palette;
    final hairline = AppHairline.of(c.textmedium);
    final outline = AppHairline.outline(c.textmedium);

    // Material's own widgets — checkboxes, progress bars, text buttons, the
    // cursor — read `primary` for their accent, so the brand colour reaches
    // them without each one being told.
    final base = option.isDark ? const ColorScheme.dark() : const ColorScheme.light();
    final colorScheme = base.copyWith(
      primary: c.primary,
      onPrimary: c.textlight,
      secondary: c.primary,
      onSecondary: c.textlight,
      surface: c.surface,
      onSurface: c.textdark,
      onSurfaceVariant: c.textmedium,
      error: c.error,
      onError: c.textlight,
      outline: outline,
      outlineVariant: hairline,
      // Material 3 tints elevated surfaces with the primary colour; on a
      // white-and-red product that turns every card faintly pink.
      surfaceTint: Colors.transparent,
    );

    OutlineInputBorder fieldBorder(Color color, double width) => OutlineInputBorder(
          borderRadius: AppOutlinedContainers.field.borderRadius,
          borderSide: BorderSide(color: color, width: width),
        );

    // Chrome and controls name the product's typeface explicitly: a button's
    // text style does not inherit the text theme's family, so without this a
    // change of face in `ui_text_styles.dart` would miss every button.
    final family = AppTextStyles.fontFamily;
    TextStyle chrome(double size, FontWeight weight, {Color? color, double? letterSpacing, double? height}) =>
        TextStyle(fontFamily: family, fontSize: size, fontWeight: weight, color: color, letterSpacing: letterSpacing, height: height);

    return ThemeData(
      brightness: option.isDark ? Brightness.dark : Brightness.light,
      colorScheme: colorScheme,
      primaryColor: c.primary,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.surface,
      cardColor: c.surface,
      dividerColor: hairline,
      // A quieter ripple: ink, not a flash.
      splashColor: c.textdark.withValues(alpha: 0.06),
      highlightColor: c.textdark.withValues(alpha: 0.04),
      fontFamily: AppTextStyles.fontFamily,
      iconTheme: IconThemeData(color: c.textdark),
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.textdark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: hairline, width: AppBorders.thin)),
        titleTextStyle: chrome(18, FontWeight.w600, color: c.textdark, letterSpacing: -0.2),
        iconTheme: IconThemeData(color: c.textdark),
        actionsIconTheme: IconThemeData(color: c.textdark),
        // The bar is light, so the clock and the battery are drawn dark.
        systemOverlayStyle: option.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.surface,
        selectedItemColor: c.primary,
        unselectedItemColor: c.textmedium,
        selectedLabelStyle: chrome(11, FontWeight.w600),
        unselectedLabelStyle: chrome(11, FontWeight.w500),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      // Buttons are pills, full width and 48 points tall on a phone. Flat:
      // the colour is what says "press me", not a shadow.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.textlight,
          disabledBackgroundColor: c.textmedium.withValues(alpha: 0.18),
          disabledForegroundColor: c.textmedium,
          minimumSize: const Size(double.infinity, 48),
          shape: AppRadii.pill,
          elevation: AppElevation.flat,
          shadowColor: Colors.transparent,
          textStyle: chrome(15, FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.textlight,
          minimumSize: const Size(double.infinity, 48),
          shape: AppRadii.pill,
          textStyle: chrome(15, FontWeight.w600),
        ),
      ),
      // The secondary action: ink on an outline, so it never competes with
      // the one red button beside it.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textdark,
          side: BorderSide(color: outline, width: AppBorders.thin),
          minimumSize: const Size(0, 48),
          shape: AppRadii.pill,
          textStyle: chrome(15, FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          shape: AppRadii.pill,
          textStyle: chrome(14, FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // On a dark theme a field is a pane of glass over whatever it sits
        // on, the way the client screens are drawn; on a light one, white.
        fillColor: option.isDark ? Colors.white.withValues(alpha: 0.06) : c.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: fieldBorder(outline, AppBorders.thin),
        enabledBorder: fieldBorder(outline, AppBorders.thin),
        // Focus is the one place a field shows the brand colour.
        focusedBorder: fieldBorder(c.primary, 1.5),
        errorBorder: fieldBorder(c.error, AppBorders.thin),
        focusedErrorBorder: fieldBorder(c.error, 1.5),
        hintStyle: chrome(14, FontWeight.w400, color: c.textmedium),
        errorStyle: chrome(12, FontWeight.w400, color: c.error),
      ),
      // Sizes, weights and typeface come from the UI Style system; the two
      // colours come from the palette. Anything already reading
      // `Theme.of(context).textTheme` therefore follows a change made in
      // `ui_text_styles.dart` without being touched.
      //
      // The scale is fixed at 1 here: a phone is the size these numbers
      // were written for. A screen that wants live scaling across a tablet
      // uses `AppText.body(context)` directly.
      textTheme: AppText.textTheme(
        color: c.textdark,
        mutedColor: c.textmedium,
      ),
      // A card is a white surface on a hairline: flat, with the radius the
      // UI Style system gives every surface. Changing that radius in
      // `ui_container_styles.dart` reaches every card.
      cardTheme: CardThemeData(
        elevation: AppElevation.flat,
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppFilledContainers.surface.borderRadius,
          side: BorderSide(color: hairline, width: AppBorders.thin),
        ),
        margin: EdgeInsets.zero,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.textdark,
        textColor: c.textdark,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: c.textlight,
        elevation: AppElevation.flat,
        highlightElevation: AppElevation.flat,
      ),
      dividerTheme: DividerThemeData(
        color: hairline,
        thickness: AppBorders.thin,
        space: AppBorders.thin,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: AppFilledContainers.dialog.shape(),
        elevation: AppElevation.modal,
        titleTextStyle: chrome(18, FontWeight.w600, color: c.textdark),
        contentTextStyle: chrome(14, FontWeight.w400, color: c.textdark, height: 1.4),
      ),
      // Sheets carry a small handle, which is how a phone says "this can be
      // pulled down" without a close button.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        modalBackgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppFilledContainers.sheetTopRadius),
        elevation: AppElevation.flat,
        modalElevation: AppElevation.flat,
        showDragHandle: true,
        dragHandleColor: c.textmedium.withValues(alpha: 0.35),
        dragHandleSize: const Size(36, 4),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.textdark,
        contentTextStyle: chrome(13, FontWeight.w400, color: c.surface),
        behavior: SnackBarBehavior.floating,
        shape: AppFilledContainers.overlay.shape(),
        elevation: AppElevation.flat,
      ),
      // Badges and filter chips read as pills, outlined until selected.
      chipTheme: ChipThemeData(
        shape: AppRadii.pill,
        side: BorderSide(color: hairline, width: AppBorders.thin),
        backgroundColor: c.surface,
        selectedColor: c.primary.withValues(alpha: 0.12),
        labelStyle: chrome(13, FontWeight.w500, color: c.textdark),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: c.primary, width: AppBorders.regular),
        ),
        labelColor: c.textdark,
        unselectedLabelColor: c.textmedium,
        dividerColor: hairline,
      ),
      // Every Switch in the app, in every shell: an outlined pill with a
      // solid circle inside — textmedium when off, primary when on. Set
      // here rather than screen by screen so a toggle anywhere (settings,
      // forms, dialogs, management screens) looks identical without
      // repeating the colors, and any new one is styled by default.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return c.textmedium.withValues(alpha: 0.3);
          }
          if (states.contains(WidgetState.selected)) return c.primary;
          return c.textmedium.withValues(alpha: 0.55);
        }),
        // No fill in either state — the pill reads as an outline over
        // whatever it sits on, so it looks right on cards and dialogs as
        // well as on the page background.
        trackColor: const WidgetStatePropertyAll(Colors.transparent),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return c.textmedium.withValues(alpha: 0.3);
          }
          if (states.contains(WidgetState.selected)) return c.primary;
          return c.textmedium;
        }),
        // Material 3 drops the outline once a switch is on, because its
        // track is normally filled. Ours never is, so the outline has to be
        // held at the same weight in both states.
        trackOutlineWidth: const WidgetStatePropertyAll(AppBorders.regular),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadii.borderXs),
        side: BorderSide(color: outline, width: 1.5),
      ),
      // Rounded caps on every progress bar, in the brand colour.
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        borderRadius: AppRadii.borderXs,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.popover,
        shape: RoundedRectangleBorder(
          borderRadius: AppFilledContainers.overlay.borderRadius,
          side: BorderSide(color: hairline, width: AppBorders.thin),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.textdark,
          borderRadius: AppRadii.borderSm,
        ),
        textStyle: chrome(12, FontWeight.w400, color: c.surface),
      ),
    );
  }
}
