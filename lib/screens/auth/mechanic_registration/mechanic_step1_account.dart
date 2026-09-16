import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/auth_widgets.dart';
import '../../../data/registration_draft.dart';
import '../../../utils/step_navigator.dart';
import 'mechanic_step2_personal.dart';
import '../../../widgets/password_strength.dart';

class MechanicStep1Account extends StatefulWidget {
  const MechanicStep1Account({super.key});

  @override
  State<MechanicStep1Account> createState() => _MechanicStep1AccountState();
}

class _MechanicStep1AccountState extends State<MechanicStep1Account> {
  final _draft = RegistrationDraft.instance;

  final _usernameCtrl    = TextEditingController();
  final _emailCtrl       = TextEditingController();
  final _passCtrl        = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _obscurePass    = true;
  bool _obscureConfirm = true;
  bool _loaded         = false;

  String? _usernameError;
  String? _emailError;
  String? _passError;
  String? _confirmPassError;

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  Future<void> _loadDraft() async {
    await _draft.load();
    if (!mounted) return;
    setState(() {
      _usernameCtrl.text    = _draft.username;
      _emailCtrl.text       = _draft.email;
      _passCtrl.text        = _draft.password;
      _confirmPassCtrl.text = _draft.confirmPassword;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  void _autosave() {
    _draft.username        = _usernameCtrl.text;
    _draft.email           = _emailCtrl.text;
    _draft.password        = _passCtrl.text;
    _draft.confirmPassword = _confirmPassCtrl.text;
    _draft.saveStep1();
  }

  bool _validate() {
    final username = _usernameCtrl.text.trim();
    final email    = _emailCtrl.text.trim();
    final pass     = _passCtrl.text;
    final confirm  = _confirmPassCtrl.text;

    String? usernameErr, emailErr, passErr, confirmErr;

    if (username.isEmpty) usernameErr = 'Username is required';

    if (email.isEmpty) {
      emailErr = 'Email is required';
    } else if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) {
      emailErr = 'Enter a valid email address';
    }

    if (pass.isEmpty) {
      passErr = 'Password is required';
    } else if (pass.length < 8) {
      passErr = 'Password must be at least 8 characters';
    }

    if (confirm.isEmpty) {
      confirmErr = 'Please confirm your password';
    } else if (pass.isNotEmpty && confirm != pass) {
      confirmErr = 'Passwords do not match';
    }

    setState(() {
      _usernameError    = usernameErr;
      _emailError       = emailErr;
      _passError        = passErr;
      _confirmPassError = confirmErr;
    });

    return usernameErr == null && emailErr == null &&
           passErr == null && confirmErr == null;
  }

  Widget _field({required Widget child, required String? error}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(error,
                style: TextStyle(fontSize: 11, color: AppColors.error)),
          ),
      ],
    );
  }

  // Stepper tap — delegate to shared helper which handles all 5 steps
  void _onStepTapped(int step) => goToRegistrationStep(context, step);

  void _goNext() {
    if (!_validate()) return;
    _draft.username        = _usernameCtrl.text.trim();
    _draft.email           = _emailCtrl.text.trim();
    _draft.password        = _passCtrl.text;
    _draft.confirmPassword = _confirmPassCtrl.text;
    _draft.saveStep1();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MechanicStep2Personal()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const RegistrationHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: context.layout.pageInsets,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RegistrationStepper(
                    currentStep: 1,
                    highestCompletedStep: _draft.highestCompletedStep,
                    onStepTapped: _onStepTapped,
                  ),
                  const SizedBox(height: 20),
                  Text('Create Your Account',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textdark)),
                  const SizedBox(height: 16),

                  _field(
                    error: _usernameError,
                    child: OnGoTextField(
                      label: 'Username',
                      hint: 'juandelacruz',
                      isRequired: true,
                      autofillHints: const [AutofillHints.newUsername],
                      controller: _usernameCtrl,
                      onChanged: (_) {
                        _autosave();
                        if (_usernameError != null) {
                          setState(() => _usernameError = null);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                  _field(
                    error: _emailError,
                    child: OnGoTextField(
                      label: 'Email',
                      hint: 'juandelacruz@gmail.com',
                      isRequired: true,
                      autofillHints: const [AutofillHints.email],
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) {
                        _autosave();
                        if (_emailError != null) {
                          setState(() => _emailError = null);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                                    _field(
                    error: _passError,
                    child: OnGoTextField(
                      label: 'Password',
                      hint: '********',
                      isRequired: true,
                      autofillHints: const [AutofillHints.newPassword],
                      obscure: _obscurePass,
                      controller: _passCtrl,
                      onChanged: (_) {
                        _autosave();
                        setState(() => _passError = null);
                      },
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePass
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                          color: AppColors.textdark.withValues(alpha: 0.55),
                        ),
                        onPressed: () =>
                            setState(() => _obscurePass = !_obscurePass),
                      ),
                    ),
                  ),
                  PasswordStrengthMeter(password: _passCtrl.text),
                  const SizedBox(height: 14),

                  _field(
                    error: _confirmPassError,
                    child: OnGoTextField(
                      label: 'Confirm Password',
                      hint: '********',
                      isRequired: true,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _goNext(),
                      obscure: _obscureConfirm,
                      controller: _confirmPassCtrl,
                      onChanged: (_) {
                        _autosave();
                        // Rebuild on every keystroke so the match indicator
                        // keeps up, clearing the error if one was showing.
                        setState(() => _confirmPassError = null);
                      },
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                          color: AppColors.textdark.withValues(alpha: 0.55),
                        ),
                        onPressed: () => setState(
                            () => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                  ),
                  PasswordMatchIndicator(
                    password: _passCtrl.text,
                    confirmPassword: _confirmPassCtrl.text,
                  ),
                  const SizedBox(height: 28),

                  StepNavButtons(
                    onBack: () => Navigator.maybePop(context),
                    onNext: _goNext,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}