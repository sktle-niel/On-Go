import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_widgets.dart';
import 'auth/client_registration/client_registration_screen.dart';
import 'auth/mechanic_registration/mechanic_step1_account.dart';
import 'auth/sign_in_screen.dart';

/// The first step of registration: which side of On Go the account is for.
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
    return AuthPage(
      // A way back on the hero when Sign In is underneath; when this screen
      // was opened on its own, the footer link is the way there.
      showBack: Navigator.of(context).canPop(),
      // A way back for someone who already has an account.
      footer: AuthFooterLink(
        prompt: 'Already have an account? ',
        action: 'Sign In',
        onTap: () => _backToSignIn(context),
      ),
      children: [
        const AuthIntro(
          title: 'Create your account',
          subtitle: "Tell us how you'll use On Go.",
        ),
        const SizedBox(height: 24),
        AuthRoleButton(
          icon: Icons.person_rounded,
          label: 'I need a mechanic',
          description: 'Book help for your vehicle, wherever you are.',
          onTap: () => _startClientRegistration(context),
        ),
        const SizedBox(height: 12),
        AuthRoleButton(
          icon: Icons.handyman_rounded,
          label: "I'm a mechanic",
          description: 'Take on jobs near you and earn.',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const MechanicStep1Account(),
            ),
          ),
        ),
      ],
    );
  }
}
