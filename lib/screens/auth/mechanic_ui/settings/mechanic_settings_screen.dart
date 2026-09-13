import 'package:flutter/material.dart';
import '../../../../data/mechanic_account_store.dart';
import '../../../../data/mechanic_settings_store.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/change_password_dialog.dart';
import '../../../../widgets/location_widgets.dart';
import '../../../../widgets/password_strength.dart';
import '../../../shared/theme_screen.dart';

class MechanicSettingsScreen extends StatefulWidget {
  const MechanicSettingsScreen({super.key});

  @override
  State<MechanicSettingsScreen> createState() => _MechanicSettingsScreenState();
}

class _MechanicSettingsScreenState extends State<MechanicSettingsScreen> {
  final _store = MechanicAccountStore.instance;

  /// Opens the Change Password dialog the Client screen uses too.
  /// The rules below are this screen's own and are unchanged — only where
  /// they run has moved.
  Future<void> _changePassword() async {
    final changed = await showChangePasswordDialog(
      context: context,
      onSubmit: (current, next, confirm) {
        if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
          return 'Please fill in all fields.';
        }
        if (evaluatePasswordStrength(next) == PasswordStrength.weak) {
          return 'Please choose a stronger password.';
        }
        if (next != confirm) return 'New passwords do not match.';
        final ok = _store.changePassword(currentPassword: current, newPassword: next);
        if (!ok) return 'Current password is incorrect.';
        return null;
      },
    );

    if (changed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated'), duration: AppDurations.snackBar),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLocalPassword = !_store.verifyPassword('');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textmedium,
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: context.layout.pageInsets,
        children: [
          Text('APPEARANCE', style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55), fontWeight: FontWeight.w600)),
          const ThemesSettingsTile(),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 16),
          Text('NOTIFICATIONS', style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55), fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: MechanicSettingsStore.instance,
            builder: (context, _) => Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Emergency job alerts', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        'Pulse the Emergency button when new emergency jobs are posted',
                        style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
                      ),
                    ],
                  ),
                ),
                // Colors come from the app-wide switchTheme.
                Switch(
                  value: MechanicSettingsStore.instance.emergencyPulseEnabled,
                  onChanged: MechanicSettingsStore.instance.setEmergencyPulseEnabled,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 16),
          Text('LOCATION', style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55), fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const LocationAccessTile(),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 16),
          Text('SECURITY', style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55), fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (!hasLocalPassword) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: AppColors.textdark.withValues(alpha: 0.55)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This account doesn\'t have a password set — that\'s expected for Demo Mode. Register a real mechanic account to set one.',
                      style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            ChangePasswordSettingsTile(
              subtitle: 'Update the password for this account',
              onTap: _changePassword,
            ),
          ],
        ],
      ),
    );
  }
}
