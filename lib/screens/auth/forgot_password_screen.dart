import 'package:flutter/material.dart';

import '../../data/password_reset_store.dart';
import '../../services/backend/mobile_backend.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_widgets.dart';
import '../../widgets/password_strength.dart';

/// Forgot Password, in three stages on one screen: name the account, enter the
/// one-time code, then set the new password. One screen keeps the reset
/// request tied to a single route, so leaving at any point abandons it cleanly.
///
/// Two backings, one set of stages:
///
/// * **On Go API.** The server issues and delivers the code, and checks it
///   when the new password is saved — there is no separate "verify code" call,
///   so the code stage only checks that it is six digits, and a wrong code
///   comes back with the password and returns the user to the code stage.
///   The server answers the first step the same whether or not the email has
///   an account, and this screen shows that answer as-is.
/// * **Local.** [PasswordResetStore] does all three, and — with no mail service
///   — shows the code on screen.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

enum _Stage { email, code, newPassword }

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _reset = PasswordResetStore.instance;

  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  _Stage _stage = _Stage.email;
  String? _error;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  /// While a request to the API is out.
  bool _busy = false;

  /// The email the API was asked to send a code to, and what it said back.
  String? _sentTo;
  String? _serverNotice;

  bool get _usesApi => MobileBackend.instance.usesApi;

  @override
  void dispose() {
    // Abandoning the screen abandons the reset — a code must not outlive the
    // flow that issued it.
    _reset.cancel();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- stages ---

  void _submitEmail() => _usesApi ? _requestCodeFromServer() : _submitEmailLocally();

  void _submitCode() => _usesApi ? _acceptCodeForServer() : _submitCodeLocally();

  void _submitNewPassword() => _usesApi ? _saveNewPasswordOnServer() : _submitNewPasswordLocally();

  // ------------------------------------------------------------------- API ---

  Future<void> _requestCodeFromServer() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter the email address on your account.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final reply = await MobileBackend.instance.auth.requestPasswordReset(email);
      if (!mounted) return;
      setState(() {
        _sentTo = email;
        _serverNotice = reply.message;
        _codeCtrl.clear();
        _stage = _Stage.code;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.fieldErrors['email'] ?? error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _acceptCodeForServer() {
    if (!RegExp(r'^\d{6}$').hasMatch(_codeCtrl.text.trim())) {
      setState(() => _error = 'Enter the 6-digit code from your email.');
      return;
    }
    setState(() {
      _error = null;
      _stage = _Stage.newPassword;
    });
  }

  Future<void> _saveNewPasswordOnServer() async {
    final password = _passwordCtrl.text;
    final problem = password.length < PasswordResetStore.minPasswordLength
        ? 'Password must be at least ${PasswordResetStore.minPasswordLength} characters'
        : evaluatePasswordStrength(password) == PasswordStrength.weak
            ? 'Please choose a stronger password.'
            : password != _confirmCtrl.text
                ? 'Passwords do not match.'
                : null;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    final email = _sentTo;
    if (email == null) {
      setState(() {
        _error = 'This reset is no longer valid. Start again.';
        _backToEmail();
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await MobileBackend.instance.auth.confirmPasswordReset(
        email: email,
        code: _codeCtrl.text.trim(),
        newPassword: password,
      );
      if (!mounted) return;
      _finish();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        if (error.code == ApiErrorCodes.invalidResetCode) {
          // Wrong, expired or over-tried: the server does not say which.
          _error = error.message;
          _stage = _Stage.code;
          _passwordCtrl.clear();
          _confirmCtrl.clear();
        } else {
          _error = error.fieldErrors['newPassword'] ?? error.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ----------------------------------------------------------------- local ---

  void _submitEmailLocally() {
    final result = _reset.requestReset(_emailCtrl.text);
    setState(() {
      switch (result) {
        case ResetRequestResult.codeSent:
          _error = null;
          _stage = _Stage.code;
        case ResetRequestResult.missingEmail:
          _error = 'Enter the email address on your account.';
        case ResetRequestResult.unknownAccount:
          _error = 'No account was found with that email address.';
      }
    });
  }

  void _submitCodeLocally() {
    final result = _reset.verifyCode(_codeCtrl.text);
    setState(() {
      switch (result) {
        case ResetVerifyResult.verified:
          _error = null;
          _stage = _Stage.newPassword;
        case ResetVerifyResult.incorrectCode:
          _error = 'That code is not correct. '
              '${_reset.attemptsRemaining} attempt${_reset.attemptsRemaining == 1 ? '' : 's'} left.';
        case ResetVerifyResult.expired:
          _error = 'That code has expired. Request a new one.';
          _backToEmail();
        case ResetVerifyResult.tooManyAttempts:
          _error = 'Too many incorrect attempts. Request a new code.';
          _backToEmail();
        case ResetVerifyResult.noActiveRequest:
          _error = 'This reset is no longer active. Start again.';
          _backToEmail();
      }
    });
  }

  void _submitNewPasswordLocally() {
    final result = _reset.completeReset(
      password: _passwordCtrl.text,
      confirmPassword: _confirmCtrl.text,
    );
    if (result == ResetCompleteResult.success) {
      _finish();
      return;
    }
    setState(() {
      switch (result) {
        case ResetCompleteResult.tooShort:
          _error = 'Password must be at least ${PasswordResetStore.minPasswordLength} characters';
        case ResetCompleteResult.tooWeak:
          _error = 'Please choose a stronger password.';
        case ResetCompleteResult.mismatch:
          _error = 'Passwords do not match.';
        case ResetCompleteResult.expired:
          _error = 'This reset expired before it was finished. Start again.';
          _backToEmail();
        case ResetCompleteResult.notVerified:
        case ResetCompleteResult.accountGone:
          _error = 'This reset is no longer valid. Start again.';
          _backToEmail();
        case ResetCompleteResult.success:
          break;
      }
    });
  }

  // ---------------------------------------------------------------- shared ---

  void _finish() {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password updated. Sign in with your new password.'),
        duration: AppDurations.snackBar,
      ),
    );
  }

  void _backToEmail() {
    _stage = _Stage.email;
    _codeCtrl.clear();
    _passwordCtrl.clear();
    _confirmCtrl.clear();
  }

  /// Sends another code to the same address.
  Future<void> _resendCode() async {
    _codeCtrl.clear();
    if (_usesApi) {
      await _requestCodeFromServer();
    } else {
      _submitEmailLocally();
    }
    if (!mounted || _error != null || _stage != _Stage.code) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('A new code is on its way.'), duration: AppDurations.snackBar),
    );
  }

  /// Back to the first stage, to correct a mistyped address.
  void _changeEmail() => setState(() {
        _error = null;
        _backToEmail();
      });

  ButtonStyle get _linkStyle => TextButton.styleFrom(
        foregroundColor: AppColors.textdark,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        minimumSize: const Size(48, 44),
      );

  @override
  Widget build(BuildContext context) {
    final sentTo = _usesApi ? _sentTo : _reset.email;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: AuthBackground(
        child: SafeArea(
          child: AuthBottomCard(
            children: [
              // Centred, like the headings on Welcome and Sign In, which share
              // this card.
              Text(
                switch (_stage) {
                  _Stage.email => 'Reset your password',
                  _Stage.code => 'Enter your code',
                  _Stage.newPassword => 'Create a new password',
                },
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: AppColors.textdark,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.center,
                child: Text(
                  textAlign: TextAlign.center,
                  switch (_stage) {
                    _Stage.email => 'We\'ll send a one-time code to the email on your account.',
                    _Stage.code =>
                      'Enter the 6-digit code sent to ${sentTo ?? 'your email'}. It expires in ${PasswordResetStore.codeLifetime.inMinutes} minutes.',
                    _Stage.newPassword => 'Choose a password you haven\'t used before.',
                  },
                  style: TextStyle(fontSize: 13, color: AppColors.textdark.withValues(alpha: 0.55)),
                ),
              ),
              const SizedBox(height: 20),
              ..._stageFields(),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Row(
                  // The icon stays beside the first line when the message wraps.
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(Icons.error_outline, size: 16, color: AppColors.error),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_error!, style: TextStyle(fontSize: 12, color: AppColors.error)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              AuthWhiteButton(
                label: _busy
                    ? 'Please wait…'
                    : switch (_stage) {
                        _Stage.email => 'Send Code',
                        _Stage.code => 'Verify Code',
                        _Stage.newPassword => 'Save New Password',
                      },
                onPressed: _busy
                    ? null
                    : switch (_stage) {
                        _Stage.email => _submitEmail,
                        _Stage.code => _submitCode,
                        _Stage.newPassword => _submitNewPassword,
                      },
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: _linkStyle,
                  child: Text('Back to Sign In',
                      style: TextStyle(fontSize: 13, color: AppColors.textdark)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _stageFields() {
    switch (_stage) {
      case _Stage.email:
        return [
          AuthTextField(
            hint: 'Email address',
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.send,
            autofillHints: const [AutofillHints.email],
            onSubmitted: (_) {
              if (!_busy) _submitEmail();
            },
          ),
        ];

      case _Stage.code:
        final notice = _usesApi
            ? _serverNotice
            // Stands in for the email the local build cannot send.
            : 'No email service is connected yet, so your code is: ${_reset.visibleCode ?? '—'}';
        return [
          AuthTextField(
            hint: '6-digit code',
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 6,
            onSubmitted: (_) {
              if (!_busy) _submitCode();
            },
          ),
          if (notice != null) ...[
            const SizedBox(height: 12),
            _InfoNote(notice),
          ],
          const SizedBox(height: 4),
          // A code that never arrived, or went to a mistyped address, has a
          // way forward from here, not only "Back to Sign In".
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: _busy ? null : _resendCode,
                style: _linkStyle,
                child: Text('Resend code', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textdark)),
              ),
              TextButton(
                onPressed: _busy ? null : _changeEmail,
                style: _linkStyle,
                child: Text('Change email', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textdark)),
              ),
            ],
          ),
        ];

      case _Stage.newPassword:
        return [
          AuthTextField(
            hint: 'New password',
            controller: _passwordCtrl,
            obscure: _obscurePassword,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            onChanged: (_) => setState(() {}),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: AppColors.textdark.withValues(alpha: 0.55),
                size: 20,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          PasswordStrengthMeter(password: _passwordCtrl.text),
          const SizedBox(height: 16),
          AuthTextField(
            hint: 'Confirm new password',
            controller: _confirmCtrl,
            obscure: _obscureConfirm,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            onSubmitted: (_) {
              if (!_busy) _submitNewPassword();
            },
            onChanged: (_) => setState(() {}),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: AppColors.textdark.withValues(alpha: 0.55),
                size: 20,
              ),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
          PasswordMatchIndicator(
            password: _passwordCtrl.text,
            confirmPassword: _confirmCtrl.text,
          ),
        ];
    }
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: AppColors.info),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: AppColors.info)),
          ),
        ],
      ),
    );
  }
}
