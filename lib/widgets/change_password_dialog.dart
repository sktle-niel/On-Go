import 'dart:async';

import 'package:flutter/material.dart';

import '../services/backend/mobile_backend.dart';
import '../theme/app_theme.dart';
import 'password_strength.dart';

/// Changes the signed-in account's password on the On Go API, for a
/// [ChangePasswordAttempt]: the error to show, or null once it changed.
Future<String?> changePasswordOnServer(String current, String next) async {
  try {
    final changed = await MobileBackend.instance.auth.changePassword(
      currentPassword: current,
      newPassword: next,
    );
    return changed ? null : 'Current password is incorrect.';
  } on ApiException catch (error) {
    return error.fieldErrors['newPassword'] ?? error.message;
  }
}

/// Runs one caller's own rules. Return an error to show inside the dialog, or
/// null once the password has actually been changed. May be asynchronous —
/// a change the server makes is — and the dialog waits for it.
typedef ChangePasswordAttempt = FutureOr<String?> Function(
  String current,
  String next,
  String confirm,
);

/// The Change Password dialog, shared by the Client and Mechanic
/// settings screens so both are the same UI rather than two drifting
/// copies. Each screen keeps its own validation by way of [onSubmit].
///
/// Returns true when the password was changed, so the caller can report it
/// however that screen normally does.
Future<bool> showChangePasswordDialog({
  required BuildContext context,
  required ChangePasswordAttempt onSubmit,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => _ChangePasswordDialog(onSubmit: onSubmit),
  );
  return result == true;
}

/// A widget rather than a StatefulBuilder so the controllers are owned by
/// something with a real lifecycle: disposing them by hand when showDialog
/// returns tears them down while the dialog's exit animation is still
/// painting the fields, which throws.
class _ChangePasswordDialog extends StatefulWidget {
  final ChangePasswordAttempt onSubmit;

  const _ChangePasswordDialog({required this.onSubmit});

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final currentController = TextEditingController();
  final newController = TextEditingController();
  final confirmController = TextEditingController();
  String? errorText;

  /// While an attempt is out, so Save cannot send it twice.
  bool saving = false;

  @override
  void dispose() {
    currentController.dispose();
    newController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (saving) return;
    setState(() => saving = true);
    final error = await widget.onSubmit(
      currentController.text,
      newController.text,
      confirmController.text,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        errorText = error;
        saving = false;
      });
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext ctx) {
    void setDialogState(VoidCallback fn) => setState(fn);

    return AlertDialog(
        title: const Text('Change Password'),
        // Scrollable, and never taller than the space the keyboard leaves:
        // the strength meter and match indicator both appear as the user
        // types, and without this the content grows past the dialog and
        // overflows at the bottom.
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.6,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentController,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(labelText: 'Current Password'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newController,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(labelText: 'New Password'),
                ),
                PasswordStrengthMeter(password: newController.text),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onChanged: (_) => setDialogState(() {}),
                  // Done on the keyboard saves, the same as the Save button.
                  onSubmitted: (_) => _save(),
                  decoration: const InputDecoration(labelText: 'Confirm New Password'),
                ),
                PasswordMatchIndicator(
                  password: newController.text,
                  confirmPassword: confirmController.text,
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(errorText!, style: TextStyle(color: AppColors.primary, fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: saving ? null : _save,
            child: Text(saving ? 'Saving…' : 'Save'),
          ),
        ],
      );
  }
}

/// The Settings row that opens [showChangePasswordDialog]. Shared so the three
/// screens present the entry point identically too.
class ChangePasswordSettingsTile extends StatelessWidget {
  final String subtitle;
  final VoidCallback? onTap;

  const ChangePasswordSettingsTile({super.key, required this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.lock_outline, color: AppColors.textdark),
      title: Text('Change Password', style: TextStyle(fontSize: 15, color: AppColors.textdark)),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
      ),
      trailing: Icon(Icons.chevron_right, color: AppColors.textdark.withValues(alpha: 0.55)),
      onTap: onTap,
    );
  }
}
