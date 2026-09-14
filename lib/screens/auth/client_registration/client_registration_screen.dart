import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../data/client_account_store.dart';
import '../../../services/backend/mobile_backend.dart';
import '../client_ui/client_home_screen.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/auth_widgets.dart';
import '../../../widgets/password_strength.dart';

class ClientRegistrationScreen extends StatefulWidget {
  /// Set when the client picked "Continue with Google" on the popup shown
  /// from WelcomeScreen — triggers Google sign-in automatically as soon as
  /// this screen mounts. If they picked "Fill up manually" instead, this is
  /// false and the form just starts empty.
  final bool startWithGoogle;

  const ClientRegistrationScreen({super.key, this.startWithGoogle = false});

  @override
  State<ClientRegistrationScreen> createState() =>
      _ClientRegistrationScreenState();
}

class _ClientRegistrationScreenState extends State<ClientRegistrationScreen> {
  // ── Controllers ─────────────────────────────────────────────────────────────
  final _emailCtrl       = TextEditingController();
  final _firstNameCtrl   = TextEditingController();
  final _lastNameCtrl    = TextEditingController();
  final _addressCtrl     = TextEditingController();
  final _phoneCtrl       = TextEditingController();
  final _passCtrl        = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  // ── UI state ─────────────────────────────────────────────────────────────────
  bool _obscurePass    = true;
  bool _obscureConfirm = true;
  bool _isLoading      = false;

  // ── Profile photo ─────────────────────────────────────────────────────────────
  File?  _profilePhoto;     // local file from gallery / camera
  final  _picker = ImagePicker();

  // ── Social auth (Google only) ─────────────────────────────────────────────────
  bool    _isSocialLogin  = false;
  String? _socialPhotoUrl;   // remote URL from Google

  // ── Validation errors ─────────────────────────────────────────────────────────
  Map<String, String?> _err = {};

  /// Whether the form asks for a password. A Google sign-up skips it locally,
  /// but an On Go API account always has one — the API has no Google sign-in,
  /// so Google only fills in the name and email.
  bool get _requiresPassword => !_isSocialLogin || MobileBackend.instance.usesApi;

  @override
  void initState() {
    super.initState();
    if (widget.startWithGoogle) {
      // Post-frame so the loading overlay has something to render over.
      WidgetsBinding.instance.addPostFrameCallback((_) => _continueWithGoogle());
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Image picker
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _pickGallery() async {
    final picked = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) {
      setState(() => _profilePhoto = File(picked.path));
    }
  }

  Future<void> _takeSelfie() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() => _profilePhoto = File(picked.path));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Social auth
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _continueWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final account = await GoogleSignIn(scopes: ['email', 'profile']).signIn();
      if (account == null) {
        // Cancelled — fall back to manual entry silently.
        return;
      }

      final parts = (account.displayName ?? '').trim().split(' ');
      setState(() {
        _emailCtrl.text     = account.email;
        _firstNameCtrl.text = parts.isNotEmpty ? parts.first : '';
        _lastNameCtrl.text  = parts.length > 1 ? parts.sublist(1).join(' ') : '';
        _socialPhotoUrl     = account.photoUrl;
        _isSocialLogin      = true;
        _profilePhoto       = null; // use the provider URL instead
        _err                = {};
      });
    } catch (_) {
      _snack('Google sign-in failed. You can continue filling the form manually.', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _disconnectSocial() => setState(() {
        _isSocialLogin  = false;
        _socialPhotoUrl = null;
        _emailCtrl.clear();
        _firstNameCtrl.clear();
        _lastNameCtrl.clear();
        _profilePhoto   = null;
        _err            = {};
      });

  // Remove current photo (local takes priority; fall back to social URL)
  void _removePhoto() => setState(() {
        if (_profilePhoto != null) {
          _profilePhoto = null;   // reveal social URL preview if it still exists
        } else {
          _socialPhotoUrl = null; // clear social URL so no preview shows
        }
      });

  // ─────────────────────────────────────────────────────────────────────────────
  // Validation
  // ─────────────────────────────────────────────────────────────────────────────
  bool _validate() {
    final e = <String, String?>{};

    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      e['email'] = 'Email is required';
    } else if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
      e['email'] = 'Enter a valid email address';
    }

    if (_firstNameCtrl.text.trim().isEmpty) e['firstName'] = 'First name is required';
    if (_lastNameCtrl.text.trim().isEmpty)  e['lastName']  = 'Last name is required';
    if (_addressCtrl.text.trim().isEmpty)   e['address']   = 'Address is required';

    final digits = _phoneCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      e['phone'] = 'Mobile number is required';
    } else if (digits.length < 10) {
      e['phone'] = 'Enter a valid mobile number';
    }

    if (_requiresPassword) {
      if (_passCtrl.text.isEmpty) {
        e['password'] = 'Password is required';
      } else if (_passCtrl.text.length < 8) {
        e['password'] = 'Password must be at least 8 characters';
      }

      if (_confirmPassCtrl.text.isEmpty) {
        e['confirmPassword'] = 'Please confirm your password';
      } else if (_passCtrl.text != _confirmPassCtrl.text) {
        e['confirmPassword'] = 'Passwords do not match';
      }
    }

    setState(() => _err = e);
    return e.isEmpty;
  }

    Future<void> _submit() async {
    if (_isLoading || !_validate()) return;

    // With the On Go API the account is created there first; nothing is kept
    // on the device unless the server accepted it.
    final usesApi = MobileBackend.instance.usesApi;
    if (usesApi) {
      setState(() => _isLoading = true);
      try {
        await MobileBackend.instance.auth.register(RegisterRequest(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text,
          firstName: _firstNameCtrl.text.trim(),
          lastName: _lastNameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          role: UserRole.client,
        ));
      } on ApiException catch (error) {
        if (!mounted) return;
        final fieldErrors = _serverFieldErrors(error);
        setState(() {
          _isLoading = false;
          _err = fieldErrors;
        });
        if (fieldErrors.isEmpty) _snack(error.message, error: true);
        return;
      }
      if (!mounted) return;
      setState(() => _isLoading = false);
    }

    ClientAccountStore.instance.registerAccount(
      firstName: _firstNameCtrl.text.trim(),
      lastName: _lastNameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      // The server holds an API account's password; it is never kept here.
      password: usesApi || _isSocialLogin ? '' : _passCtrl.text,
      photoPath: _profilePhoto?.path ?? _socialPhotoUrl,
      photoIsNetwork: _profilePhoto == null && _socialPhotoUrl != null,
    );

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ClientHomeScreen()),
      (route) => false,
    );
  }

  /// The server's refusal, placed under the fields it names. A taken email
  /// (`conflict`) goes under Email. Address has no counterpart on the API.
  Map<String, String?> _serverFieldErrors(ApiException error) {
    const formFields = {'email', 'firstName', 'lastName', 'phone', 'password'};
    final errors = <String, String?>{
      for (final entry in error.fieldErrors.entries)
        if (formFields.contains(entry.key)) entry.key: entry.value,
    };
    if (error.code == ApiErrorCodes.conflict) errors['email'] = error.message;
    return errors;
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.error : AppColors.primary,
      duration: AppDurations.snackBar,
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // True when any photo is ready to preview
    final bool hasPhoto = _profilePhoto != null || _socialPhotoUrl != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Column(
            children: [
              // ── Header ───────────────────────────────────────────────────────
              Container(
                width: double.infinity,
                color: AppColors.primary,
                padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
                child: Column(
                  children: [
                    Text(
                      'Client Registration',
                      style: TextStyle(
                        color: AppColors.textlight,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Create your account to book services',
                      style: TextStyle(color: AppColors.textlight, fontSize: 12),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: context.layout.pageInsets,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ── Connected badge (only shown once Google succeeds) ──────
                      if (_isSocialLogin) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.textdark.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.g_mobiledata_rounded,
                                color: Color(0xFFEA4335),
                                size: 26,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Connected via Google',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: AppColors.success,
                                      ),
                                    ),
                                    Text(
                                      _emailCtrl.text,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.success),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: _disconnectSocial,
                                style: TextButton.styleFrom(
                                    foregroundColor: AppColors.success),
                                child: const Text('Change'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── Profile Picture ───────────────────────────────────────
                      Row(
                        children: [
                          Text(
                            'Profile Picture',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            ' *',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.error),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Upload a clear photo of yourself.',
                        style:
                            TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55)),
                      ),
                      const SizedBox(height: 10),

                      // ── Photo preview (appears above buttons once set) ─────────
                      if (hasPhoto) ...[
                        Center(
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // 140×140 rounded-square preview — matches mechanic Step 5
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: _profilePhoto != null
                                    ? Image.file(
                                        _profilePhoto!,
                                        width: context.layout.scale(140),
                                        height: context.layout.scale(140),
                                        fit: BoxFit.cover,
                                      )
                                    : Image.network(
                                        _socialPhotoUrl!,
                                        width: context.layout.scale(140),
                                        height: context.layout.scale(140),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Container(
                                          width: context.layout.scale(140),
                                          height: context.layout.scale(140),
                                          color: AppColors.background,
                                          child: Icon(
                                            Icons.person_outline,
                                            size: 52,
                                            color: AppColors.textdark.withValues(alpha: 0.55),
                                          ),
                                        ),
                                      ),
                              ),
                              // Red ✕ remove button
                              Positioned(
                                top: -10,
                                right: -10,
                                child: GestureDetector(
                                  onTap: _removePhoto,
                                  child: CircleAvatar(
                                    radius: 12,
                                    backgroundColor: AppColors.error,
                                    child: Icon(Icons.close,
                                        size: 14, color: AppColors.textmedium),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ── Upload / Selfie buttons ───────────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.upload_outlined, size: 18),
                              label: const Text('UPLOAD\nPHOTO',
                                  textAlign: TextAlign.center),
                              onPressed: _pickGallery,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: BorderSide(color: AppColors.primary),
                                minimumSize: const Size(0, 56),
                                shape: const StadiumBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.camera_alt_outlined,
                                  size: 18),
                              label: const Text('TAKE\nSELFIE',
                                  textAlign: TextAlign.center),
                              onPressed: _takeSelfie,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: BorderSide(color: AppColors.primary),
                                minimumSize: const Size(0, 56),
                                shape: const StadiumBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Form fields ───────────────────────────────────────────
                      OnGoTextField(
                        label: 'Email *',
                        hint: 'juandelacruz@gmail.com',
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        errorText: _err['email'],
                      ),
                      const SizedBox(height: 14),
                      OnGoTextField(
                        label: 'First Name *',
                        hint: 'Juan',
                        controller: _firstNameCtrl,
                        errorText: _err['firstName'],
                      ),
                      const SizedBox(height: 14),
                      OnGoTextField(
                        label: 'Last Name *',
                        hint: 'De la Cruz',
                        controller: _lastNameCtrl,
                        errorText: _err['lastName'],
                      ),
                      const SizedBox(height: 14),
                      OnGoTextField(
                        label: 'Address *',
                        hint: 'Puerto Princesa City',
                        controller: _addressCtrl,
                        errorText: _err['address'],
                      ),
                      const SizedBox(height: 14),
                      OnGoTextField(
                        label: 'Mobile Number *',
                        hint: '+63 XXX XXX XXXX',
                        keyboardType: TextInputType.phone,
                        controller: _phoneCtrl,
                        errorText: _err['phone'],
                      ),

                      // ── Password (manual only) ────────────────────────────────
                      if (_requiresPassword) ...[
                        const SizedBox(height: 14),
                        OnGoTextField(
                          label: 'Password *',
                          hint: '••••••••',
                          obscure: _obscurePass,
                          controller: _passCtrl,
                          errorText: _err['password'],
                          onChanged: (_) => setState(() {}),
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
                        PasswordStrengthMeter(password: _passCtrl.text),
                        const SizedBox(height: 14),
                                                OnGoTextField(
                          label: 'Confirm Password *',
                          hint: '••••••••',
                          obscure: _obscureConfirm,
                          controller: _confirmPassCtrl,
                          errorText: _err['confirmPassword'],
                          onChanged: (_) => setState(() {}),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirm
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                              color: AppColors.textdark.withValues(alpha: 0.55),
                            ),
                            onPressed: () =>
                                setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                        PasswordMatchIndicator(
                          password: _passCtrl.text,
                          confirmPassword: _confirmPassCtrl.text,
                        ),
                      ] else ...[
                        // ── Provider note ─────────────────────────────────────
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.textdark.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.lock_outline,
                                  size: 16, color: AppColors.textdark.withValues(alpha: 0.55)),
                              SizedBox(width: 8),
                              Text(
                                'Password is managed by Google',
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 28),

                      // ── Submit ────────────────────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.textlight,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: const StadiumBorder(),
                          ),
                          child: const Text(
                            'Sign Up',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── Loading overlay ───────────────────────────────────────────────────
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }
}