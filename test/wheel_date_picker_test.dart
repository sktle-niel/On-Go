import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_go/theme/app_theme.dart';
import 'package:on_go/widgets/wheel_date_picker.dart';

/// The registration date picker.
///
/// Kept apart from the login tests on purpose. It imports nothing but the
/// theme, so it still compiles and runs while the auth screens are mid-change,
/// and a failure in one file cannot hide the results of the other.

Widget _app(Size size, Widget home, {double textScale = 1}) {
  return MediaQuery(
    data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
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

/// Runs [body], returning every error Flutter reported while it ran, with the
/// handler restored before returning.
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

DateTime? _picked;
bool _closed = false;

/// The last day a picker in these tests will allow — a fixed "today", so no
/// result depends on when the tests run.
final _today = DateTime(2026, 9, 15);

Future<void> _openPicker(
  WidgetTester tester, {
  required DateTime initial,
  DateTime? first,
  DateTime? last,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  _picked = null;
  _closed = false;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_app(
    size,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              _picked = await showWheelDatePicker(
                context: context,
                initialDate: initial,
                firstDate: first ?? DateTime(1900),
                lastDate: last ?? _today,
                title: 'Select Date of Birth',
              );
              _closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
    textScale: textScale,
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _tapRow(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first, warnIfMissed: false);
  await tester.pumpAndSettle();
}

Future<void> _set(WidgetTester tester) async {
  await tester.tap(find.text('SET'));
  await tester.pumpAndSettle();
}

Finder _wheel(String name) => find.byKey(ValueKey('wheel-$name'));

double _itemExtent(WidgetTester tester) => tester
    .widget<ListWheelScrollView>(
        find.descendant(of: _wheel('day'), matching: find.byType(ListWheelScrollView)))
    .itemExtent;

void main() {
  group('the wheel date picker', () {
    testWidgets('opens on the initial date, laid out as in the reference', (tester) async {
      final handle = tester.ensureSemantics();
      await _openPicker(tester, initial: DateTime(2000, 3, 1));

      expect(find.text('Select Date of Birth'), findsOneWidget);
      expect(find.text('CANCEL'), findsOneWidget);
      expect(find.text('SET'), findsOneWidget);

      // Month, day, year — left to right, level with each other.
      final month = tester.getCenter(find.text('Mar'));
      final day = tester.getCenter(find.text('01'));
      final year = tester.getCenter(find.text('2000'));
      expect(month.dx, lessThan(day.dx));
      expect(day.dx, lessThan(year.dx));
      expect(month.dy, closeTo(day.dy, 1));
      expect(day.dy, closeTo(year.dy, 1));

      // The neighbours from the reference, above and below the selection.
      // "31" above "01" is the day wheel wrapping round, as in the screenshot.
      for (final (above, below, selected) in [
        ('Feb', 'Apr', 'Mar'),
        ('31', '02', '01'),
        ('1999', '2001', '2000'),
      ]) {
        final centre = tester.getCenter(find.text(selected)).dy;
        expect(tester.getCenter(find.text(above).first).dy, lessThan(centre), reason: above);
        expect(tester.getCenter(find.text(below).first).dy, greaterThan(centre), reason: below);
      }

      // Selected row bold and full strength; its neighbours plain and dimmed.
      final selectedStyle = tester.widget<Text>(find.text('Mar')).style!;
      final neighbourStyle = tester.widget<Text>(find.text('Feb').first).style!;
      expect(selectedStyle.fontWeight, FontWeight.w700);
      expect(neighbourStyle.fontWeight, FontWeight.w400);
      expect(neighbourStyle.color!.a, lessThan(selectedStyle.color!.a));

      // Screen readers get each wheel as one adjustable control.
      expect(
        tester.getSemantics(_wheel('month')),
        isSemantics(
          label: 'Month',
          value: 'March',
          increasedValue: 'April',
          decreasedValue: 'February',
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('SET returns the date on screen; CANCEL returns nothing', (tester) async {
      await _openPicker(tester, initial: DateTime(2000, 3, 1));
      await _set(tester);
      expect(_closed, isTrue);
      expect(_picked, DateTime(2000, 3, 1));

      await _openPicker(tester, initial: DateTime(2000, 3, 1));
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(_closed, isTrue);
      expect(_picked, isNull);
    });

    testWidgets('tapping the row above or below steps to it', (tester) async {
      await _openPicker(tester, initial: DateTime(2000, 3, 1));
      await _tapRow(tester, 'Apr');
      await _tapRow(tester, '2001');
      // April has 30 days, so the row above the 1st is the 30th — there is no
      // "31" on this wheel any more.
      expect(find.text('31'), findsNothing);
      await _tapRow(tester, '30');
      await _set(tester);
      // Months and days are independent wheels: stepping the day back past the
      // 1st lands on the last day of the SAME month, not of the one before.
      expect(_picked, DateTime(2001, 4, 30));
    });

    testWidgets('dragging a wheel moves it by whole rows', (tester) async {
      await _openPicker(tester, initial: DateTime(2000, 3, 1));
      final extent = _itemExtent(tester);

      // Moved slowly and released at rest, so the wheel settles on the row
      // under it rather than flinging on.
      final gesture = await tester.startGesture(tester.getCenter(_wheel('day')));
      const steps = 20;
      final distance = -(2 * extent) - kTouchSlop;
      for (var i = 0; i < steps; i++) {
        await gesture.moveBy(Offset(0, distance / steps));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();

      await _set(tester);
      expect(_picked, DateTime(2000, 3, 3));
    });

    testWidgets('the day wheel follows the month and the leap year', (tester) async {
      await _openPicker(tester, initial: DateTime(2000, 3, 31));
      await _tapRow(tester, 'Feb');
      expect(find.text('30'), findsNothing);
      expect(find.text('31'), findsNothing);
      await _set(tester);
      expect(_picked, DateTime(2000, 2, 29), reason: '2000 is a leap year');

      await _openPicker(tester, initial: DateTime(2001, 3, 31));
      await _tapRow(tester, 'Feb');
      await _set(tester);
      expect(_picked, DateTime(2001, 2, 28));

      await _openPicker(tester, initial: DateTime(2000, 2, 29));
      await _tapRow(tester, '2001');
      await _set(tester);
      expect(_picked, DateTime(2001, 2, 28), reason: 'the 29th does not survive leaving a leap year');
    });

    testWidgets('months wrap round; years do not', (tester) async {
      await _openPicker(tester, initial: DateTime(2000, 12, 15));
      expect(tester.getCenter(find.text('Jan').first).dy,
          greaterThan(tester.getCenter(find.text('Dec')).dy));
      await _tapRow(tester, 'Jan');
      await _set(tester);
      expect(_picked, DateTime(2000, 1, 15), reason: 'wrapping the month does not change the year');

      await _openPicker(tester, initial: DateTime(1900, 1, 1));
      expect(find.text('1899'), findsNothing);
      expect(find.text('1901'), findsOneWidget);
    });

    testWidgets('never offers a date outside the range', (tester) async {
      // On the last allowed day, the wheels stop at September and the 15th —
      // and still wrap within what is left.
      await _openPicker(tester, initial: _today);
      expect(find.text('Oct'), findsNothing);
      expect(find.text('16'), findsNothing);
      expect(tester.getCenter(find.text('Jan').first).dy,
          greaterThan(tester.getCenter(find.text('Sep')).dy));
      expect(find.text('2027'), findsNothing);
      await _set(tester);
      expect(_picked, _today);

      // Moving into the last year pulls a later month and day back inside it.
      await _openPicker(tester, initial: DateTime(2025, 12, 31));
      await _tapRow(tester, '2026');
      await _set(tester);
      expect(_picked, _today);

      // An initial date past the end opens on the end.
      await _openPicker(tester, initial: DateTime(2030, 1, 1));
      await _set(tester);
      expect(_picked, _today);
    });

    testWidgets('a screen reader can adjust each wheel', (tester) async {
      final handle = tester.ensureSemantics();
      await _openPicker(tester, initial: DateTime(2000, 3, 1));

      tester.semantics.performAction(find.semantics.byLabel('Month'), SemanticsAction.increase);
      await tester.pumpAndSettle();
      tester.semantics.performAction(find.semantics.byLabel('Year'), SemanticsAction.decrease);
      await tester.pumpAndSettle();

      await _set(tester);
      expect(_picked, DateTime(1999, 4, 1));
      handle.dispose();
    });

    for (final device in _devices.entries) {
      testWidgets('fits and works @ ${device.key}', (tester) async {
        final errors = await _collectErrors(
          () => _openPicker(tester, initial: DateTime(2000, 3, 1), size: device.value),
        );
        expect(_overflows(errors), isEmpty);

        // The dialog's surface. `Dialog` itself fills the whole route — its
        // inset padding is part of its box — so measuring it would compare the
        // screen with the screen and pass at every size.
        final dialog = tester.getRect(
          find.descendant(of: find.byType(Dialog), matching: find.byType(Material)).first,
        );
        expect(dialog.left, greaterThanOrEqualTo(0));
        expect(dialog.right, lessThanOrEqualTo(device.value.width));
        expect(dialog.top, greaterThanOrEqualTo(0));
        expect(dialog.bottom, lessThanOrEqualTo(device.value.height));
        // A picker, not a panel: it does not stretch across a tablet.
        expect(dialog.width, lessThanOrEqualTo(400));
        // ignore: avoid_print
        print('DIALOG ${device.key}: ${dialog.width.toStringAsFixed(0)} x ${dialog.height.toStringAsFixed(0)}');

        for (final label in ['Mar', '01', '2000', 'SET']) {
          expect(find.text(label).hitTestable(), findsOneWidget, reason: label);
        }
      });
    }

    for (final size in const [Size(320, 568), Size(844, 390)]) {
      testWidgets('fits at the largest text size @ ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        final errors = await _collectErrors(
          () => _openPicker(tester, initial: DateTime(2000, 3, 1), size: size, textScale: 2.0),
        );
        expect(_overflows(errors), isEmpty);

        // On a phone on its side at this size the dialog may need to scroll;
        // SET must still be reachable, and still work.
        final dialogScroll = find
            .descendant(of: find.byType(Dialog), matching: find.byType(Scrollable))
            .first;
        await tester.scrollUntilVisible(find.text('SET'), 40, scrollable: dialogScroll);
        await _set(tester);
        expect(_picked, DateTime(2000, 3, 1));
      });
    }
  });
}
