import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/client_account_store.dart';
import '../../../services/backend/mobile_backend.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/auth_widgets.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/password_strength.dart';
import '../client_ui/client_home_screen.dart';

/// Registration, in three short steps on one screen: the account, who they
/// are, a photo. Clients only — a mechanic's account is not opened from the
/// app.
///
/// One screen rather than three routes, so every field keeps its value while
/// the user walks back and forth, and a refusal from the server can put the
/// form back on the step that holds the field it names.
///
/// Google can fill in the name and email first. The On Go API has no Google
/// sign-in, so an API account always sets a password as well; the local
/// build lets Google stand in for one.
class ClientRegistrationScreen extends StatefulWidget {
  /// Starts the Google prefill as soon as the screen opens.
  final bool startWithGoogle;

  const ClientRegistrationScreen({super.key, this.startWithGoogle = false});

  @override
  State<ClientRegistrationScreen> createState() => _ClientRegistrationScreenState();
}

class _ClientRegistrationScreenState extends State<ClientRegistrationScreen> {
  static const int _stepCount = 3;

  final _emailCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  /// Which step is showing: 0 the account, 1 who they are, 2 the photo.
  int _step = 0;

  bool _obscurePass = true;
  bool _obscureConfirm = true;

  /// While the account is being created.
  bool _isLoading = false;

  /// While Google is being asked.
  bool _googleBusy = false;

  /// The profile photo: a file from the camera or the gallery, or the
  /// picture Google supplied. A file wins when both exist.
  File? _profilePhoto;
  String? _socialPhotoUrl;
  final _picker = ImagePicker();

  bool _isSocialLogin = false;

  Map<String, String?> _err = {};

  /// Whether the form asks for a password. A Google sign-up skips it locally,
  /// but an On Go API account always has one — the API has no Google sign-in,
  /// so Google only fills in the name and email.
  bool get _requiresPassword => !_isSocialLogin || MobileBackend.instance.usesApi;

  bool get _lastStep => _step == _stepCount - 1;

  @override
  void initState() {
    super.initState();
    if (widget.startWithGoogle) {
      // Post-frame so the busy overlay has something to render over.
      WidgetsBinding.instance.addPostFrameCallback((_) => _continueWithGoogle());
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------- steps ---

  /// Back through the steps first; off the screen only from the first one.
  void _back() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      Navigator.maybePop(context);
    }
  }

  /// On to the next step once this one is complete; from the last, the
  /// account is created.
  void _next() {
    if (!_validateStep(_step)) return;
    if (_lastStep) {
      _submit();
    } else {
      setState(() => _step++);
    }
  }

  /// The step that holds the first of [fields], so a refusal lands where it
  /// can be corrected.
  int _stepFor(Iterable<String> fields) {
    const account = {'email', 'password', 'confirmPassword'};
    const about = {'firstName', 'middleName', 'lastName', 'phone', 'address'};
    if (fields.any(account.contains)) return 0;
    if (fields.any(about.contains)) return 1;
    return _step;
  }

  // ----------------------------------------------------------------- photo ---

  /// One tap on the avatar: where the photo comes from, and a way to drop it.
  Future<void> _choosePhoto() async {
    final c = AppColors.palette;
    final hasPhoto = _profilePhoto != null || _socialPhotoUrl != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Profile photo', style: AppText.sectionTitle(ctx)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a selfie'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (hasPhoto)
              ListTile(
                leading: Icon(Icons.delete_outline, color: c.error),
                title: Text('Remove photo', style: TextStyle(color: c.error)),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'camera':
        await _takeSelfie();
      case 'gallery':
        await _pickGallery();
      case 'remove':
        setState(() {
          _profilePhoto = null;
          _socialPhotoUrl = null;
        });
    }
  }

  Future<void> _pickGallery() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null && mounted) setState(() => _profilePhoto = File(picked.path));
  }

  Future<void> _takeSelfie() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 85,
    );
    if (picked != null && mounted) setState(() => _profilePhoto = File(picked.path));
  }

  // ---------------------------------------------------------------- google ---

  Future<void> _continueWithGoogle() async {
    setState(() => _googleBusy = true);
    try {
      final account = await GoogleSignIn(scopes: ['email', 'profile']).signIn();
      if (account == null) return; // Cancelled: the form stays as it was.

      final parts = (account.displayName ?? '').trim().split(' ');
      setState(() {
        _emailCtrl.text = account.email;
        _firstNameCtrl.text = parts.isNotEmpty ? parts.first : '';
        _lastNameCtrl.text = parts.length > 1 ? parts.sublist(1).join(' ') : '';
        _socialPhotoUrl = account.photoUrl;
        _isSocialLogin = true;
        _profilePhoto = null; // Google's picture, until one is picked here.
        _err = {};
      });
    } catch (_) {
      _snack('Google sign-in failed. You can fill in the form instead.', error: true);
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  void _disconnectSocial() => setState(() {
        _isSocialLogin = false;
        _socialPhotoUrl = null;
        _emailCtrl.clear();
        _firstNameCtrl.clear();
        _middleNameCtrl.clear();
        _lastNameCtrl.clear();
        _profilePhoto = null;
        _err = {};
      });

  // ------------------------------------------------------------ validation ---

  /// Checks only what [step] asks for, so an untouched later step is never
  /// marked wrong before the user has reached it.
  bool _validateStep(int step) {
    final e = <String, String?>{};

    if (step == 0) {
      final email = _emailCtrl.text.trim();
      if (email.isEmpty) {
        e['email'] = 'Email is required';
      } else if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
        e['email'] = 'Enter a valid email address';
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
    } else if (step == 1) {
      if (_firstNameCtrl.text.trim().isEmpty) e['firstName'] = 'First name is required';
      if (_lastNameCtrl.text.trim().isEmpty) e['lastName'] = 'Last name is required';
      if (_addressCtrl.text.trim().isEmpty) e['address'] = 'Address is required';

      final digits = _phoneCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isEmpty) {
        e['phone'] = 'Mobile number is required';
      } else if (digits.length < 10) {
        e['phone'] = 'Enter a valid mobile number';
      }
    }

    setState(() => _err = e);
    return e.isEmpty;
  }

  Future<void> _submit() async {
    if (_isLoading) return;

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
          // Back to the step that holds the field the server refused.
          _step = _stepFor(fieldErrors.keys);
        });
        if (fieldErrors.isEmpty) _snack(error.message, error: true);
        return;
      }
      if (!mounted) return;
      setState(() => _isLoading = false);
    }

    ClientAccountStore.instance.registerAccount(
      firstName: _firstNameCtrl.text.trim(),
      middleName: _middleNameCtrl.text.trim(),
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
      backgroundColor: error ? AppColors.error : null,
      duration: AppDurations.snackBar,
    ));
  }

  // ----------------------------------------------------------------- build ---

  String get _title => switch (_step) {
        0 => 'Your account',
        1 => 'About you',
        _ => 'Add a photo',
      };

  String get _subtitle => switch (_step) {
        0 => !_isSocialLogin
            ? "The email and password you'll sign in with."
            : _requiresPassword
                ? 'Google filled in your email. Set a password to sign in with.'
                : 'Google will sign you in from now on.',
        1 => 'So a mechanic knows who they are helping, and how to reach you.',
        _ => 'Optional, but it helps a mechanic recognise you on the road.',
      };

  /// The step's one red button: on to the next step, or the account itself.
  Widget get _cta => AuthPrimaryButton(
        label: _lastStep ? (_isLoading ? 'Creating account…' : 'Create account') : 'Continue',
        busy: _isLoading,
        onPressed: _next,
      );

  Widget _eye(bool obscured, VoidCallback toggle) => IconButton(
        tooltip: obscured ? 'Show password' : 'Hide password',
        icon: Icon(obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
        onPressed: toggle,
      );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;

    return PopScope(
      // The system back walks the steps too.
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Stack(
        children: [
          AuthPage(
            showBack: true,
            onBack: _back,
            compactHero: true,
            // A way back to Sign In, offered before anything has been typed.
            footer: _step == 0
                ? AuthFooterLink(
                    prompt: 'Already have an account? ',
                    action: 'Sign In',
                    onTap: () => Navigator.maybePop(context),
                  )
                : null,
            children: [
              StepProgressBar(step: _step, count: _stepCount),
              const SizedBox(height: 12),
              Text(
                'STEP ${_step + 1} OF $_stepCount',
                style: AppText.overline(context).copyWith(color: c.textmedium),
              ),
              const SizedBox(height: 8),
              AuthIntro(title: _title, subtitle: _subtitle),
              const SizedBox(height: 28),
              // The step's fields and its button slide in from the right; the
              // previous ones slide out the way they came.
              AnimatedSwitcher(
                duration: AppMotion.normal,
                switchInCurve: AppMotion.enter,
                switchOutCurve: AppMotion.enter,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(animation),
                    child: child,
                  ),
                ),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topCenter,
                  children: [...previous, ?current],
                ),
                child: KeyedSubtree(key: ValueKey(_step), child: _stepBody()),
              ),
            ],
          ),

          // Google's own sheet is in front while it is being asked; this
          // keeps the form from being tapped underneath it.
          if (_googleBusy)
            Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(
                  color: c.surface.withValues(alpha: 0.6),
                  child: Center(child: CircularProgressIndicator(color: c.primary)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // What Google filled in, and a way to undo it.
              if (_isSocialLogin) ...[
                _GoogleConnected(email: _emailCtrl.text, onChange: _disconnectSocial),
                const SizedBox(height: 20),
              ],
              AuthTextField(
                label: 'Email',
                hint: 'Enter your email',
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                // The only field on this step when Google holds the password.
                textInputAction: _requiresPassword ? TextInputAction.next : TextInputAction.done,
                onSubmitted: _requiresPassword ? null : (_) => _next(),
                errorText: _err['email'],
              ),
              if (_requiresPassword) ...[
                const SizedBox(height: 16),
                AuthTextField(
                  label: 'Password',
                  hint: 'Enter a password',
                  controller: _passCtrl,
                  obscure: _obscurePass,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  onChanged: (_) => setState(() {}),
                  suffixIcon: _eye(_obscurePass, () => setState(() => _obscurePass = !_obscurePass)),
                  errorText: _err['password'],
                ),
                PasswordStrengthMeter(password: _passCtrl.text),
                const SizedBox(height: 16),
                AuthTextField(
                  label: 'Confirm password',
                  hint: 'Re-enter your password',
                  controller: _confirmPassCtrl,
                  obscure: _obscureConfirm,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onSubmitted: (_) => _next(),
                  onChanged: (_) => setState(() {}),
                  suffixIcon: _eye(_obscureConfirm, () => setState(() => _obscureConfirm = !_obscureConfirm)),
                  errorText: _err['confirmPassword'],
                ),
                PasswordMatchIndicator(
                  password: _passCtrl.text,
                  confirmPassword: _confirmPassCtrl.text,
                ),
              ] else ...[
                const SizedBox(height: 16),
                const _Note(Icons.lock_outline, 'Your password is managed by Google.'),
              ],
              const SizedBox(height: 28),
              _cta,
              // Google as the other way in: it fills in the name and the email.
              if (!_isSocialLogin) ...[
                const SizedBox(height: 22),
                const _OrDivider('Or with'),
                const SizedBox(height: 22),
                AuthSecondaryButton(
                  label: 'Continue with Google',
                  leading: const _GoogleMark(size: 20),
                  onPressed: _googleBusy ? null : _continueWithGoogle,
                ),
              ],
            ],
          ),
        );

      case 1:
        return AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // One name to a row, in the order a form here expects them.
              AuthTextField(
                label: 'First name',
                hint: 'Enter your first name',
                controller: _firstNameCtrl,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.givenName],
                errorText: _err['firstName'],
              ),
              const SizedBox(height: 16),
              // Not everyone has one, so it is the one name not insisted on.
              AuthTextField(
                label: 'Middle name',
                hint: 'Enter your middle name',
                controller: _middleNameCtrl,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.middleName],
              ),
              const SizedBox(height: 16),
              AuthTextField(
                label: 'Last name',
                hint: 'Enter your last name',
                controller: _lastNameCtrl,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.familyName],
                errorText: _err['lastName'],
              ),
              const SizedBox(height: 16),
              AuthTextField(
                label: 'Mobile number',
                hint: 'Enter your mobile number',
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.telephoneNumber],
                errorText: _err['phone'],
              ),
              const SizedBox(height: 16),
              AuthTextField(
                label: 'Address',
                hint: 'Enter your address',
                controller: _addressCtrl,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.fullStreetAddress],
                onSubmitted: (_) => _next(),
                errorText: _err['address'],
              ),
              const SizedBox(height: 28),
              _cta,
            ],
          ),
        );

      default:
        final c = AppColors.palette;
        final ImageProvider? photo = _profilePhoto != null
            ? FileImage(_profilePhoto!)
            : _socialPhotoUrl != null
                ? NetworkImage(_socialPhotoUrl!)
                : null;
        return Column(
          children: [
            const SizedBox(height: 8),
            _AvatarPicker(image: photo, onTap: _choosePhoto),
            const SizedBox(height: 14),
            Text(
              photo == null ? 'Add a profile photo' : 'Change photo',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.primary),
            ),
            const SizedBox(height: 28),
            _cta,
          ],
        );
    }
  }
}

/// The avatar, and the one control for changing it: a circle showing the
/// photo, or a placeholder until there is one, with a small camera badge.
class _AvatarPicker extends StatelessWidget {
  final ImageProvider? image;
  final VoidCallback onTap;

  const _AvatarPicker({required this.image, required this.onTap});

  static const double size = 120;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    return Semantics(
      button: true,
      label: image == null ? 'Add a profile photo' : 'Change profile photo',
      child: PressScale(
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: size + 4,
            height: size + 4,
            child: Stack(
              children: [
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.background,
                    border: Border.all(color: AppHairline.outline(c.textmedium)),
                    image: image == null ? null : DecorationImage(image: image!, fit: BoxFit.cover),
                  ),
                  child: image == null
                      ? Icon(Icons.person_rounded, size: 56, color: c.textmedium.withValues(alpha: 0.7))
                      : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.primary,
                      border: Border.all(color: c.surface, width: 3),
                    ),
                    child: Icon(Icons.photo_camera_rounded, size: 18, color: c.textlight),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What Google supplied, and a way to undo it.
class _GoogleConnected extends StatelessWidget {
  final String email;
  final VoidCallback onChange;

  const _GoogleConnected({required this.email, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadii.borderLg,
        border: Border.all(color: AppHairline.outline(c.textmedium)),
      ),
      child: Row(
        children: [
          const _GoogleMark(size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Signed in with Google',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textdark),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: c.textmedium),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onChange,
            style: TextButton.styleFrom(foregroundColor: c.primary),
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}

/// A hairline with a word in the middle. Kept to a word: the row cannot
/// give way, so the text must never be wider than a small phone.
class _OrDivider extends StatelessWidget {
  final String text;

  const _OrDivider(this.text);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(text, style: TextStyle(fontSize: 12, color: c.textmedium)),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

/// A quiet line of explanation in a soft well.
class _Note extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Note(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: c.background, borderRadius: AppRadii.borderMd),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.textmedium),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: c.textmedium))),
        ],
      ),
    );
  }
}

/// Google's "G", drawn rather than shipped as a picture: four arcs of a ring
/// and the bar, in Google's own colours.
class _GoogleMark extends StatelessWidget {
  final double size;

  const _GoogleMark({this.size = 20});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: const _GoogleMarkPainter());
  }
}

class _GoogleMarkPainter extends CustomPainter {
  const _GoogleMarkPainter();

  static const Color _blue = Color(0xFF4285F4);
  static const Color _green = Color(0xFF34A853);
  static const Color _yellow = Color(0xFFFBBC05);
  static const Color _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final stroke = r * 0.46;
    final ring = Rect.fromCircle(center: Offset(r, r), radius: r - stroke / 2);
    double rad(double degrees) => degrees * math.pi / 180;
    Paint arc(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    // Angles run clockwise from three o'clock; the ring opens at the top
    // right, where the bar comes in.
    canvas.drawArc(ring, rad(225), rad(90), false, arc(_red)); // top
    canvas.drawArc(ring, rad(135), rad(90), false, arc(_yellow)); // left
    canvas.drawArc(ring, rad(45), rad(90), false, arc(_green)); // bottom
    canvas.drawArc(ring, rad(0), rad(45), false, arc(_blue)); // lower right
    canvas.drawRect(Rect.fromLTWH(r, r - stroke / 2, r, stroke), Paint()..color = _blue);
  }

  @override
  bool shouldRepaint(_GoogleMarkPainter oldDelegate) => false;
}
