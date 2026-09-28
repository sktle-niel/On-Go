import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'design_tokens.dart';

/// One destination in [OnGoBottomNav].
@immutable
class OnGoNavItem {
  final IconData icon;

  /// Shown when this item is selected. Falls back to [icon] when null.
  final IconData? activeIcon;
  final String label;

  const OnGoNavItem({required this.icon, this.activeIcon, required this.label});
}

/// A flat navigation bar on the page's own surface, set off by a hairline.
///
/// Every destination shows its icon and its label; the selected one is drawn
/// in the brand colour and nothing else moves. A tab is switched dozens of
/// times a day, which is exactly the kind of action that should not animate.
///
/// Drop-in replacement for [BottomNavigationBar] — same [currentIndex] /
/// [onTap] contract, so each shell keeps its own tabs and routing.
class OnGoBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<OnGoNavItem> items;

  const OnGoBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  static const double height = 60;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: AppHairline.side(AppColors.textmedium)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Material(
            type: MaterialType.transparency,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _Destination(
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
    );
  }
}

class _Destination extends StatelessWidget {
  final OnGoNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _Destination({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textmedium;

    return Semantics(
      button: true,
      selected: selected,
      child: InkResponse(
        onTap: onTap,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        highlightColor: Colors.transparent,
        splashColor: AppColors.textdark.withValues(alpha: 0.06),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? (item.activeIcon ?? item.icon) : item.icon, size: 24, color: color),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                height: 1.2,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
