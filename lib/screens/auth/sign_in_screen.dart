import 'package:flutter/material.dart';

import '../../services/backend/mobile_backend.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_widgets.dart';
import 'auth_routing.dart';
import 'client_registration/client_registration_screen.dart';
import 'forgot_password_screen.dart';

/// Sign In for the mobile app, which serves Clients and Mechanics.
///
/// Admin and Moderator are not roles here. They sign in to the On Go admin
/// console, a separate web application, and the server refuses them on this
/// surface (`wrong_surface`) with a message this screen shows as-is.
/// [MobileBackend.auth] decides all of that — this screen only routes
/// whatever role comes back.
class SignInScreen extends StatefulWidget {
  /// Shown once when the screen opens: why the user is here when it was not
  /// their doing — a session that ended, a server that could not be reached.
  final String? notice;

  const SignInScreen({super.key, this.notice});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _signingIn = false;

  @override
  void initState() {
    super.initState();
    final notice = widget.notice;
    if (notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showMessage(notice));
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: AppDurations.snackBar),
    );
  }

  Future<void> _handleSignIn() async {
    if (_signingIn) return;

    // The server needs both, and every refused attempt counts against the
    // sign-in rate limit — so an empty form never leaves the phone.
    if (MobileBackend.instance.usesApi &&
        (_usernameCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty)) {
      _showMessage('Enter your email and password.');
      return;
    }

    setState(() => _signingIn = true);
    try {
      final result = await MobileBackend.instance.auth.signIn(
        SignInRequest(
          identifier: _usernameCtrl.text,
          password: _passwordCtrl.text,
          surface: AppSurface.mobile,
        ),
      );
      if (!mounted) return;

      final user = result.user;
      if (user != null) {
        // The console roles never get this far — the server turns them away
        // first — but one that did must not be left holding a session.
        if (!enterAppAs(context, user)) {
          await MobileBackend.instance.auth.signOut();
          _showMessage(_consoleMessage);
        }
        return;
      }
      _showMessage(result.message ?? _messageFor(result.failure));
    } on ApiException catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  static const String _consoleMessage =
      'Admin and Moderator sign in on the On Go admin console website, not in the app.';

  /// Wording for the local implementation, which reports a failure without a
  /// message. The API always sends its own.
  String _messageFor(SignInFailure? failure) {
    switch (failure) {
      case SignInFailure.wrongSurface:
        return _consoleMessage;
      case SignInFailure.accountInactive:
        return 'That account has been deactivated.';
      case SignInFailure.accountLocked:
        return 'Too many failed attempts. Try again later.';
      case SignInFailure.wrongPassword:
      case SignInFailure.unknownAccount:
      case null:
        return 'Use client or mechanic as the demo username, or sign in with '
            'your registered email and password.';
    }
  }

  void _register({bool withGoogle = false}) => Navigator.push(
        context,
        // Straight to the form: a client's account is the only one opened
        // from the app. Google only fills the form in; the account is On Go's.
        MaterialPageRoute(builder: (_) => ClientRegistrationScreen(startWithGoogle: withGoogle)),
      );

  @override
  Widget build(BuildContext context) {
    final usesApi = MobileBackend.instance.usesApi;

    return AuthPage(
      headline: const AuthHeadline(lead: "Let's get you", accent: 'moving again'),
      footer: AuthFooterLink(
        prompt: "Don't have an account? ",
        action: 'Register',
        onTap: _register,
      ),
      children: [
        const AuthIntro(
          title: 'Welcome back!',
          subtitle: 'Sign in to book a mechanic or take on a job.',
        ),
        const SizedBox(height: 20),
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthTextField(
                // The API signs in by email; the local build also takes
                // the demo usernames.
                label: usesApi ? 'Email' : 'Username',
                icon: usesApi ? Icons.mail_outline_rounded : Icons.person_outline_rounded,
                labelAbove: false,
                autocorrect: false,
                controller: _usernameCtrl,
                keyboardType: usesApi ? TextInputType.emailAddress : TextInputType.text,
                textInputAction: TextInputAction.next,
                autofillHints: [usesApi ? AutofillHints.email : AutofillHints.username],
              ),
              const SizedBox(height: 14),
              AuthTextField(
                label: 'Password',
                icon: Icons.lock_outline_rounded,
                labelAbove: false,
                obscure: _obscurePassword,
                controller: _passwordCtrl,
                // The keyboard's key signs in, so a user does not have
                // to dismiss it to reach the button.
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _handleSignIn(),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: _ForgotLink(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
            ),
          ),
        ),
        const SizedBox(height: 8),
        AuthPrimaryButton(
          label: _signingIn ? 'Signing in…' : 'Sign In',
          busy: _signingIn,
          onPressed: _handleSignIn,
        ),
        const SizedBox(height: 18),
        const AuthDivider(label: 'or'),
        const SizedBox(height: 18),
        AuthSecondaryButton(
          label: 'Sign up with Google',
          leading: const GoogleMark(size: 20),
          onPressed: () => _register(withGoogle: true),
        ),
      ],
    );
  }
}

/// "Forgot password?" in the brand colour, at the right under the fields.
class _ForgotLink extends StatelessWidget {
  final VoidCallback onTap;

  const _ForgotLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      // A real tap area; with zero padding and no minimum size the link was
      // only as big as its letters.
      style: TextButton.styleFrom(
        foregroundColor: AuthScheme.of(context).primary,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        minimumSize: const Size(48, 44),
      ),
      child: const Text(
        'Forgot password?',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}
