import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_go/theme/app_theme.dart';
import 'package:on_go/widgets/auth_widgets.dart';

import 'package:on_go/screens/welcome_screen.dart';
import 'package:on_go/screens/auth/sign_in_screen.dart';
import 'package:on_go/screens/auth/forgot_password_screen.dart';
import 'package:on_go/screens/auth/client_registration/client_registration_screen.dart';
import 'package:on_go/screens/auth/client_ui/client_home_screen.dart';
import 'package:on_go/screens/auth/client_ui/history/service_history_screen.dart';
import 'package:on_go/screens/auth/client_ui/home/need_help_screen.dart';
import 'package:on_go/screens/auth/client_ui/home/quotes_screen.dart';
import 'package:on_go/screens/auth/client_ui/jobs/client_jobs_screen.dart';
import 'package:on_go/screens/auth/client_ui/notifications/client_notifications_screen.dart';
import 'package:on_go/screens/auth/client_ui/profile/client_profile_screen.dart';
import 'package:on_go/screens/auth/client_ui/rank/rankings_screen.dart';
import 'package:on_go/screens/auth/client_ui/rewards/client_rewards_screen.dart';
import 'package:on_go/screens/auth/client_ui/settings/client_settings_screen.dart';
import 'package:on_go/screens/auth/mechanic_ui/earning/earning_screen.dart';
import 'package:on_go/screens/auth/mechanic_ui/earning/points_offers_screen.dart';
import 'package:on_go/screens/auth/mechanic_ui/jobs/jobs_screen.dart';
import 'package:on_go/screens/auth/mechanic_ui/mechanic_home_screen.dart';
import 'package:on_go/screens/auth/mechanic_ui/notifications/mechanic_notifications_screen.dart';
import 'package:on_go/screens/auth/mechanic_ui/profile/mechanic_certifications_screen.dart';
import 'package:on_go/screens/auth/mechanic_ui/profile/mechanic_profile_info_screen.dart';
import 'package:on_go/screens/auth/mechanic_ui/profile/mechanic_profile_screen.dart';
import 'package:on_go/screens/auth/mechanic_ui/qr/qr_screen.dart';
import 'package:on_go/screens/auth/mechanic_ui/rank/mechanic_rankings_screen.dart';
import 'package:on_go/screens/auth/mechanic_ui/settings/mechanic_settings_screen.dart';
import 'package:on_go/screens/shared/theme_screen.dart';
import 'package:on_go/screens/shared/job_chat_screen.dart';
import 'package:on_go/screens/auth/client_ui/active/active_request_screen.dart';
import 'package:on_go/screens/auth/client_ui/profile/mechanic_profile_view_screen.dart';
import 'package:on_go/screens/auth/mechanic_ui/jobs/mechanic_active_job_screen.dart';

/// The devices the app is expected to work on.
///
/// Real logical sizes, not round numbers — the point is to catch what an
/// actual device does, and the awkward ones (320 wide, a phone on its side)
/// are exactly where fixed sizes fail.
const devices = <String, Size>{
  'small phone  320x568': Size(320, 568),
  'android      360x640': Size(360, 640),
  'iphone SE    375x667': Size(375, 667),
  'iphone 14    390x844': Size(390, 844),
  'pixel 7      412x915': Size(412, 915),
  'max phone    430x932': Size(430, 932),
  'foldable     600x960': Size(600, 960),
  'ipad        768x1024': Size(768, 1024),
  'ipad air   834x1112': Size(834, 1112),
  'landscape    844x390': Size(844, 390),
};

final screens = <String, Widget Function()>{
  'WelcomeScreen': () => const WelcomeScreen(),
  'SignInScreen': () => SignInScreen(),
  'ForgotPasswordScreen': () => const ForgotPasswordScreen(),
  'ClientRegistrationScreen': () => const ClientRegistrationScreen(),
  'ClientHomeScreen': () => const ClientHomeScreen(),
  'ServiceHistoryScreen': () => const ServiceHistoryScreen(),
  'NeedHelpScreen': () => const NeedHelpScreen(),
  'QuotesScreen': () => const QuotesScreen(),
  'ClientJobsScreen': () => const ClientJobsScreen(),
  'ClientNotificationsScreen': () => const ClientNotificationsScreen(),
  'ClientProfileScreen': () => const ClientProfileScreen(),
  'RankingsScreen': () => const RankingsScreen(),
  'ClientRewardsScreen': () => const ClientRewardsScreen(),
  'ClientSettingsScreen': () => const ClientSettingsScreen(),
  'EarningScreen': () => const EarningScreen(),
  'PointsOffersScreen': () => const PointsOffersScreen(),
  'JobsScreen': () => const JobsScreen(),
  'MechanicHomeScreen': () => const MechanicHomeScreen(),
  'MechanicNotificationsScreen': () => const MechanicNotificationsScreen(),
  'MechanicCertificationsScreen': () => const MechanicCertificationsScreen(),
  'MechanicProfileInfoScreen': () => const MechanicProfileInfoScreen(),
  'MechanicProfileScreen': () => const MechanicProfileScreen(),
  'QrScreen': () => const QrScreen(),
  'MechanicRankingsScreen': () => const MechanicRankingsScreen(),
  'MechanicSettingsScreen': () => const MechanicSettingsScreen(),
  'ThemeScreen': () => const ThemeScreen(),
  // These four take an id or a name. Passing one that resolves to nothing
  // still lays out their chrome, which is what is being measured.
  'ActiveRequestScreen': () => const ActiveRequestScreen(requestId: 'r1'),
  'MechanicActiveJobScreen': () => const MechanicActiveJobScreen(requestId: 'r1'),
  'MechanicProfileViewScreen': () =>
      const MechanicProfileViewScreen(name: 'Alexandra Villanueva-Reyes'),
  'JobChatScreen': () => const JobChatScreen(
        requestId: 'r1',
        otherPartyName: 'Alexandra Villanueva-Reyes',
      ),
};

/// How much the reader has enlarged text in their OS settings.
///
/// 1.0 is the default; 2.0 is what an accessibility setting can ask for and
/// what the app clamps down from. Sweeping at both is the point — a layout
/// that only works at 1.0 is not finished.
double readerTextScale = 1.0;

/// Wraps [child] exactly the way `main.dart`'s builder does, so what the sweep
/// measures is what the app actually renders.
Widget app(Size size, Widget child) {
  return MediaQuery(
    data: MediaQueryData(
      size: size,
      textScaler: TextScaler.linear(readerTextScale),
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
            // Some screens are meant to sit inside a shell and are not
            // Scaffolds themselves; this gives every one of them the Material
            // ancestor it would have in the app.
            home: Scaffold(body: child),
          ),
        ),
      );
    }),
  );
}

/// An overflow is reported as a FlutterError during paint. Anything else —
/// a missing plugin, a platform channel — is not a layout problem and is
/// counted separately so it cannot be mistaken for one.
bool isOverflow(Object e) =>
    e.toString().contains('overflowed by') ||
    e.toString().contains('RenderFlex overflowed') ||
    e.toString().contains('A RenderFlex overflowed');

/// The reader text scales to sweep at: normal, and the largest the app will
/// honour before clamping.
const readerScales = <String, double>{'text 1.0': 1.0, 'text 2.0': 2.0};

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  //  The layout model itself
  // ─────────────────────────────────────────────────────────────────────────

  group('AppLayout', () {
    test('sorts real devices into the right class', () {
      AppFormFactor of(Size s) => AppLayout.fromSize(s).formFactor;
      expect(of(const Size(320, 568)), AppFormFactor.smallPhone);
      expect(of(const Size(360, 640)), AppFormFactor.phone);
      expect(of(const Size(390, 844)), AppFormFactor.phone);
      expect(of(const Size(412, 915)), AppFormFactor.largePhone);
      expect(of(const Size(768, 1024)), AppFormFactor.tablet);
    });

    test('a rotated phone is still a phone, not a tablet', () {
      // 844 points wide is wider than an iPad's short side. Deciding on width
      // alone would hand a sideways phone a tablet layout.
      expect(AppLayout.fromSize(const Size(844, 390)).formFactor,
          AppFormFactor.phone);
      expect(AppLayout.fromSize(const Size(844, 390)).isTablet, isFalse);
      expect(AppLayout.fromSize(const Size(1112, 834)).isTablet, isTrue);
    });

    test('gutters grow with the device, and never vanish', () {
      double gutter(Size s) => AppLayout.fromSize(s).gutter;
      expect(gutter(const Size(320, 568)),
          lessThan(gutter(const Size(390, 844))));
      expect(gutter(const Size(390, 844)),
          lessThan(gutter(const Size(768, 1024))));
      for (final size in devices.values) {
        expect(AppLayout.fromSize(size).gutter, greaterThanOrEqualTo(12));
      }
    });

    test('content stops widening on a tablet and centres', () {
      final phone = AppLayout.fromSize(const Size(390, 844));
      expect(phone.contentMaxWidth, double.infinity);
      expect(phone.pageInsets.left, phone.gutter);

      final tablet = AppLayout.fromSize(const Size(834, 1112));
      expect(tablet.contentMaxWidth, lessThan(834));
      // What is left after both insets IS the reading measure, which is what
      // makes the content centred rather than merely padded.
      final content = 834 - tablet.pageInsets.left - tablet.pageInsets.right;
      expect(content, closeTo(tablet.contentMaxWidth, 0.01));
      expect(tablet.pageInsets.left, tablet.pageInsets.right);
    });

    test('scale is proportional between the clamps, and bounded outside them',
        () {
      final baseline = AppLayout.fromSize(const Size(AppLayout.baselineWidth, 800));
      // At the baseline a number is untouched — adopting the system changed
      // nothing on the phone the app was designed on.
      expect(baseline.scale(120), 120);

      expect(AppLayout.fromSize(const Size(320, 568)).scale(120),
          lessThan(120));
      expect(AppLayout.fromSize(const Size(834, 1112)).scale(120),
          greaterThan(120));

      // Never runaway in either direction.
      for (final size in devices.values) {
        final s = AppLayout.fromSize(size).scale(100);
        expect(s, inInclusiveRange(88, 130));
      }
    });

    test('a panel never eats the screen, however short the window', () {
      for (final size in devices.values) {
        final layout = AppLayout.fromSize(size);
        expect(layout.panelHeight(190), lessThanOrEqualTo(size.height * 0.34));
        expect(layout.panelHeight(190), greaterThan(0));
      }
      // The landscape phone is the case this exists for.
      final landscape = AppLayout.fromSize(const Size(844, 390));
      expect(landscape.panelHeight(190), lessThan(190));
    });

    test('reader text scaling is honoured, but bounded', () {
      final layout = AppLayout.fromSize(const Size(390, 844));

      final huge = layout.textScalerFrom(const TextScaler.linear(3.0));
      expect(huge.scale(10), lessThanOrEqualTo(10 * AppLayout.maxTextScale));

      final tiny = layout.textScalerFrom(const TextScaler.linear(0.2));
      expect(tiny.scale(10), greaterThanOrEqualTo(10 * AppLayout.minTextScale));

      // In between, the reader's own preference still moves the needle.
      final small = layout.textScalerFrom(const TextScaler.linear(0.9));
      final large = layout.textScalerFrom(const TextScaler.linear(1.2));
      expect(large.scale(10), greaterThan(small.scale(10)));
    });

    test('a tablet reads slightly larger than a phone at the same setting', () {
      const reader = TextScaler.linear(1.0);
      final phone = AppLayout.fromSize(const Size(390, 844)).textScalerFrom(reader);
      final tablet = AppLayout.fromSize(const Size(834, 1112)).textScalerFrom(reader);
      expect(tablet.scale(14), greaterThan(phone.scale(14)));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  Real widgets at real sizes
  // ─────────────────────────────────────────────────────────────────────────

  group('adapting, not stretching', () {
    testWidgets('auth buttons stop widening on a tablet', (tester) async {
      Future<double> buttonWidth(Size size) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(app(size, const WelcomeScreen()));
        await tester.pump(const Duration(milliseconds: 50));
        return tester.getSize(find.byType(AuthRoleButton).first).width;
      }

      addTearDown(tester.view.reset);

      final onPhone = await buttonWidth(const Size(390, 844));
      final onTablet = await buttonWidth(const Size(834, 1112));

      // Wider than a phone's, but nothing like the full width of the tablet —
      // a "Register as Client" button running the whole width of an iPad is
      // the thing this guards against.
      expect(onTablet, greaterThan(onPhone));
      expect(onTablet, lessThan(700));
    });

    testWidgets('the earnings header stacks on a small phone and not on a big one',
        (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1;

      Future<double> figureTop(Size size, int index) async {
        tester.view.physicalSize = size;
        await tester.pumpWidget(app(size, const EarningScreen()));
        await tester.pump(const Duration(milliseconds: 50));
        return tester.getTopLeft(find.text('Points')).dy;
      }

      // Stacked: "Points" sits below "Available Balance".
      final smallTop = await figureTop(const Size(320, 568), 1);
      final balanceTop =
          tester.getTopLeft(find.text('Available Balance')).dy;
      expect(smallTop, greaterThan(balanceTop));

      // Side by side: both labels share a line.
      await figureTop(const Size(430, 932), 1);
      expect(
        tester.getTopLeft(find.text('Points')).dy,
        closeTo(tester.getTopLeft(find.text('Available Balance')).dy, 1),
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  The sweep: every screen, every device, at both text sizes
  // ─────────────────────────────────────────────────────────────────────────

  final overflows = <String>[];
  final others = <String, String>{};

  for (final scaleEntry in readerScales.entries) {
  for (final screen in screens.entries) {
    for (final device in devices.entries) {
      testWidgets('${screen.key} @ ${device.key} ${scaleEntry.key}', (tester) async {
        readerTextScale = scaleEntry.value;
        addTearDown(() => readerTextScale = 1.0);
        tester.view.physicalSize = device.value;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        // Every error, not just the first. `takeException` hands back one
        // object however many were thrown, and an overflow behind an
        // unrelated plugin failure would go unseen.
        final caught = <String>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (details) => caught.add(details.toString());
        addTearDown(() => FlutterError.onError = previous);

        try {
          await tester.pumpWidget(app(device.value, screen.value()));
          await tester.pump(const Duration(milliseconds: 50));
        } catch (e) {
          caught.add(e.toString());
        }
        tester.takeException();

        for (final error in caught) {
          if (isOverflow(error)) {
            // Keep the measurement: "overflowed by 13 pixels on the right"
            // says both how bad and in which direction.
            final match = RegExp(r'overflowed by ([\d.]+) pixels on the (\w+)')
                .firstMatch(error);
            final detail = match == null
                ? ''
                : '  (${match.group(1)}px ${match.group(2)})';
            overflows.add(
                '${screen.key.padRight(30)} ${device.key}  ${scaleEntry.key}$detail');
          } else {
            others[screen.key] = error.split('\n').first;
          }
        }
      });
    }
  }
  }

  tearDownAll(() {
    if (others.isNotEmpty) {
      // Not a failure — a plugin that cannot run in a test is not a layout
      // problem — but worth printing, because a screen that threw before it
      // painted was never actually measured.
      // ignore: avoid_print
      print('Screens that raised a non-layout error: ${others.keys.join(', ')}');
    }
    if (overflows.isEmpty) return;
    fail('The layout overflows on ${overflows.length} '
        'screen/size combinations:\n${overflows.join('\n')}');
  });
}
