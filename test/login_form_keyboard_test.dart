import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_go/screens/auth/forgot_password_screen.dart';
import 'package:on_go/screens/auth/sign_in_screen.dart';
import 'package:on_go/screens/welcome_screen.dart';
import 'package:on_go/theme/app_theme.dart';
import 'package:on_go/widgets/auth_widgets.dart';

/// The login form with the keyboard up.
///
/// With the keyboard open the Scaffold gave the sign-in card less height than
/// it needed, and a card that could not scroll overflowed — the warning stripe
/// painted over "Don't have account? Sign Up". The card now scrolls when, and
/// only when, it has to.

// ═══════════════════════════════════════════════════════════════════════════
//  Harness
// ═══════════════════════════════════════════════════════════════════════════

/// Mirrors main.dart's MaterialApp.builder — without the extra Scaffold the
/// responsive sweep wraps screens in. These screens are Scaffolds themselves,
/// and a second one would take the keyboard's height off the body twice,
/// making every keyboard measurement here wrong.
Widget _app(Size size, Widget home, {double keyboard = 0, double textScale = 1}) {
  return MediaQuery(
    data: MediaQueryData(
      size: size,
      textScaler: TextScaler.linear(textScale),
      viewInsets: EdgeInsets.only(bottom: keyboard),
    ),
    child: Builder(builder: (context) {
      final media = MediaQuery.of(context);
      final layout = AppLayout.fromSize(media.size);
      return MediaQuery(
        data: media.copyWith(textScaler: layout.textScalerFrom(media.textScaler)),
        child: AppLayoutScope(
          layout: layout,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.themeFor(AppThemes.all.first),
            home: home,
          ),
        ),
      );
    }),
  );
}

void _setView(WidgetTester tester, Size size, {double keyboard = 0}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  // The View's inset, not just MediaQuery's: a focused text field listens to
  // the View to decide when the keyboard has arrived and it must scroll into
  // sight.
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
}

Future<void> _pump(
  WidgetTester tester,
  Size size,
  Widget home, {
  double keyboard = 0,
  double textScale = 1,
}) async {
  _setView(tester, size, keyboard: keyboard);
  await tester.pumpWidget(_app(size, home, keyboard: keyboard, textScale: textScale));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Runs [body], returning every error Flutter reported while it ran. The
/// handler is restored before this returns — flutter_test checks it at the
/// end of the test body, so restoring it in a tearDown is too late.
Future<List<String>> _collectErrors(Future<void> Function() body) async {
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (d) => errors.add(d.toString());
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return errors;
}

List<String> _overflows(List<String> errors) =>
    errors.where((e) => e.contains('overflowed')).toList();

const _devices = <String, Size>{
  'small phone 320x568': Size(320, 568),
  'android 360x640': Size(360, 640),
  'phone 390x844': Size(390, 844),
  'large phone 430x932': Size(430, 932),
  'tablet 834x1112': Size(834, 1112),
  'landscape 844x390': Size(844, 390),
};

Finder get _cardScrollable => find
    .descendant(of: find.byType(AuthBottomCard), matching: find.byType(Scrollable))
    .first;

// ═══════════════════════════════════════════════════════════════════════════
//  Tests
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  group('Sign In with the keyboard open', () {
    for (final device in _devices.entries) {
      testWidgets('does not overflow, and every control stays reachable @ ${device.key}',
          (tester) async {
        // The emoji keyboard in the report covers more than half the screen.
        final keyboard = device.value.height * 0.55;

        final errors = await _collectErrors(
          () => _pump(tester, device.value, const SignInScreen(), keyboard: keyboard),
        );
        expect(_overflows(errors), isEmpty);

        // The link the overflow stripe was painted over in the report.
        await tester.scrollUntilVisible(find.text('Sign Up'), 40, scrollable: _cardScrollable);
        expect(find.text('Sign Up').hitTestable(), findsOneWidget);

        await tester.scrollUntilVisible(find.text('Sign In'), -40, scrollable: _cardScrollable);
        expect(find.text('Sign In').hitTestable(), findsOneWidget);

        // The field, not its hint. The hint is painted underneath the text
        // input, so a tap there lands on the field and the hint itself is
        // never the thing hit.
        final username =
            find.ancestor(of: find.text('Username'), matching: find.byType(TextField));
        await tester.scrollUntilVisible(username, -40, scrollable: _cardScrollable);
        expect(username.hitTestable(), findsOneWidget);
      });
    }

    testWidgets('holds at the largest text size on a small phone', (tester) async {
      const size = Size(320, 568);
      final errors = await _collectErrors(
        () => _pump(tester, size, const SignInScreen(), keyboard: size.height * 0.55, textScale: 2.0),
      );
      expect(_overflows(errors), isEmpty);
      await tester.scrollUntilVisible(find.text('Sign Up'), 40, scrollable: _cardScrollable);
      expect(find.text('Sign Up').hitTestable(), findsOneWidget);
    });

    testWidgets('a field scrolled out of sight comes back when it takes focus', (tester) async {
      // A phone on its side with the keyboard up leaves the least room of any
      // supported screen; scrolled down to Sign Up, Username is off the top.
      const size = Size(844, 390);
      const keyboard = 214.0;
      await _pump(tester, size, const SignInScreen(), keyboard: keyboard);

      await tester.scrollUntilVisible(find.text('Sign Up'), 40, scrollable: _cardScrollable);
      final username = find.byType(EditableText).first;
      expect(tester.getRect(username).bottom, lessThan(0),
          reason: 'the precondition: Username has scrolled out of sight');

      await tester.showKeyboard(username);
      await tester.pumpAndSettle();

      final rect = tester.getRect(username);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(size.height - keyboard));
    });

    testWidgets('without the keyboard the card still sits on the bottom edge', (tester) async {
      const size = Size(390, 844);
      await _pump(tester, size, const SignInScreen());

      // Anchored to the bottom, as before — not pulled up to the top by the
      // scroll view it now sits in.
      expect(tester.getRect(find.text('Sign Up')).bottom, greaterThan(size.height - 120));
      expect(tester.getRect(find.text('Username')).top, greaterThan(size.height / 3));

      // And nothing to scroll: it fits.
      final position = tester.state<ScrollableState>(_cardScrollable).position;
      expect(position.maxScrollExtent, 0);
    });

    testWidgets('Sign Up still opens registration from under the keyboard', (tester) async {
      const size = Size(360, 640);
      await _pump(tester, size, const SignInScreen(), keyboard: size.height * 0.55);

      await tester.scrollUntilVisible(find.text('Sign Up'), 40, scrollable: _cardScrollable);
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });

    testWidgets('Forgot Password? still opens the reset flow from under the keyboard',
        (tester) async {
      const size = Size(360, 640);
      await _pump(tester, size, const SignInScreen(), keyboard: size.height * 0.55);

      await tester.scrollUntilVisible(find.text('Forgot Password?'), 40, scrollable: _cardScrollable);
      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    });
  });

  group('the other screens on the same card', () {
    for (final device in _devices.entries) {
      for (final screen in <String, Widget>{
        'Forgot Password': const ForgotPasswordScreen(),
        'Welcome': const WelcomeScreen(),
      }.entries) {
        testWidgets('${screen.key} does not overflow with the keyboard open @ ${device.key}',
            (tester) async {
          final errors = await _collectErrors(
            () => _pump(tester, device.value, screen.value, keyboard: device.value.height * 0.55),
          );
          expect(_overflows(errors), isEmpty);
        });
      }
    }
  });
}
