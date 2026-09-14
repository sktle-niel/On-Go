import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:livelyness_detection/livelyness_detection.dart';
import '../../../data/mechanic_account_store.dart';
import '../../../data/mechanic_credential_store.dart';
import '../../../services/backend/mobile_backend.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/auth_widgets.dart';
import '../../../data/registration_draft.dart';
import '../../../utils/step_navigator.dart';
import '../mechanic_ui/mechanic_home_screen.dart';

// pubspec.yaml — add these dependencies:
//   image_picker: ^1.1.2
//   livelyness_detection: ^0.0.1+5
//
// Android: set minSdkVersion to 21 in android/app/build.gradle
//
// iOS — ios/Runner/Info.plist (inside <dict>):
//   <key>NSCameraUsageDescription</key>
//   <string>Camera access is required for face verification.</string>
//   <key>NSMicrophoneUsageDescription</key>
//   <string>Microphone access is needed during face verification.</string>
// iOS — ios/Podfile: uncomment/set  platform :ios, '14.0'

class MechanicStep5Verification extends StatefulWidget {
  const MechanicStep5Verification({super.key});

  @override
  State<MechanicStep5Verification> createState() =>
      _MechanicStep5VerificationState();
}

class _MechanicStep5VerificationState
    extends State<MechanicStep5Verification> {
  final _draft  = RegistrationDraft.instance;
  final ImagePicker _picker = ImagePicker();

  /// Which registration step this screen is, for [RegistrationDraft
  /// .markPickerLaunched].
  static const int _stepNumber = 5;

  File? _profilePhoto;
  File? _faceScanPhoto;       // captured frame returned by liveness SDK
  bool _isScanning    = false;
  bool _livenessPass  = false; // true once the SDK reports success

  bool _profilePhotoError = false;
  bool _faceScanError     = false;

  @override
  void initState() {
    super.initState();
    _restoreFromDraft();
    _recoverInterruptedPick();
  }

  /// Picks up a photo that Android took but never got to hand back.
  ///
  /// If the activity was destroyed while the camera or gallery was open, the
  /// result is delivered to a process that no longer exists; the plugin holds
  /// it until it is asked for. Without this the user would come back to an
  /// empty photo slot and have to shoot it again.
  Future<void> _recoverInterruptedPick() async {
    // Consume the flag first. This launch has already done its job of getting
    // the user back here, and a plugin call that never answers must not leave
    // every future launch reopening registration.
    await _draft.clearPendingPicker();
    try {
      final lost = await _picker.retrieveLostData();
      final file = lost.file;
      if (file != null && mounted) {
        setState(() {
          _profilePhoto = File(file.path);
          _profilePhotoError = false;
        });
        _autosave();
      }
    } catch (_) {
      // retrieveLostData is Android-only; anywhere else this is a no-op.
    }
  }

  void _restoreFromDraft() {
    _profilePhoto  = _draft.resolveFile(_draft.profilePhotoPath);
    final restored = _draft.resolveFile(_draft.faceScanPath);
    if (restored != null) {
      _faceScanPhoto = restored;
      _livenessPass  = true; // was already verified in a previous session
    }
  }

  void _autosave() {
    _draft.profilePhotoPath = _profilePhoto?.path ?? '';
    _draft.faceScanPath     = _faceScanPhoto?.path ?? '';
    _draft.saveStep5();
  }

  // ── Profile photo ────────────────────────────────────────────────────────

  // Both pickers hand the screen over to another Android activity, which is
  // the moment this app can be killed. Recording the step first is what lets
  // the next launch come back here instead of to Sign In.

  Future<void> _pickFromGallery() async {
    await _draft.markPickerLaunched(_stepNumber);
    try {
      final picked = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 85);
      if (picked != null) {
        setState(() {
          _profilePhoto = File(picked.path);
          _profilePhotoError = false;
        });
        _autosave();
      }
    } finally {
      await _draft.clearPendingPicker();
    }
  }

  Future<void> _takeSelfie() async {
    await _draft.markPickerLaunched(_stepNumber);
    try {
      final picked = await _picker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.front,
          imageQuality: 85);
      if (picked != null) {
        setState(() {
          _profilePhoto = File(picked.path);
          _profilePhotoError = false;
        });
        _autosave();
      }
    } finally {
      await _draft.clearPendingPicker();
    }
  }

  // ── Liveness detection ───────────────────────────────────────────────────

  Future<void> _startLivenessDetection() async {
    setState(() {
      _isScanning    = true;
      _faceScanError = false;
    });

    try {
      // detectLivelyness opens a full-screen camera UI that guides the user
      // through blink + smile challenges, then returns the captured image path
      // on success or null on failure/cancellation.
      final CapturedImage? result =
          await LivelynessDetection.instance.detectLivelyness(
        context,
        config: DetectionConfig(
          startWithInfoScreen: true,
          steps: [
            LivelynessStepItem(
              step: LivelynessStep.blink,
              title: 'Blink',
              isCompleted: false,
            ),
            LivelynessStepItem(
              step: LivelynessStep.smile,
              title: 'Smile',
              isCompleted: false,
            ),
          ],
        ),
      );

      final String? capturedPath = result?.imgPath;

      if (capturedPath != null && capturedPath.isNotEmpty) {
        setState(() {
          _faceScanPhoto = File(capturedPath);
          _livenessPass  = true;
          _faceScanError = false;
        });
        _autosave();
        // todo: optionally send capturedPath + validIdPath to your backend
        // to queue a human moderator review for ID-face matching.
      } else {
        // User cancelled or challenge failed
        setState(() => _livenessPass = false);
      }
    } catch (e) {
      setState(() => _livenessPass = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Face verification error: $e'), duration: AppDurations.snackBar),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _retakeLiveness() async {
    setState(() {
      _faceScanPhoto = null;
      _livenessPass  = false;
    });
    _autosave();
    await _startLivenessDetection();
  }

  // ── Validation ───────────────────────────────────────────────────────────

  bool _validate() {
    final profileMissing  = _profilePhoto == null;
    final faceScanMissing = !_livenessPass;
    setState(() {
      _profilePhotoError = profileMissing;
      _faceScanError     = faceScanMissing;
    });
    return !profileMissing && !faceScanMissing;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: context.layout.pageInsets,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RegistrationStepper(
                    currentStep: 5,
                    highestCompletedStep: _draft.highestCompletedStep,
                    onStepTapped: (step) => goToRegistrationStep(context, step),
                  ),
                  const SizedBox(height: 20),

                  Text(
                    'Verification',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textdark,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Profile Picture ─────────────────────────────────────
                  Row(
                    children: [
                      Text('Profile Picture',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                      Text('*',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.error)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Upload a clear photo of yourself. You can update it every 3 months for security purposes.',
                    style:
                        TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55)),
                  ),
                  const SizedBox(height: 10),

                  // Preview
                  if (_profilePhoto != null) ...[
                    Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(_profilePhoto!,
                                width: context.layout.scale(140), height: context.layout.scale(140), fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: -10,
                            right: -10,
                            child: GestureDetector(
                              onTap: () {
                                setState(() => _profilePhoto = null);
                                _autosave();
                              },
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
                    const SizedBox(height: 10),
                  ],

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.upload_outlined, size: 18),
                          label: const Text('UPLOAD\nPHOTO',
                              textAlign: TextAlign.center),
                          onPressed: _pickFromGallery,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.info,
                            side: BorderSide(
                                color: _profilePhotoError
                                    ? AppColors.error
                                    : AppColors.info),
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
                            foregroundColor: AppColors.info,
                            side: BorderSide(
                                color: _profilePhotoError
                                    ? AppColors.error
                                    : AppColors.info),
                            minimumSize: const Size(0, 56),
                            shape: const StadiumBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_profilePhotoError)
                    Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('A profile picture is required',
                          style:
                              TextStyle(fontSize: 11, color: AppColors.error)),
                    ),

                  const SizedBox(height: 24),

                  // ── Face Verification ───────────────────────────────────
                  Row(
                    children: [
                      Text('Face Verification',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                      Text('*',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.error)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'We need to confirm you are a real person. You will be asked to blink and smile.',
                    style:
                        TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55)),
                  ),
                  const SizedBox(height: 20),

                  // Status card
                  Center(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 24, horizontal: 20),
                      decoration: BoxDecoration(
                        color: _livenessPass
                            ? AppColors.success.withValues(alpha: 0.08)
                            : _faceScanError
                                ? AppColors.error.withValues(alpha: 0.08)
                                : AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _livenessPass
                              ? AppColors.success
                              : _faceScanError
                                  ? AppColors.error
                                  : AppColors.textdark.withValues(alpha: 0.55),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _livenessPass
                                ? Icons.verified_user_outlined
                                : _faceScanError
                                    ? Icons.error_outline
                                    : Icons.face_outlined,
                            size: 52,
                            color: _livenessPass
                                ? AppColors.success
                                : _faceScanError
                                    ? AppColors.error
                                    : AppColors.textdark.withValues(alpha: 0.55),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _livenessPass
                                ? 'Face Verification Passed'
                                : _faceScanError
                                    ? 'Verification required to continue'
                                    : 'Not yet verified',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _livenessPass
                                  ? AppColors.success
                                  : _faceScanError
                                      ? AppColors.error
                                      : AppColors.textdark.withValues(alpha: 0.55),
                            ),
                          ),
                          if (_livenessPass) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Liveness confirmed — blink & smile challenges passed.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.success),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Start / Retake button
                  ElevatedButton.icon(
                    icon: Icon(
                      _livenessPass
                          ? Icons.refresh
                          : Icons.face_retouching_natural,
                      size: 18,
                    ),
                    label: Text(
                      _isScanning
                          ? 'VERIFYING...'
                          : _livenessPass
                              ? 'REDO VERIFICATION'
                              : 'START FACE VERIFICATION',
                    ),
                    onPressed: _isScanning
                        ? null
                        : _livenessPass
                            ? _retakeLiveness
                            : _startLivenessDetection,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      backgroundColor: _livenessPass
                          ? AppColors.success
                          : AppColors.primary,
                      shape: const StadiumBorder(),
                    ),
                  ),
                  const SizedBox(height: 32),

                  StepNavButtons(
                    onBack: () => Navigator.pop(context),
                    onNext: () async {
                      if (_submitting || !_validate()) return;
                      _submitting = true;

                      // With the On Go API the account is created there
                      // first; nothing below runs unless it was accepted.
                      final usesApi = MobileBackend.instance.usesApi;
                      if (usesApi && !await _registerWithApi()) {
                        _submitting = false;
                        return;
                      }

                      // Files the account's verification request with the
                      // moderation queue — see MobileBackend. Awaited so the
                      // uploads below are attached to an account that is
                      // really in the queue.
                      await MechanicAccountStore.instance.registerAccount(
                        firstName: _draft.firstName,
                        lastName: _draft.lastName,
                        email: _draft.email,
                        phone: _draft.mobile,
                        address: _draft.address,
                        // The server holds an API account's password.
                        password: usesApi ? '' : _draft.password,
                        photoPath: _profilePhoto?.path,
                        documents: [
                          if (_draft.validIdPath.isNotEmpty) _draft.validIdPath.split('/').last,
                          if (_draft.ncIiPath.isNotEmpty) _draft.ncIiPath.split('/').last,
                          ..._draft.certPaths.map((p) => p.split('/').last),
                        ],
                      );

                      // Copy the uploads into app storage and attach them to
                      // this mechanic BEFORE the draft is wiped — the draft
                      // holds the only reference to the picked file paths.
                      await MechanicCredentialStore.instance.saveForMechanic(
                        mechanicName: MechanicAccountStore.instance.name,
                        mechanicIdPath: _draft.validIdPath,
                        documents: [
                          if (_draft.ncIiPath.isNotEmpty) (label: 'NC II', path: _draft.ncIiPath),
                        ],
                        certificationPaths: _draft.certPaths,
                      );

                      _draft.clear(); // wipe saved draft on successful completion
                      if (!context.mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                            builder: (_) => const MechanicHomeScreen()),
                        (route) => false,
                      );
                    },
                    nextLabel: 'SUBMIT',
                    isLastStep: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Set while SUBMIT is running, so a second tap cannot register twice.
  bool _submitting = false;

  /// Creates the account on the On Go API. False — with the server's reason on
  /// screen — when it was refused or could not be reached; the draft is left
  /// as it is so the user can go back and fix it.
  Future<bool> _registerWithApi() async {
    try {
      await MobileBackend.instance.auth.register(RegisterRequest(
        email: _draft.email.trim(),
        password: _draft.password,
        firstName: _draft.firstName.trim(),
        lastName: _draft.lastName.trim(),
        phone: _draft.mobile.trim(),
        role: UserRole.mechanic,
      ));
      return true;
    } on ApiException catch (error) {
      if (!mounted) return false;
      final detail = error.details.isEmpty ? null : error.details.first;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(detail == null
            ? error.message
            : '${error.message} (${_fieldLabel(detail.field)}: ${detail.message})'),
        backgroundColor: AppColors.error,
        duration: AppDurations.snackBar,
      ));
      return false;
    }
  }

  static String _fieldLabel(String field) => switch (field) {
        'email' => 'Email',
        'password' => 'Password',
        'firstName' => 'First name',
        'lastName' => 'Last name',
        'phone' => 'Mobile number',
        _ => field,
      };

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
      child: Column(
        children: [
          Text('On Go Registration',
              style: TextStyle(
                  color: AppColors.textlight,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          SizedBox(height: 4),
          Text('Complete all steps to provide services',
              style: TextStyle(color: AppColors.textlight, fontSize: 12)),
        ],
      ),
    );
  }
}