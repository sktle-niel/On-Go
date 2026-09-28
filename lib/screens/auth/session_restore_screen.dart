import 'package:flutter/material.dart';

import '../../services/api/mobile_api.dart';
import '../../services/backend/mobile_backend.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_widgets.dart';
import 'auth_routing.dart';
import 'sign_in_screen.dart';

/// The first screen when this device holds a session from an earlier launch.
///
/// Exchanges the stored refresh token for a new session and opens the right
/// shell, or falls back to Sign In: silently when the session is over, with a
/// notice when the server could not be reached (the stored session is kept
/// for next time).
class SessionRestoreScreen extends StatefulWidget {
  const SessionRestoreScreen({super.key});

  @override
  State<SessionRestoreScreen> createState() => _SessionRestoreScreenState();
}

class _SessionRestoreScreenState extends State<SessionRestoreScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  Future<void> _restore() async {
    String? notice;
    try {
      final account = await MobileBackend.instance.auth.restoreSession();
      if (!mounted) return;
      if (account != null) {
        if (enterAppAs(context, account.user)) return;
        // A console account has no business holding a session on a phone.
        await MobileBackend.instance.auth.signOut();
      }
    } on ApiException catch (error) {
      notice = error.kind == ApiErrorKind.unreachable ? restoreUnreachableMessage : error.message;
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => SignInScreen(notice: notice)),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    // The same page Sign In is drawn on, so the hand-over to it is a change
    // of sheet, not a change of scene.
    return AuthPage(
      children: [
        const SizedBox(height: 32),
        Center(
          child: Semantics(
            label: 'Signing you in',
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(color: c.primary, strokeWidth: 3),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Signing you in…',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: c.textmedium),
        ),
      ],
    );
  }
}
