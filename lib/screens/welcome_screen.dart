import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import 'auth/client_registration/client_registration_screen.dart';
import 'auth/mechanic_registration/mechanic_step1_account.dart';
import 'auth/sign_in_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  Future<void> _startClientRegistration(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      // No shape here: the theme's sheet shape, like every other sheet.
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              // 16 on the sides, the same indent as the ListTiles below, so
              // the heading lines up with their icons.
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sign up as Client', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text('Choose how you\'d like to create your account',
                      style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55))),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.g_mobiledata_rounded, color: AppColors.primary),
              title: const Text('Continue with Google'),
              onTap: () => Navigator.pop(ctx, 'google'),
            ),
            ListTile(
              leading: Icon(Icons.edit_note, color: AppColors.primary),
              title: const Text('Fill up manually'),
              onTap: () => Navigator.pop(ctx, 'manual'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (choice == null || !context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClientRegistrationScreen(startWithGoogle: choice == 'google'),
      ),
    );
  }

  /// Sign In is usually the screen underneath; when it is not, it replaces
  /// this one.
  void _backToSignIn(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacement(MaterialPageRoute(builder: (_) => const SignInScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: AuthBackground(
        child: SafeArea(
          child: AuthBottomCard(
            children: [
              Text(
                'Welcome!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: AppColors.textdark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please select how you want to register',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textdark),
              ),
              const SizedBox(height: 24),
              AuthRoleButton(
                icon: Icons.person_outline,
                label: 'Register as Client',
                onTap: () => _startClientRegistration(context),
              ),
              const SizedBox(height: 12),
              AuthRoleButton(
                icon: Icons.work_outline,
                label: 'Register as Mechanic',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MechanicStep1Account(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // A way back for someone who already has an account.
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Already have an account? ',
                    style: TextStyle(fontSize: 13, color: AppColors.textdark),
                  ),
                  TextButton(
                    onPressed: () => _backToSignIn(context),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textdark,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      minimumSize: const Size(48, 44),
                    ),
                    child: Text(
                      'Sign In',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textdark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
