import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

/// Theme picker, shared by the Client and Mechanic shells. The admin console
/// has its own, built on the same palettes.
///
/// The list is built from [AppThemes.all], so adding a theme there is all it
/// takes for it to show up here.
class ThemeScreen extends StatefulWidget {
  const ThemeScreen({super.key});

  @override
  State<ThemeScreen> createState() => _ThemeScreenState();
}

class _ThemeScreenState extends State<ThemeScreen> {
  final _controller = ThemeController.instance;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChange);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _select(AppThemeOption option) async {
    if (option.id == _controller.selectedId) return;
    await _controller.select(option.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${option.label} theme applied'), duration: AppDurations.snackBar),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textlight,
        title: const Text('Themes'),
      ),
      body: ListView(
        padding: context.layout.pageInsets,
        children: [
          const SectionLabel('APPEARANCE'),
          const SizedBox(height: 8),
          Text(
            'Pick a color theme. It applies everywhere in the app and is remembered the next time you open On Go.',
            style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.textdark.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 16),
          _ControlsCard(controller: _controller),
          const SizedBox(height: 20),
          SectionLabel(_controller.isDarkModeActive ? 'DARK THEMES' : 'LIGHT THEMES'),
          const SizedBox(height: 8),
          for (final option in _controller.availableThemes) ...[
            _ThemeOptionCard(
              option: option,
              selected: option.id == _controller.selectedId,
              onTap: () => _select(option),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// Dark Mode, Dynamic Themes and the Warm Filter, grouped above the list.
class _ControlsCard extends StatelessWidget {
  final ThemeController controller;

  const _ControlsCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final dynamicOn = controller.dynamicThemes;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.borderLg,
        border: Border.all(color: AppColors.textmedium.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          _SwitchRow(
            label: 'Dark Mode',
            // Dynamic Themes owns the light/dark decision while it is on, so
            // the switch reports what the clock is doing and can't be moved.
            subtitle: dynamicOn
                ? 'Controlled by Dynamic Themes right now.'
                : 'Show the dark version of each theme.',
            value: controller.isDarkModeActive,
            onChanged: dynamicOn ? null : (v) => controller.setDarkMode(v),
          ),
          Divider(height: 1, color: AppColors.textmedium.withValues(alpha: 0.25)),
          _SwitchRow(
            label: 'Dynamic Themes',
            subtitle: 'Follow the time of day — light from '
                '${ThemeController.dayStartHour}:00, dark from '
                '${ThemeController.nightStartHour}:00.',
            value: dynamicOn,
            onChanged: (v) => controller.setDynamicThemes(v),
          ),
          Divider(height: 1, color: AppColors.textmedium.withValues(alpha: 0.25)),
          _WarmFilterRow(controller: controller),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SwitchRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textdark.withValues(alpha: enabled ? 1 : 0.45),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Colors come from the app-wide switchTheme.
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _WarmFilterRow extends StatelessWidget {
  final ThemeController controller;

  const _WarmFilterRow({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Warm Filter',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textdark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Warms the whole screen for easier reading in low light.',
            style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.textmedium.withValues(alpha: 0.3),
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.12),
              valueIndicatorColor: AppColors.primary,
            ),
            child: WarmFilterSlider(controller: controller),
          ),
        ],
      ),
    );
  }
}

class _ThemeOptionCard extends StatelessWidget {
  final AppThemeOption option;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOptionCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = option.palette;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.textmedium.withValues(alpha: 0.3),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            _PalettePreview(palette: palette),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textdark),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    option.description,
                    style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? AppColors.primary : AppColors.textmedium.withValues(alpha: 0.5),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

/// A small card showing what the theme's key colors look like, so the choice
/// is readable without applying it first.
class _PalettePreview extends StatelessWidget {
  final AppPalette palette;

  const _PalettePreview({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.textmedium.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Container(height: 16, color: palette.primary),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  _Swatch(color: palette.textdark),
                  const SizedBox(width: 4),
                  _Swatch(color: palette.info),
                  const SizedBox(width: 4),
                  _Swatch(color: palette.success),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;

  const _Swatch({required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}

/// The "Themes" row every role's Settings screen shows, so all four shells
/// reach the picker the same way.
class ThemesSettingsTile extends StatelessWidget {
  const ThemesSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.palette_outlined, color: AppColors.textdark),
        title: Text('Themes', style: TextStyle(fontSize: 15, color: AppColors.textdark)),
        subtitle: Text(
          ThemeController.instance.selected.label,
          style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
        ),
        trailing: Icon(Icons.chevron_right, color: AppColors.textdark.withValues(alpha: 0.55)),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ThemeScreen()),
        ),
      ),
    );
  }
}
