import 'package:flutter/material.dart';
import '../../../../data/client_account_store.dart';
import '../../../../services/backend/mobile_backend.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/change_password_dialog.dart';
import '../../../../widgets/common_widgets.dart';
import '../../../../widgets/location_widgets.dart';
import '../../../../widgets/password_strength.dart';
import '../../../shared/theme_screen.dart';

class ClientSettingsScreen extends StatefulWidget {
  const ClientSettingsScreen({super.key});

  @override
  State<ClientSettingsScreen> createState() => _ClientSettingsScreenState();
}

class _ClientSettingsScreenState extends State<ClientSettingsScreen> {
  final _store = ClientAccountStore.instance;

  /// Opens the Change Password dialog the Mechanic screen uses too.
  /// The rules below are this screen's own and are unchanged — only where
  /// they run has moved.
  Future<void> _changePassword() async {
    final changed = await showChangePasswordDialog(
      context: context,
      onSubmit: (current, next, confirm) async {
        if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
          return 'Please fill in all fields.';
        }
        if (evaluatePasswordStrength(next) == PasswordStrength.weak) {
          return 'Please choose a stronger password.';
        }
        if (next != confirm) return 'New passwords do not match.';
        if (MobileBackend.instance.usesApi) return changePasswordOnServer(current, next);
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
    // A local Google sign-up leaves the password empty — that's the signal
    // we use to detect it. An On Go API account always has a password, held
    // by the server.
    final hasLocalPassword = MobileBackend.instance.usesApi || !_store.verifyPassword('');

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
          const SectionLabel('APPEARANCE'),
          const SizedBox(height: 8),
          const ThemesSettingsTile(),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 16),
          const SectionLabel('LOCATION'),
          const SizedBox(height: 8),
          const LocationAccessTile(),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 16),
          const SectionLabel('SECURITY'),
          const SizedBox(height: 8),
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
                      'Your account uses Google Sign-In, so there\'s no On Go password to change here. Manage your password from your Google account instead.',
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
