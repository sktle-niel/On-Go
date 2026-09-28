import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  GLASS
// ═══════════════════════════════════════════════════════════════════════════
//
//  The look the client side of the app is drawn in, after iOS: a dark page
//  with the brand colour glowing through it, and surfaces that read as
//  frosted glass laid over the glow.
//
//  Two kinds of surface, and the difference is about speed:
//
//   * A plain [GlassPanel] — a translucent fill lit from the top left, and a
//     hairline. Over a dark, glowing page that already reads as glass, and it
//     costs no more than a coloured box, so every card in a scrolling list is
//     one of these.
//   * `GlassPanel(blur: true)`, [GlassNavBar], [GlassSegmented],
//     [GlassSearchField] — a real backdrop blur, kept for the few things that
//     float over content, where the blur is actually seen.
//
//  Everything reads the palette, so the same widgets work on a light theme:
//  the glass turns milky white and the glow softens.
// ═══════════════════════════════════════════════════════════════════════════

/// Shared values for glass surfaces.
class Glass {
  Glass._();

  static bool get _dark => AppColors.isDark;

  /// A glass surface's fill, lit from the top left: brighter there, fading
  /// towards the far corner. [tint] colours it, for a card that carries a
  /// state.
  static List<Color> fill({Color? tint}) {
    if (_dark) {
      if (tint != null) return [tint.withValues(alpha: 0.22), tint.withValues(alpha: 0.05)];
      return [Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0.035)];
    }
    if (tint != null) {
      return [
        Color.alphaBlend(tint.withValues(alpha: 0.10), Colors.white),
        Colors.white.withValues(alpha: 0.80),
      ];
    }
    return [Colors.white.withValues(alpha: 0.94), Colors.white.withValues(alpha: 0.76)];
  }

  /// The hairline round a glass surface.
  static Color get edge =>
      _dark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.07);

  /// A floating surface's own colour, under its blur.
  static Color get floating =>
      _dark ? const Color(0xB3141416) : Colors.white.withValues(alpha: 0.80);

  /// The soft shadow a light-theme glass surface needs to lift off the page.
  /// None on a dark theme, where a shadow cannot be seen.
  static List<BoxShadow>? get lift => _dark
      ? null
      : const [BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 8))];

  /// The blur behind a floating surface.
  static ui.ImageFilter get blur => ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24);

  /// The status bar over a glass page: light on a dark page, dark on a light
  /// one, and never a bar of its own colour.
  static SystemUiOverlayStyle get overlay => (_dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
      .copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: AppColors.background);

  /// A white that reads on the glow: pure on a dark page, the ink on a light
  /// one. For a "Play now" style button and a chosen segment.
  static Color get contrast => _dark ? Colors.white : AppColors.textdark;

  /// What goes on [contrast].
  static Color get onContrast => _dark ? const Color(0xFF111114) : Colors.white;
}

/// The page glass is laid over: the palette's background, deepened towards
/// the brand colour at the top, with two soft glows of it.
class GlassBackdrop extends StatelessWidget {
  final Widget? child;

  const GlassBackdrop({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final dark = AppColors.isDark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(c.background, c.primarydark, dark ? 0.30 : 0.05)!,
            c.background,
            c.background,
          ],
          stops: const [0, 0.45, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The two glows sit behind everything and take no taps.
          IgnorePointer(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  top: -180,
                  left: -120,
                  right: -120,
                  height: 460,
                  child: _Glow(color: c.primary, alpha: dark ? 0.34 : 0.12),
                ),
                Positioned(
                  bottom: -220,
                  left: -180,
                  width: 460,
                  height: 460,
                  child: _Glow(color: c.primarydark, alpha: dark ? 0.24 : 0.07),
                ),
              ],
            ),
          ),
          ?child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double alpha;

  const _Glow({required this.color, required this.alpha});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

/// A glass surface: a card, a tile, a sheet.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// A real backdrop blur. Only for something that floats over content.
  final bool blur;

  /// Colours the glass, for a card that carries a state.
  final Color? tint;
  final VoidCallback? onTap;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.blur = false,
    this.tint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: blur ? [Glass.floating, Glass.floating] : Glass.fill(tint: tint),
        ),
        border: Border.all(color: Glass.edge),
        boxShadow: blur ? null : Glass.lift,
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap != null) {
      body = Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, borderRadius: r, child: body),
      );
    }
    if (!blur) return body;
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(filter: Glass.blur, child: body),
    );
  }
}

/// A glyph lit from above, for glass: white fading slightly towards the brand
/// colour at the bottom, as if the glow were showing through it.
class GlassGlyph extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? color;

  const GlassGlyph(this.icon, {super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) {
    final base = color ?? Glass.contrast;
    final low = Color.lerp(base, AppColors.primary, AppColors.isDark ? 0.30 : 0.55)!;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [base, low],
      ).createShader(bounds),
      child: Icon(icon, size: size, color: base),
    );
  }
}

/// A round glass button with a glyph: call, chat, the bell, the menu.
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;
  final Color? color;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size = 40,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onPressed,
                customBorder: const CircleBorder(),
                child: Ink(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: Glass.fill(tint: color),
                    ),
                    border: Border.all(color: Glass.edge),
                  ),
                  child: Icon(icon, size: size * 0.48, color: color ?? AppColors.textdark),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How a [GlassPillButton] is filled.
enum GlassPillStyle {
  /// White on a dark page: the "Play now" button. The main thing on a card.
  contrast,

  /// The brand colour, for the one action a screen is for.
  brand,

  /// Glass, for the other action beside the main one.
  ghost,
}

/// A small pill button for a card or a sheet.
class GlassPillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final GlassPillStyle style;
  final IconData? icon;

  const GlassPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = GlassPillStyle.contrast,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final (Color? fill, Color ink, Color? border) = switch (style) {
      GlassPillStyle.contrast => (Glass.contrast, Glass.onContrast, null),
      GlassPillStyle.brand => (c.primary, c.textlight, null),
      GlassPillStyle.ghost => (null, c.textdark, Glass.edge),
    };
    return PressScale(
      enabled: onPressed != null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          customBorder: const StadiumBorder(),
          child: Ink(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: ShapeDecoration(
              shape: StadiumBorder(side: border == null ? BorderSide.none : BorderSide(color: border)),
              color: fill,
              gradient: fill == null
                  ? LinearGradient(colors: Glass.fill(), begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 16, color: ink), const SizedBox(width: 6)],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A search-shaped glass field that opens something rather than taking text.
class GlassSearchField extends StatelessWidget {
  final String hint;
  final VoidCallback onTap;

  const GlassSearchField({super.key, required this.hint, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    return Semantics(
      button: true,
      label: hint,
      child: GlassPanel(
        blur: true,
        radius: 18,
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(Icons.search_rounded, size: 22, color: c.textmedium),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: c.textmedium),
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of choices on one glass track, the chosen one lit: "Quotes",
/// "Booked", "Ongoing". Each can carry a count.
class GlassSegmented extends StatelessWidget {
  final List<String> labels;
  final List<int>? counts;
  final int index;
  final ValueChanged<int> onChanged;

  const GlassSegmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.counts,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: Glass.blur,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Glass.floating,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Glass.edge),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: _Segment(
                      label: labels[i],
                      count: counts == null ? 0 : counts![i],
                      selected: i == index,
                      onTap: () => onChanged(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _Segment({required this.label, required this.count, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final ink = selected ? Glass.onContrast : c.textmedium;
    return Semantics(
      button: true,
      selected: selected,
      label: count > 0 ? '$label, $count' : label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.enter,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? Glass.contrast : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w600, color: ink),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected ? c.primary : Glass.edge,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? c.textlight : c.textdark,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One tab of a [GlassNavBar].
class GlassNavItem {
  final IconData icon;
  final IconData? activeIcon;
  final String label;

  const GlassNavItem({required this.icon, required this.label, this.activeIcon});
}

/// The tab bar: a glass pill floating above the bottom edge, the chosen tab
/// a glowing disc in the brand colour.
///
/// Put it in `Scaffold.bottomNavigationBar` with `extendBody: true`, so the
/// page runs on under the glass; a page then keeps its last row clear of it
/// with `MediaQuery.paddingOf(context).bottom`.
class GlassNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<GlassNavItem> items;

  const GlassNavBar({super.key, required this.currentIndex, required this.onTap, required this.items});

  static const double barHeight = 70;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    // A tab bar's labels keep their size: they are read at a glance, and a
    // bar that grew with the text would crowd the page it floats over.
    return MediaQuery.withNoTextScaling(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 10 + bottom),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(barHeight / 2),
              child: BackdropFilter(
                filter: Glass.blur,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Glass.floating,
                    borderRadius: BorderRadius.circular(barHeight / 2),
                    border: Border.all(color: Glass.edge),
                  ),
                  child: SizedBox(
                    height: barHeight,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Row(
                        children: [
                          for (var i = 0; i < items.length; i++)
                            Expanded(
                              child: _GlassNavButton(
                                item: items[i],
                                selected: i == currentIndex,
                                onTap: () => onTap(i),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassNavButton extends StatelessWidget {
  final GlassNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _GlassNavButton({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final ink = selected ? c.textlight : c.textmedium;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: AppMotion.normal,
            curve: AppMotion.enter,
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color.lerp(c.primary, Colors.white, 0.16)!, c.primarydark],
                    )
                  : null,
              boxShadow: selected
                  ? [BoxShadow(color: c.primary.withValues(alpha: 0.55), blurRadius: 18, spreadRadius: -2)]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(selected ? (item.activeIcon ?? item.icon) : item.icon, size: 22, color: ink),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
