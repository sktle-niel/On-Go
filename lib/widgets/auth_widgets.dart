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

/// The wordmark and a line under it, set on the page rather than on a band.
class OnGoHeader extends StatelessWidget {
  final String subtitle;
  const OnGoHeader({super.key, this.subtitle = 'Service Anywhere'});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // The status bar's real height rather than a fixed 48, which was too
      // little under a notch and too much on a phone without one.
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 16, 20, 20),
      child: Column(
        children: [
          Text(
            'On Go',
            style: TextStyle(
              color: AppColors.primary,
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
    this.nextLabel = 'Next',
    this.backLabel = 'Back',
    this.isLastStep = false,
    this.busy = false,
    this.busyLabel = 'Please wait…',
  });

  @override
  Widget build(BuildContext context) {
    // The one red button on the form; Back is ink on an outline beside it.
    final next = PressScale(
      enabled: !busy && onNext != null,
      child: ElevatedButton(
        onPressed: busy ? null : onNext,
        child: Text(busy ? busyLabel : nextLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );

    return Row(
      children: [
        if (onBack != null) ...[
          Expanded(
            child: OutlinedButton(
              onPressed: busy ? null : onBack,
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

    // The page's own surface with a hairline under it, like every app bar.
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: AppHairline.side(AppColors.textmedium)),
      ),
      padding: EdgeInsets.fromLTRB(4, MediaQuery.paddingOf(context).top + 8, 4, 14),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: canGoBack
                ? IconButton(
                    icon: Icon(Icons.arrow_back, color: AppColors.textdark),
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
                    color: AppColors.textdark,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textmedium, fontSize: 12),
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

// ═══════════════════════════════════════════════════════════════════════════
//  The front door: Sign In, Welcome, Forgot Password, the session restore
// ═══════════════════════════════════════════════════════════════════════════

/// The page every screen outside the app proper is built on.
///
/// A brand hero across the top and a white sheet with rounded top corners
/// rising over it — the front door of a ride-hailing app, with the brand
/// colour doing the welcoming and the sheet doing the work. The hero paints
/// the photo an admin published from the console when there is one.
///
/// The sheet scrolls only when it has to. With the keyboard up the hero folds
/// to a slim band so the form keeps the room, and the field being typed into
/// is brought above the keyboard; when everything fits, [footer] sits on the
/// bottom edge and nothing moves.
class AuthPage extends StatelessWidget {
  /// The sheet's content, top down.
  final List<Widget> children;

  /// Pinned to the bottom of the sheet: the "already have an account?" line.
  final Widget? footer;

  /// A back button on the hero, for a screen reached from another one.
  final bool showBack;

  /// The slim hero from the start, for a page that is mostly form and needs
  /// the room more than the picture.
  final bool compactHero;

  /// What the back button does. Null pops the route; a stepped form passes
  /// something that first walks back through its steps.
  final VoidCallback? onBack;

  const AuthPage({
    super.key,
    required this.children,
    this.footer,
    this.showBack = false,
    this.compactHero = false,
    this.onBack,
  });

  /// The sheet's corner radius — how much hero shows beside the corners.
  static const double sheetRadius = 28;

  /// The widest the sheet's content gets. A sign-in form a foot wide, on a
  /// tablet or a phone on its side, looks like a mistake.
  static const double contentMaxWidth = 480;

  @override
  Widget build(BuildContext context) {
    final layout = context.layout;
    final media = MediaQuery.of(context);
    final top = media.padding.top;
    // The hero gives way to the form: folded when the page asks for it,
    // whenever the keyboard is up, or when the window is too short to spare
    // a third of itself.
    final compact = compactHero || media.viewInsets.bottom > 0 || layout.isShort;
    final heroHeight = compact
        ? top + AuthHero.compactHeight
        : (layout.height * 0.32).clamp(top + 184, top + 280).toDouble();
    final c = AppColors.palette;

    return Scaffold(
      // The hero colour is the page: it is what shows beside the sheet's
      // rounded corners.
      backgroundColor: c.primary,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        // The clock sits on the hero, so it is drawn light on every theme.
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: c.surface,
          systemNavigationBarIconBrightness:
              AppColors.isDark ? Brightness.light : Brightness.dark,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthHero(height: heroHeight, compact: compact, showBack: showBack, onBack: onBack),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(sheetRadius)),
                child: ColoredBox(
                  color: c.surface,
                  child: SafeArea(
                    top: false,
                    child: _AuthSheet(footer: footer, children: children),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The white sheet: [AuthPage]'s content, scrolling only when it must.
class _AuthSheet extends StatelessWidget {
  final List<Widget> children;
  final Widget? footer;

  const _AuthSheet({required this.children, this.footer});

  @override
  Widget build(BuildContext context) {
    final side = context.layout.isTablet ? 32.0 : 24.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Past the reading measure the content centres and the rest of the
        // width becomes margin.
        final slack = (constraints.maxWidth - AuthPage.contentMaxWidth) / 2;
        final inset = slack > side ? slack : side;

        // Inside a scroll view the sheet has somewhere to go when the
        // keyboard takes half the screen. The minimum height is the full
        // height available, so when everything fits the footer still sits on
        // the bottom edge, and clamping physics stop it bouncing when there
        // is nothing to scroll. IntrinsicHeight gives the column a definite
        // height — the taller of the sheet and its content — for the Spacer
        // above the footer to fill.
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: _SheetEntrance(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(inset, 28, inset, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...children,
                      if (footer != null) ...[
                        const Spacer(),
                        const SizedBox(height: 20),
                        footer!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The sheet's content settling into place as the screen opens: a short
/// rise and fade, once. Skipped when the reader has asked for no animation.
class _SheetEntrance extends StatelessWidget {
  final Widget child;

  const _SheetEntrance({required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.slow,
      curve: AppMotion.enter,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}

/// The brand hero across the top of every [AuthPage]: the wordmark over a
/// photo of the trade, tinted the brand colour — the one the app ships with,
/// or the one an admin published from the console.
///
/// [height] includes the status bar, which the hero runs under. While
/// [compact] it is a slim band with the wordmark alone, so the form keeps the
/// room when the keyboard is up.
class AuthHero extends StatelessWidget {
  final double height;
  final bool compact;
  final bool showBack;

  /// What the back button does; null pops the route.
  final VoidCallback? onBack;

  const AuthHero({
    super.key,
    required this.height,
    this.compact = false,
    this.showBack = false,
    this.onBack,
  });

  /// The band the hero folds to, below the status bar.
  static const double compactHeight = 64;

  /// The photo the app ships with: a mechanic leaning into an engine bay in
  /// daylight (Pexels, free licence; see assets/images/README.md).
  static const String defaultPhoto = 'assets/images/auth_hero.jpg';

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final top = MediaQuery.paddingOf(context).top;

    return AnimatedContainer(
      duration: AppMotion.slow,
      curve: AppMotion.move,
      height: height,
      child: AnimatedBuilder(
        animation: AuthBackgroundController.instance,
        builder: (context, _) {
          final photo = AuthBackgroundController.instance.photoPath;
          final ImageProvider scene =
              photo == null ? const AssetImage(AuthHero.defaultPhoto) : FileImage(File(photo));
          return Stack(
            fit: StackFit.expand,
            children: [
              // The colour first, so there is never a blank while the photo
              // decodes or if it cannot be read.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [c.primary, c.primarydark],
                  ),
                ),
              ),
              // The scene, multiplied by the brand colour: it reads in red and
              // stays a backdrop for the words rather than competing with them.
              Image(
                image: scene,
                fit: BoxFit.cover,
                color: c.primary,
                colorBlendMode: BlendMode.multiply,
                // Fades in once decoded rather than popping over the colour.
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded) return child;
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: AppMotion.normal,
                    curve: AppMotion.enter,
                    child: child,
                  );
                },
                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
              ),
              // A shade that deepens towards the wordmark, for legibility.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      c.primarydark.withValues(alpha: 0.05),
                      c.primarydark.withValues(alpha: 0.70),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, top, 24, 0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Decided by the room there is right now, not by
                      // [compact]: the band animates between its two heights,
                      // and the full block must never be asked to fit a
                      // height it cannot.
                      final full = constraints.maxHeight >= 172;
                      if (!full) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            // Clear of the back button beside it.
                            padding: EdgeInsets.only(left: showBack ? 48 : 0),
                            child: const _Brand(compact: true),
                          ),
                        );
                      }
                      return const Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 24),
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          // Scales down rather than overflowing at the largest
                          // text sizes.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.bottomLeft,
                            child: _Brand(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (showBack)
                Positioned(
                  top: top + 6,
                  left: 12,
                  child: IconButton(
                    onPressed: onBack ?? () => Navigator.maybePop(context),
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_rounded, size: 22),
                    style: IconButton.styleFrom(
                      backgroundColor: c.textlight.withValues(alpha: 0.18),
                      foregroundColor: c.textlight,
                      minimumSize: const Size(44, 44),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The wordmark on the hero, with the tagline under it when there is room.
class _Brand extends StatelessWidget {
  final bool compact;

  const _Brand({this.compact = false});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final wordmark = Text(
      'On Go',
      style: TextStyle(
        color: c.textlight,
        fontSize: compact ? 20 : 34,
        fontWeight: FontWeight.w800,
        letterSpacing: compact ? -0.4 : -1.0,
        height: 1.1,
      ),
    );
    if (compact) return wordmark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        wordmark,
        const SizedBox(height: 4),
        Text(
          'Service Anywhere',
          style: TextStyle(
            color: c.textlight.withValues(alpha: 0.88),
            fontSize: 15,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

/// The headline at the top of the sheet and the line under it. Set left,
/// like a page rather than a dialog.
class AuthIntro extends StatelessWidget {
  final String title;
  final String? subtitle;

  const AuthIntro({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.15,
            color: c.textdark,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: TextStyle(fontSize: 14, height: 1.4, color: c.textmedium),
          ),
        ],
      ],
    );
  }
}

/// A field on the sheet: a soft well with a faint outline and its name inside,
/// which rises onto the top edge as the field fills. The brand colour appears
/// only while it has focus — the outline and the floated name.
class AuthTextField extends StatelessWidget {
  /// The field's name: "Email", "Password", "6-digit code".
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

  /// What is wrong with the value, under the field in the error colour.
  final String? errorText;

  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;

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
    this.errorText,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: AppRadii.borderMd,
          borderSide: width == 0 ? BorderSide.none : BorderSide(color: color, width: width),
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
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      cursorColor: c.primary,
      style: TextStyle(color: c.textdark, fontSize: 16, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: hint,
        labelStyle: TextStyle(color: c.textmedium, fontSize: 15),
        // Drawn at three quarters of this size once it has floated.
        floatingLabelStyle: WidgetStateTextStyle.resolveWith(
          (states) => TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.error)
                ? c.error
                : states.contains(WidgetState.focused)
                    ? c.primary
                    : c.textmedium,
          ),
        ),
        filled: true,
        fillColor: c.background,
        suffixIcon: suffixIcon,
        suffixIconColor: c.textmedium,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        counterText: maxLength == null ? null : '',
        errorText: errorText,
        errorStyle: TextStyle(fontSize: 12, color: c.error),
        // A faint outline at rest, so the floated name has a line to sit on.
        border: border(AppHairline.outline(c.textmedium), 1),
        enabledBorder: border(AppHairline.outline(c.textmedium), 1),
        focusedBorder: border(c.primary, 1.5),
        errorBorder: border(c.error, 1),
        focusedErrorBorder: border(c.error, 1.5),
      ),
    );
  }
}

/// The one brand-coloured button on the sheet: full width, tall enough for a
/// thumb, and answering the press. While [busy] it keeps its colour and shows
/// it is working, rather than going grey as if it had been switched off.
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);

    return PressScale(
      enabled: onPressed != null && !busy,
      child: ElevatedButton(
        onPressed: busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.borderLg),
          disabledBackgroundColor: busy ? c.primary.withValues(alpha: 0.72) : null,
          disabledForegroundColor: busy ? c.textlight : null,
          textStyle: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
        child: busy
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: c.textlight),
                  ),
                  const SizedBox(width: 10),
                  Flexible(child: text),
                ],
              )
            : text,
      ),
    );
  }
}

/// The line at the foot of the sheet: a prompt and the one link that answers
/// it — "Don't have an account? Sign Up".
///
/// Wrap, not Row: at a large system text scale the prompt and the link no
/// longer fit side by side, and the link drops to its own line instead of
/// overflowing. Identical to a centred Row when it does fit.
class AuthFooterLink extends StatelessWidget {
  final String? prompt;
  final String action;
  final VoidCallback onTap;

  const AuthFooterLink({
    super.key,
    this.prompt,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (prompt != null) Text(prompt!, style: TextStyle(fontSize: 14, color: c.textmedium)),
        TextButton(
          onPressed: onTap,
          // A real tap area; with zero padding and no minimum size the link
          // was only as big as its letters.
          style: TextButton.styleFrom(
            foregroundColor: c.primary,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            minimumSize: const Size(48, 44),
          ),
          child: Text(
            action,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// The other button on the sheet: ink on an outline, the same size and shape
/// as [AuthPrimaryButton], for the path that is offered but not urged —
/// "Continue with Google" above the form.
class AuthSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  /// A mark to the left of the label.
  final Widget? leading;

  const AuthSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    return PressScale(
      enabled: onPressed != null,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.borderLg),
          side: BorderSide(color: AppHairline.outline(c.textmedium)),
          foregroundColor: c.textdark,
          textStyle: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}
