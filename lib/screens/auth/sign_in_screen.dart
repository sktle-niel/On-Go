import 'package:flutter/material.dart';

import '../../services/backend/mobile_backend.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_widgets.dart';
import '../welcome_screen.dart';
import 'auth_routing.dart';
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

  @override
  Widget build(BuildContext context) {
    final usesApi = MobileBackend.instance.usesApi;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: AuthBackground(
        child: SafeArea(
          child: AuthBottomCard(
            children: [
              Text(
                'Welcome back',
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
                'Sign in to find help or take on jobs',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textdark),
              ),
              const SizedBox(height: 24),
              AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AuthTextField(
                      // The API signs in by email; the local build also takes
                      // the demo usernames.
                      hint: usesApi ? 'Email' : 'Username',
                      controller: _usernameCtrl,
                      keyboardType: usesApi ? TextInputType.emailAddress : TextInputType.text,
                      textInputAction: TextInputAction.next,
                      autofillHints: [usesApi ? AutofillHints.email : AutofillHints.username],
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      hint: 'Password',
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
                          color: AppColors.textdark.withValues(alpha: 0.55),
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
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                  ),
                  // A real tap area; with zero padding and no minimum size the
                  // link was only as big as its letters.
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textdark,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    minimumSize: const Size(48, 44),
                  ),
                  child: Text(
                    'Forgot Password?',
                    style: TextStyle(color: AppColors.textdark, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AuthWhiteButton(
                label: _signingIn ? 'Signing In…' : 'Sign In',
                onPressed: _signingIn ? null : _handleSignIn,
              ),

              const SizedBox(height: 16),
              // Wrap, not Row: at a large system text scale the prompt and the
              // link no longer fit side by side, and the link drops to its own
              // line instead of overflowing. Identical to a centred Row when it
              // does fit.
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    "Don't have account? ",
                    style: TextStyle(fontSize: 13, color: AppColors.textdark),
                  ),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textdark,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      minimumSize: const Size(48, 44),
                    ),
                    child: Text(
                      'Sign Up',
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
