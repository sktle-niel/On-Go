import 'dart:io';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Red header banner (logo + subtitle)
class OnGoHeader extends StatelessWidget {
  final String subtitle;
  const OnGoHeader({super.key, this.subtitle = 'Service Anywhere'});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
      child: Column(
        children: [
          Text(
            'On Go',
            style: TextStyle(
              color: AppColors.textmedium,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: AppColors.textmedium, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Labelled text field with optional validation support.
class OnGoTextField extends StatelessWidget {
  final String label;
  final String hint;
  final bool obscure;
  final TextEditingController? controller;
  final TextInputType keyboardType;
  final Widget? suffixIcon;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  const OnGoTextField({
    super.key,
    required this.label,
    this.hint = '',
    this.obscure = false,
    this.controller,
    this.keyboardType = TextInputType.text,
    this.suffixIcon,
    this.errorText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textdark,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: suffixIcon,
            errorText: errorText,
          ),
        ),
      ],
    );
  }
}

/// Step progress indicator used in multi-step registration.
///
/// [currentStep]         — the step currently being filled (1-based).
/// [highestCompletedStep]— the highest step the user has validated and passed.
///                         Circles ≤ this value are tappable.
/// [onStepTapped]        — called with the tapped step number when a completed
///                         step circle is tapped. The screen is responsible for
///                         pushing the correct route.
class RegistrationStepper extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final List<String> labels;
  final int highestCompletedStep;
  final ValueChanged<int>? onStepTapped;

  const RegistrationStepper({
    super.key,
    required this.currentStep,
    this.totalSteps = 5,
    this.labels = const [
      'Account',
      'Personal',
      'ID Details',
      'Documents',
      'Verification',
    ],
    this.highestCompletedStep = 0,
    this.onStepTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          // Circles and connector lines
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(totalSteps * 2 - 1, (i) {
              if (i.isOdd) {
                final stepBefore = (i ~/ 2) + 1;
                final stepAfter = stepBefore + 1;
                // Green if both the step before AND after are completed
                final active =
                    stepBefore <= highestCompletedStep &&
                    stepAfter <= highestCompletedStep;
                return Expanded(
                  child: Container(
                    height: 3,
                    color: active
                        ? AppColors.success
                        : AppColors.textdark.withValues(alpha: 0.2),
                  ),
                );
              }

              final step = i ~/ 2 + 1;
              final done = step < currentStep;
              final current = step == currentStep;
              // A step is tappable if it has been completed (done) but is not
              // Any completed step is tappable, including steps ahead of current.
              // Current step itself is excluded (already there).
              final tappable =
                  step <= highestCompletedStep && step != currentStep;

              final circle = Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (done || current || step <= highestCompletedStep)
                      ? AppColors.success
                      : AppColors.textdark.withValues(alpha: 0.12),
                ),
                child: Center(
                  child: done || (step <= highestCompletedStep && !current)
                      ? Icon(Icons.check, color: AppColors.textlight, size: 14)
                      : Text(
                          '$step',
                          style: TextStyle(
                            color: current
                                ? AppColors.textlight
                                : AppColors.textdark.withValues(alpha: 0.55),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              );

              if (tappable && onStepTapped != null) {
                return GestureDetector(
                  onTap: () => onStepTapped!(step),
                  child: circle,
                );
              }
              return circle;
            }),
          ),

          const SizedBox(height: 4),

          // Labels row
          Row(
            children: List.generate(totalSteps * 2 - 1, (i) {
              if (i.isOdd) return Expanded(child: Container());
              final step = i ~/ 2 + 1;
              final done = step < currentStep;
              final current = step == currentStep;
              return SizedBox(
                width: 45,
                child: Text(
                  labels[step - 1],
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: 9,
                    color: (done || current)
                        ? AppColors.success
                        : AppColors.textdark.withValues(alpha: 0.55),
                    fontWeight: current ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// Back / Next button row for multi-step forms.
class StepNavButtons extends StatelessWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final String nextLabel;
  final bool isLastStep;

  const StepNavButtons({
    super.key,
    this.onBack,
    this.onNext,
    this.nextLabel = 'NEXT',
    this.isLastStep = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(onPressed: onNext, child: Text(nextLabel)),
        ),
      ],
    );
  }
}

/// Layout used by the Sign In / Welcome screens.
class AuthBottomCard extends StatelessWidget {
  final List<Widget> children;
  final Widget? topContent;

  const AuthBottomCard({super.key, required this.children, this.topContent});

  @override
  Widget build(BuildContext context) {
    // Scrolls when it has to, and only then.
    //
    // With the keyboard up, the Scaffold hands this far less height than the
    // card needs — over half the screen with some keyboards — and a Column
    // that cannot scroll can only overflow, painting the warning stripe over
    // "Don't have account? Sign Up". Inside a scroll view the card has
    // somewhere to go: the field being typed into is brought above the
    // keyboard, and the rest of the card is a swipe away.
    //
    // When everything fits, nothing changes. The minimum height is the full
    // height available, so the space above the card still expands and the
    // card still sits on the bottom edge exactly as before, and clamping
    // physics stop it bouncing when there is nothing to scroll.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          // What lets the Expanded below work inside a scroll view: it gives
          // the column a definite height — the taller of the screen and the
          // card — for the space above the card to fill.
          child: IntrinsicHeight(
            child: Column(
              children: [
                Expanded(child: Center(child: topContent ?? const SizedBox.shrink())),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    border: Border.all(color: AppColors.primary, width: 4),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    context.layout.isTablet ? 32 : 24,
                    36,
                    context.layout.isTablet ? 32 : 24,
                    32,
                  ),
                  // The card itself still runs edge to edge — that full-bleed
                  // panel anchored to the bottom is the design. What stops at
                  // a sensible width is what is INSIDE it: on a tablet, a
                  // sign-in field and a "Register as Client" button stretched
                  // across ten inches look broken, and the buttons become a
                  // long way from the thumb that has to reach them. Centred
                  // inside the card, they keep a phone's proportions on any
                  // screen.
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: context.layout.contentMaxWidth),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: children,
                      ),
                    ),
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

/// White, borderless input field for use on the red card.
class AuthTextField extends StatelessWidget {
  final String hint;
  final bool obscure;
  final TextEditingController? controller;
  final TextInputType keyboardType;
  final Widget? suffixIcon;

  /// Optional per-keystroke callback, for fields whose surroundings react as
  /// the user types (the password match indicator, for one).
  final ValueChanged<String>? onChanged;

  const AuthTextField({
    super.key,
    required this.hint,
    this.obscure = false,
    this.controller,
    this.keyboardType = TextInputType.text,
    this.suffixIcon,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: AppColors.textmedium.withValues(alpha: 0.2), width: 1.5),
    );

    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: TextStyle(color: AppColors.textdark),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textdark.withValues(alpha: 0.55)),
        filled: true,
        fillColor: AppColors.surface,
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border,
      ),
    );
  }
}

/// Solid primary button with light text.
class AuthWhiteButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const AuthWhiteButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textlight,
        minimumSize: const Size(double.infinity, 50),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}

/// Primary pill button with a light icon and label.
class AuthRoleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const AuthRoleButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.textlight, width: 1.5),
                ),
                child: Icon(icon, color: AppColors.textlight, size: 20),
              ),
              const SizedBox(width: 16),
              // Expanded, not bare: the label takes what is left of the row
              // after the circle rather than demanding its own full width.
              // Without it "Register as Mechanic" runs past the right edge of
              // the card on any phone narrower than about 430 points.
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textlight,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The backdrop the Sign In and Welcome screens sit on.
///
/// Paints the photo an admin published from the console website (Settings >
/// Change Background), or [AppColors.surface] — the default background color
/// — when there is none. It listens to [AuthBackgroundController], so a
/// published or cleared photo swaps both screens over on its own.
class AuthBackground extends StatelessWidget {
  final Widget child;

  const AuthBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthBackgroundController.instance,
      child: child,
      builder: (context, child) {
        final photo = AuthBackgroundController.instance.photoPath;
        return Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface,
            image: photo == null
                ? null
                : DecorationImage(image: FileImage(File(photo)), fit: BoxFit.cover),
          ),
          child: child,
        );
      },
    );
  }
}
