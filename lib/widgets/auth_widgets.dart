import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

// The registration screens reach the photo badge through this file, as before.
export 'common_widgets.dart' show PhotoRemoveButton;

/// What a date field on the registration forms accepts as it is typed:
/// digits and slashes, at most "mm/dd/yyyy".
final List<TextInputFormatter> dateInputFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
  LengthLimitingTextInputFormatter(10),
];

/// A Philippine mobile number as the forms ask for it: 09 and nine digits.
final List<TextInputFormatter> phMobileInputFormatters = [
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(11),
];

/// Red header banner (logo + subtitle)
class OnGoHeader extends StatelessWidget {
  final String subtitle;
  const OnGoHeader({super.key, this.subtitle = 'Service Anywhere'});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.primary,
      // The status bar's real height rather than a fixed 48, which was too
      // little under a notch and too much on a phone without one.
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 16, 20, 20),
      child: Column(
        children: [
          Text(
            'On Go',
            style: TextStyle(
              color: AppColors.textmedium,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              // Large type reads best slightly tightened, not spread out.
              letterSpacing: -0.4,
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

/// A field heading, with a red asterisk when the field is required. The one
/// way the app's forms mark a required field, so every form reads the same.
class OnGoFieldLabel extends StatelessWidget {
  final String text;
  final bool isRequired;

  const OnGoFieldLabel(this.text, {super.key, this.isRequired = false});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textdark,
        ),
        children: [
          if (isRequired) TextSpan(text: ' *', style: TextStyle(color: AppColors.error)),
        ],
      ),
    );
  }
}

/// Labelled text field with optional validation support.
///
/// The keyboard moves a form along: [textInputAction] defaults to "next",
/// which takes focus to the following field, and the last field of a form
/// passes [TextInputAction.done] with [onSubmitted] so the keyboard's key
/// submits it.
class OnGoTextField extends StatelessWidget {
  final String label;
  final String hint;
  final bool obscure;
  final bool isRequired;
  final TextEditingController? controller;
  final TextInputType keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? suffixIcon;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const OnGoTextField({
    super.key,
    required this.label,
    this.hint = '',
    this.obscure = false,
    this.isRequired = false,
    this.controller,
    this.keyboardType = TextInputType.text,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.inputFormatters,
    this.suffixIcon,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OnGoFieldLabel(label, isRequired: isRequired),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          enableSuggestions: !obscure,
          autocorrect: !obscure,
          keyboardType: keyboardType,
          textInputAction: textInputAction ?? TextInputAction.next,
          textCapitalization: textCapitalization,
          autofillHints: autofillHints,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
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

  /// The line between [before] and the step after it is green once both are
  /// completed.
  bool _connectorDone(int before) =>
      before <= highestCompletedStep && before + 1 <= highestCompletedStep;

  Color _lineColor(bool done) =>
      done ? AppColors.success : AppColors.textdark.withValues(alpha: 0.2);

  @override
  Widget build(BuildContext context) {
    // One column per step, all the same width. A label sits in the same column
    // as its circle, so it is always centred under it; before, the labels were
    // left-aligned in a separate row and drifted away from their circles. The
    // connector between two steps is drawn as the halves on either side of
    // each circle.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(totalSteps, (index) {
          final step = index + 1;
          final done = step < currentStep;
          final current = step == currentStep;
          // Any completed step is tappable, including steps ahead of the
          // current one; the current step itself is not (already there).
          final tappable = onStepTapped != null && step <= highestCompletedStep && !current;

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

          final column = Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 3,
                      color: step == 1 ? Colors.transparent : _lineColor(_connectorDone(step - 1)),
                    ),
                  ),
                  circle,
                  Expanded(
                    child: Container(
                      height: 3,
                      color: step == totalSteps ? Colors.transparent : _lineColor(_connectorDone(step)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                labels[index],
                textAlign: TextAlign.center,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  // 10, not 9: nothing that has to be read goes below the
                  // design system's smallest size.
                  fontSize: 10,
                  color: (done || current)
                      ? AppColors.success
                      : AppColors.textdark.withValues(alpha: 0.55),
                  fontWeight: current ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          );

          return Expanded(
            child: tappable
                ? Semantics(
                    button: true,
                    label: 'Go back to ${labels[index]}',
                    child: GestureDetector(
                      // The whole column, circle and label, is the target.
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onStepTapped!(step),
                      child: column,
                    ),
                  )
                : column,
          );
        }),
      ),
    );
  }
}

/// Back / Next button row for multi-step forms.
///
/// Back appears whenever [onBack] is given. While [busy], both buttons are
/// disabled and Next shows [busyLabel], so a slow submit cannot be sent twice
/// and the user can see it is working.
class StepNavButtons extends StatelessWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final String nextLabel;
  final String backLabel;
  final bool isLastStep;
  final bool busy;
  final String busyLabel;

  const StepNavButtons({
    super.key,
    this.onBack,
    this.onNext,
    this.nextLabel = 'NEXT',
    this.backLabel = 'BACK',
    this.isLastStep = false,
    this.busy = false,
    this.busyLabel = 'PLEASE WAIT…',
  });

  @override
  Widget build(BuildContext context) {
    final next = ElevatedButton(
      onPressed: busy ? null : onNext,
      child: Text(busy ? busyLabel : nextLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
    );

    return Row(
      children: [
        if (onBack != null) ...[
          Expanded(
            child: OutlinedButton(
              onPressed: busy ? null : onBack,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary),
                minimumSize: const Size(0, 48),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.25),
              ),
              child: Text(backLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(child: next),
      ],
    );
  }
}

/// The band at the top of every registration screen: a back button, the title
/// and a subtitle.
///
/// It reads the real status bar height, so the title never sits under a notch,
/// and the back button gives every step a visible way out. An empty slot the
/// size of the button balances the other side, so the title stays centred.
class RegistrationHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const RegistrationHeader({
    super.key,
    this.title = 'On Go Registration',
    this.subtitle = 'Complete all steps to provide services',
  });

  @override
  Widget build(BuildContext context) {
    final canGoBack = Navigator.of(context).canPop();

    return Container(
      width: double.infinity,
      color: AppColors.primary,
      padding: EdgeInsets.fromLTRB(4, MediaQuery.paddingOf(context).top + 8, 4, 16),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: canGoBack
                ? IconButton(
                    icon: Icon(Icons.arrow_back, color: AppColors.textlight),
                    tooltip: 'Back',
                    onPressed: () => Navigator.maybePop(context),
                  )
                : null,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textlight,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textlight, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

/// A labelled set of radio choices laid out in a row.
///
/// The word next to each radio is part of its tap area, and the radios are
/// drawn compact, so they line up with the left edge of the fields above and
/// below instead of sitting indented inside Material's 48-point padding.
class OnGoChoiceRow extends StatelessWidget {
  final String label;
  final bool isRequired;
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;

  const OnGoChoiceRow({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.isRequired = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OnGoFieldLabel(label, isRequired: isRequired),
        const SizedBox(height: 4),
        Wrap(
          spacing: 16,
          children: [
            for (final option in options)
              InkWell(
                borderRadius: AppRadii.borderSm,
                onTap: () => onChanged(option),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 6, right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Radio<String>(
                        value: option,
                        // ignore: deprecated_member_use
                        groupValue: value,
                        activeColor: AppColors.primary,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        // ignore: deprecated_member_use
                        onChanged: (picked) {
                          if (picked != null) onChanged(picked);
                        },
                      ),
                      const SizedBox(width: 4),
                      Text(option, style: TextStyle(fontSize: 13, color: AppColors.textdark)),
                    ],
                  ),
                ),
              ),
          ],
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

  /// What the keyboard's action key does, and what happens when it is pressed.
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

  /// Caps the length and hides the counter — for a fixed-length code.
  final int? maxLength;

  const AuthTextField({
    super.key,
    required this.hint,
    this.obscure = false,
    this.controller,
    this.keyboardType = TextInputType.text,
    this.suffixIcon,
    this.onChanged,
    this.textInputAction,
    this.onSubmitted,
    this.autofillHints,
    this.maxLength,
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
      enableSuggestions: !obscure,
      autocorrect: !obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      maxLength: maxLength,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
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
        counterText: maxLength == null ? null : '',
        border: border,
        enabledBorder: border,
        // Same colour, heavier line: the field being typed into is visible at
        // a glance without the palette changing.
        focusedBorder: border.copyWith(borderSide: border.borderSide.copyWith(width: 2.5)),
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
