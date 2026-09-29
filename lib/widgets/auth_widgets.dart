import 'dart:io';
import 'dart:math' as math;

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

/// The colours of the pages before sign-in.
///
/// Those pages are dark on every theme, the way a ride app's sign-in is: a
/// photo at night over a dark sheet. So their widgets read the dark member of
/// the theme family in force from here, rather than [AppColors], which follows
/// the app's own light or dark setting. An [InheritedTheme], so a sheet or a
/// dialog opened from one of these pages keeps the same colours.
class AuthScheme extends InheritedTheme {
  final AppPalette palette;

  const AuthScheme({super.key, required this.palette, required super.child});

  /// The dark theme of the family in force: the one the pages are drawn in.
  static AppThemeOption get darkTheme => AppThemes.variantOf(ThemeController.instance.selected, dark: true);

  /// The palette of the nearest [AuthPage], or the app's own outside one.
  static AppPalette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthScheme>()?.palette ?? AppColors.palette;

  @override
  Widget wrap(BuildContext context, Widget child) => AuthScheme(palette: palette, child: child);

  @override
  bool updateShouldNotify(AuthScheme oldWidget) => oldWidget.palette != palette;
}

/// The words over the photo on an [AuthPage]: a line in white and its end in
/// the brand colour, underlined with a stroke of it. "Let's get you" and
/// "moving again".
class AuthHeadline {
  final String lead;
  final String accent;

  const AuthHeadline({required this.lead, required this.accent});
}

/// A picture for the top of an [AuthPage] in place of the default photo.
class AuthPhoto {
  /// The bundled picture.
  final String asset;

  /// Which part of the picture stays in view where the hero crops it.
  final Alignment alignment;

  /// The words painted into the picture, for a screen reader. Set when the
  /// picture carries its own headline: the page then leaves its top undimmed
  /// so those words stay bright, starts the picture below the status bar so
  /// the clock never sits on them, and puts no wordmark of its own over them.
  final String? words;

  /// The colour above a picture with [words], behind the status bar: its own
  /// top edge, so the step down does not show.
  final Color? backdrop;

  const AuthPhoto(this.asset, {this.alignment = Alignment.center, this.words, this.backdrop});

  /// The picture on Sign In and Registration: a mechanic on a motorcycle in a
  /// city at night, with "Book a Mechanic through our app" painted into its
  /// top left (see assets/images/README.md). Kept to the left where it crops,
  /// so the words stay whole.
  static const AuthPhoto mobileMechanic = AuthPhoto(
    'assets/images/sign_in_hero.jpg',
    alignment: Alignment.topLeft,
    words: 'Book a mechanic through our app',
    backdrop: Color(0xFF131E2E),
  );
}

/// The page every screen outside the app proper is built on.
///
/// A photo of the trade across the top, darkened towards the bottom, and a
/// dark sheet with rounded top corners rising over it: the front door of a
/// ride-hailing app. The photo is the one an admin published from the console
/// when there is one. The page is dark on every theme (see [AuthScheme]).
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

  /// Words over the photo in place of the wordmark.
  final AuthHeadline? headline;

  /// The picture across the top, when a page has its own. Null is
  /// [AuthHero.defaultPhoto]. A background the console published wins over
  /// either.
  final AuthPhoto? photo;

  const AuthPage({
    super.key,
    required this.children,
    this.footer,
    this.showBack = false,
    this.compactHero = false,
    this.onBack,
    this.headline,
    this.photo,
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
    // The picture and the form share the screen half and half. The hero gives
    // way to the form: folded when the page asks for it, whenever the
    // keyboard is up, or when the window is too short to spare half of itself.
    final compact = compactHero || media.viewInsets.bottom > 0 || layout.isShort;
    final heroHeight = compact ? top + AuthHero.compactHeight : layout.height * 0.5;
    final theme = AuthScheme.darkTheme;
    final c = theme.palette;

    return Theme(
      data: AppTheme.themeFor(theme),
      child: AuthScheme(
        palette: c,
        child: Scaffold(
          backgroundColor: c.background,
          body: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
              systemNavigationBarColor: c.surface,
              systemNavigationBarIconBrightness: Brightness.light,
            ),
            child: Stack(
              children: [
                // The photo across the top, fading into the page; the sheet
                // rises over its lower edge.
                AnimatedPositioned(
                  duration: AppMotion.slow,
                  curve: AppMotion.move,
                  top: 0,
                  left: 0,
                  right: 0,
                  height: heroHeight + AuthPage.sheetRadius + 40,
                  child: _AuthScene(photo: photo, clearOfBack: showBack),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AuthHero(
                      height: heroHeight,
                      compact: compact,
                      showBack: showBack,
                      onBack: onBack,
                      headline: headline,
                      photoHasWords: photo?.words != null,
                    ),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(sheetRadius)),
                          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, -6))],
                        ),
                        child: SafeArea(
                          top: false,
                          child: _AuthSheet(footer: footer, children: children),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The photo behind the top of an [AuthPage], in its own colours, darkened
/// towards the bottom so the words over it read and the sheet takes over.
class _AuthScene extends StatelessWidget {
  final AuthPhoto? photo;

  /// The page has a back button at the top left, where a picture's words
  /// begin, so a picture with words steps down below it too.
  final bool clearOfBack;

  const _AuthScene({this.photo, this.clearOfBack = false});

  /// The row the back button takes, below the status bar.
  static const double _backRow = 52;

  @override
  Widget build(BuildContext context) {
    final c = AuthScheme.of(context);
    return AnimatedBuilder(
      animation: AuthBackgroundController.instance,
      builder: (context, _) {
        final published = AuthBackgroundController.instance.photoPath;
        final own = published == null ? photo : null;
        final ImageProvider scene = published != null
            ? FileImage(File(published))
            : AssetImage(own?.asset ?? AuthHero.defaultPhoto);
        final words = own?.words;
        return Stack(
          fit: StackFit.expand,
          children: [
            // The page colour first, so there is never a blank while the photo
            // decodes or if it cannot be read. Above a picture with words, its
            // own top edge colour, behind the status bar.
            ColoredBox(color: words == null ? c.background : (own?.backdrop ?? c.background)),
            Padding(
              // Words painted into the picture start below the clock, and
              // below the back button when there is one.
              padding: EdgeInsets.only(
                top: words == null ? 0 : MediaQuery.paddingOf(context).top + (clearOfBack ? _backRow : 0),
              ),
              child: Image(
                image: scene,
                fit: BoxFit.cover,
                alignment: own?.alignment ?? Alignment.center,
                semanticLabel: words,
                excludeFromSemantics: words == null,
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
            ),
            // Dark at the top for the clock and the words, darker at the foot
            // where the sheet meets it. A picture with words of its own keeps
            // its top bright: only a faint shade for the clock.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    c.background.withValues(alpha: words == null ? 0.72 : 0.30),
                    c.background.withValues(alpha: words == null ? 0.28 : 0.0),
                    c.background.withValues(alpha: 0.88),
                  ],
                  stops: [0, words == null ? 0.45 : 0.12, 1],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The sheet's content, scrolling only when it must.
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
                  padding: EdgeInsets.fromLTRB(inset, 24, inset, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...children,
                      if (footer != null) ...[
                        const Spacer(),
                        const SizedBox(height: 16),
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

/// The top of every [AuthPage], over the photo: a [headline] near the top, or
/// the wordmark near the bottom, and the back button. It is see-through; the
/// photo behind it belongs to the page, so it can run on under the sheet.
///
/// [height] includes the status bar, which the hero runs under. While
/// [compact] it is a slim band with the wordmark alone, so the form keeps the
/// room when the keyboard is up.
class AuthHero extends StatelessWidget {
  final double height;
  final bool compact;
  final bool showBack;
  final AuthHeadline? headline;

  /// The page's picture carries its own words ([AuthPhoto.words]), so the
  /// hero draws no wordmark over it, unless the console's published
  /// background has replaced that picture.
  final bool photoHasWords;

  /// What the back button does; null pops the route.
  final VoidCallback? onBack;

  const AuthHero({
    super.key,
    required this.height,
    this.compact = false,
    this.showBack = false,
    this.onBack,
    this.headline,
    this.photoHasWords = false,
  });

  /// The band the hero folds to, below the status bar.
  static const double compactHeight = 64;

  /// The photo the app ships with: a mechanic leaning into an engine bay in
  /// daylight (Pexels, free licence; see assets/images/README.md).
  static const String defaultPhoto = 'assets/images/auth_hero.jpg';

  @override
  Widget build(BuildContext context) {
    final c = AuthScheme.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final words = headline;

    return AnimatedContainer(
      duration: AppMotion.slow,
      curve: AppMotion.move,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, top, 24, 0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // The picture's own words are the headline; nothing goes over
                  // them.
                  if (photoHasWords && AuthBackgroundController.instance.photoPath == null) {
                    return const SizedBox.shrink();
                  }
                  // Decided by the room there is right now, not by [compact]:
                  // the band animates between its two heights, and the full
                  // block must never be asked to fit a height it cannot.
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
                  if (words != null) {
                    return Padding(
                      padding: EdgeInsets.only(top: showBack ? 60 : 28),
                      child: Align(
                        alignment: Alignment.topLeft,
                        // Scales down rather than overflowing at the largest
                        // text sizes.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topLeft,
                          child: _Headline(headline: words),
                        ),
                      ),
                    );
                  }
                  return const Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 24),
                    child: Align(
                      alignment: Alignment.bottomLeft,
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
                  backgroundColor: c.textlight.withValues(alpha: 0.16),
                  foregroundColor: c.textlight,
                  minimumSize: const Size(44, 44),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The headline over the photo: [AuthHeadline.lead] in white, and the accent
/// under it in the brand colour with a brush stroke beneath.
class _Headline extends StatelessWidget {
  final AuthHeadline headline;

  const _Headline({required this.headline});

  @override
  Widget build(BuildContext context) {
    final c = AuthScheme.of(context);
    const size = 32.0;
    return Semantics(
      header: true,
      label: '${headline.lead} ${headline.accent}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline.lead,
            style: TextStyle(
              color: c.textlight,
              fontSize: size,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              height: 1.12,
            ),
          ),
          CustomPaint(
            foregroundPainter: _BrushStroke(color: c.primary),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                headline.accent,
                style: TextStyle(
                  color: c.primary,
                  fontSize: size,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  height: 1.12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A brush stroke under the accent: a shallow curve, thick in the middle and
/// thin at the ends.
class _BrushStroke extends CustomPainter {
  final Color color;

  const _BrushStroke({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height - 5;
    final path = Path()
      ..moveTo(2, y)
      ..quadraticBezierTo(size.width * 0.5, y - 7, size.width * 0.92, y - 1)
      ..quadraticBezierTo(size.width * 0.5, y - 3, 2, y + 2)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BrushStroke oldDelegate) => oldDelegate.color != color;
}

/// The wordmark on the hero, with the tagline under it when there is room.
class _Brand extends StatelessWidget {
  final bool compact;

  const _Brand({this.compact = false});

  @override
  Widget build(BuildContext context) {
    final c = AuthScheme.of(context);
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
    final c = AuthScheme.of(context);
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

/// A field on the sheet: an outlined well with a placeholder inside. The
/// field's name sits above it in bold, or, with [labelAbove] off, only its
/// [icon] and the placeholder say what it is, as on the sign-in form. The
/// brand colour appears only while it has focus; an error turns the outline
/// red and explains itself underneath.
class AuthTextField extends StatelessWidget {
  /// The field's name: "Email", "Password", "First name".
  final String label;

  /// The prompt inside the empty field: "Enter your email". Without one, the
  /// [label] is the prompt.
  final String? hint;

  /// A glyph at the start of the well.
  final IconData? icon;

  /// The name above the field. Off, the field shows only its [icon] and
  /// prompt, and the name is what a screen reader says.
  final bool labelAbove;

  final bool obscure;

  /// Off for what a person types exactly: an email, a username.
  final bool autocorrect;
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
    required this.label,
    this.hint,
    this.icon,
    this.labelAbove = true,
    this.obscure = false,
    this.autocorrect = true,
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
    final c = AuthScheme.of(context);
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );
    final outline = c.textmedium.withValues(alpha: 0.38);

    final field = TextFormField(
      controller: controller,
      obscureText: obscure,
      enableSuggestions: !obscure && autocorrect,
      autocorrect: !obscure && autocorrect,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      maxLength: maxLength,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      cursorColor: c.primary,
      style: TextStyle(color: c.textdark, fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint ?? label,
        hintStyle: TextStyle(color: c.textmedium, fontSize: 15, fontWeight: FontWeight.w400),
        filled: true,
        fillColor: c.textdark.withValues(alpha: 0.04),
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
        prefixIconColor: c.textmedium,
        suffixIcon: suffixIcon,
        suffixIconColor: c.textmedium,
        contentPadding: EdgeInsets.symmetric(horizontal: icon == null ? 16 : 12, vertical: 17),
        counterText: maxLength == null ? null : '',
        errorText: errorText,
        errorStyle: TextStyle(fontSize: 12, color: c.error),
        border: border(outline, 1),
        enabledBorder: border(outline, 1),
        focusedBorder: border(c.primary, 1.5),
        errorBorder: border(c.error, 1),
        focusedErrorBorder: border(c.error, 1.5),
      ),
    );

    if (!labelAbove) return Semantics(label: label, child: field);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textdark),
        ),
        const SizedBox(height: 8),
        field,
      ],
    );
  }
}

/// The one brand-coloured button on the sheet: a full-width pill, the label
/// in the middle and a dark disc with an arrow at the end. While [busy] it
/// keeps its colour and turns the disc into a spinner, rather than going grey
/// as if it had been switched off.
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
    final c = AuthScheme.of(context);
    final enabled = onPressed != null && !busy;
    const height = 56.0;

    return PressScale(
      enabled: enabled,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        excludeSemantics: true,
        // The glow sits outside the Material: ink is clipped to the
        // Material's rectangle, which would square off the glow's ends.
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            shadows: [BoxShadow(color: c.primary.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              customBorder: const StadiumBorder(),
              child: Ink(
                height: height,
                decoration: ShapeDecoration(
                  shape: const StadiumBorder(),
                  color: onPressed == null && !busy ? c.primary.withValues(alpha: 0.45) : c.primary,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: height),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                          color: c.textlight,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 7,
                      child: Container(
                        width: height - 14,
                        height: height - 14,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF111114)),
                        child: Center(
                          child: busy
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2.2, color: c.textlight),
                                )
                              : Icon(Icons.arrow_forward_rounded, size: 20, color: c.textlight),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The line at the foot of the sheet: a prompt and the one link that answers
/// it — "Don't have an account? Register".
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
    final c = AuthScheme.of(context);
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

/// A hairline across the sheet with a word in the middle: "or".
class AuthDivider extends StatelessWidget {
  final String label;

  const AuthDivider({super.key, this.label = 'or'});

  @override
  Widget build(BuildContext context) {
    final c = AuthScheme.of(context);
    final line = Expanded(child: Divider(height: 1, thickness: 1, color: c.textmedium.withValues(alpha: 0.28)));
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label, style: TextStyle(fontSize: 13, color: c.textmedium)),
        ),
        line,
      ],
    );
  }
}

/// The other button on the sheet: ink on an outline, the same height as
/// [AuthPrimaryButton], for the path that is offered but not urged — "Sign
/// up with Google".
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
    final c = AuthScheme.of(context);
    return PressScale(
      enabled: onPressed != null,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 54),
          shape: const StadiumBorder(),
          side: BorderSide(color: c.textmedium.withValues(alpha: 0.38)),
          foregroundColor: c.textdark,
          textStyle: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 15,
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

/// Google's "G", drawn rather than shipped as a picture: four arcs of a ring
/// and the bar, in Google's own colours.
class GoogleMark extends StatelessWidget {
  final double size;

  const GoogleMark({super.key, this.size = 20});

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
