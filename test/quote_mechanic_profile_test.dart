import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_go/data/mechanic_account_store.dart';
import 'package:on_go/data/quote_store.dart';
import 'package:on_go/screens/auth/client_ui/home/quotes_screen.dart';
import 'package:on_go/screens/auth/client_ui/profile/mechanic_profile_view_screen.dart';

// The same wrapper the responsive suite uses, which mirrors main.dart's
// builder — so these sizes are measured the way the app actually renders.
import 'responsive_layout_test.dart' show app, readerTextScale;

/// Tapping a mechanic in the client's Quotes list opens that mechanic's
/// profile, and nothing else about the quote changes.
///
/// Two quotes from two different mechanics throughout, on purpose: with only
/// one, a row that opened the wrong mechanic — or always the first — would
/// still pass.

const _requestId = 'quote-profile-test';
const _ana = 'Ana Reyes';
const _ben = 'Ben Cruz';

const _sizes = <String, Size>{
  'small phone': Size(320, 568),
  'phone': Size(390, 844),
  'tablet': Size(834, 1112),
};

void _seedTwoQuotes() {
  final store = QuoteNotificationStore.instance;
  store.clear();

  // Quotes can only be sent by a mechanic allowed to act on jobs.
  MechanicAccountStore.instance.enterDemoMode();

  store.submitRequest(HelpRequest(
    id: _requestId,
    problem: 'Flat tire: Rear left, no spare',
    location: 'Puerto Princesa City',
    // Normal has no completion window, so no ETA is refused as too long.
    urgency: 'Normal',
    createdAt: DateTime.now(),
  ));
  store.mechanicSendQuote(
    _requestId,
    mechanicName: _ana,
    price: '₱450',
    eta: const Duration(minutes: 20),
    rating: 4.8,
  );
  store.mechanicSendQuote(
    _requestId,
    mechanicName: _ben,
    price: '₱380',
    eta: const Duration(minutes: 35),
    rating: 4.2,
  );
}

Future<void> _pumpQuotes(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app(size, const QuotesScreen(requestId: _requestId)));
  await tester.pumpAndSettle();
}

String _openProfileName(WidgetTester tester) =>
    tester.widget<MechanicProfileViewScreen>(find.byType(MechanicProfileViewScreen)).name;

/// Runs [pump] and returns every error Flutter reported while it ran.
///
/// The handler is put back before this returns, not in a tearDown. flutter_test
/// checks it at the end of the test body, so restoring it any later turns a
/// real overflow into an unrelated-looking harness assertion — which is exactly
/// what hid the first result of this file.
Future<List<String>> _collectErrors(Future<void> Function() pump) async {
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (d) => errors.add(d.toString());
  try {
    await pump();
  } finally {
    FlutterError.onError = previous;
  }
  return errors;
}

void main() {
  setUp(_seedTwoQuotes);
  tearDown(() {
    QuoteNotificationStore.instance.clear();
    MechanicAccountStore.instance.clear();
  });

  for (final entry in _sizes.entries) {
    group('on a ${entry.key}', () {
      testWidgets('tapping a mechanic opens that mechanic\'s profile', (tester) async {
        await _pumpQuotes(tester, entry.value);
        expect(find.byType(MechanicProfileViewScreen), findsNothing);

        await tester.tap(find.text(_ben));
        await tester.pumpAndSettle();
        expect(find.byType(MechanicProfileViewScreen), findsOneWidget);
        expect(_openProfileName(tester), _ben);

        // Back, then the OTHER mechanic — the row, not the list, decides.
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(MechanicProfileViewScreen), findsNothing);

        await tester.tap(find.text(_ana));
        await tester.pumpAndSettle();
        expect(_openProfileName(tester), _ana);
      });

      testWidgets('lays out with real quotes, without overflowing', (tester) async {
        final errors = await _collectErrors(() => _pumpQuotes(tester, entry.value));

        expect(errors.where((e) => e.contains('overflowed')), isEmpty);
        expect(find.text(_ana), findsOneWidget);
        expect(find.text(_ben), findsOneWidget);
      });
    });
  }

  group('the existing quote behaviour is unchanged', () {
    testWidgets('opening a profile accepts and rejects nothing', (tester) async {
      await _pumpQuotes(tester, const Size(390, 844));

      await tester.tap(find.text(_ben));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      final store = QuoteNotificationStore.instance;
      expect(store.requestFor(_requestId)!.status, RequestStatus.pending);
      final quotes = store.quotesForRequest(_requestId);
      expect(quotes, hasLength(2));
      expect(quotes.any((q) => q.accepted), isFalse);
      // Both decisions are still on offer for both mechanics.
      expect(find.text('Accept'), findsNWidgets(2));
      expect(find.text('Reject'), findsNWidgets(2));
    });

    testWidgets('Accept still accepts the quote in its own row', (tester) async {
      await _pumpQuotes(tester, const Size(390, 844));

      // Accept buttons follow the row order the store returns.
      final quotes = QuoteNotificationStore.instance.quotesForRequest(_requestId);
      final benIndex = quotes.indexWhere((q) => q.mechanicName == _ben);

      await tester.tap(find.text('Accept').at(benIndex));
      await tester.pumpAndSettle();

      final store = QuoteNotificationStore.instance;
      expect(store.requestFor(_requestId)!.status, RequestStatus.matched);
      expect(store.acceptedQuoteFor(_requestId)!.mechanicName, _ben);
      // Matched requests leave this pending-only screen, as before.
      expect(find.text(_ben), findsNothing);
      expect(find.byType(MechanicProfileViewScreen), findsNothing);
    });

    testWidgets('the larger tap target does not make the row taller', (tester) async {
      await _pumpQuotes(tester, const Size(390, 844));

      // Everything in the row sits inside this Row; its height is set by the
      // tallest cell, which must still be the Accept/Reject column.
      final row = find.ancestor(of: find.text(_ben), matching: find.byType(Row)).first;
      final link = find.ancestor(of: find.text(_ben), matching: find.byType(InkWell)).first;
      final decisions = find
          .ancestor(of: find.text('Accept').first, matching: find.byType(Column))
          .first;

      expect(tester.getSize(link).height, lessThan(tester.getSize(decisions).height));
      expect(tester.getSize(row).height, tester.getSize(decisions).height);
    });

    testWidgets('screen readers announce the name as a way into the profile', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpQuotes(tester, const Size(390, 844));

      expect(find.bySemanticsLabel("View $_ben's profile"), findsOneWidget);
      expect(find.bySemanticsLabel("View $_ana's profile"), findsOneWidget);
      handle.dispose();
    });

    testWidgets('holds up at the largest text size on a small phone', (tester) async {
      // app() builds its MediaQuery from this, so it has to be set here —
      // wrapping app() in an outer MediaQuery would be silently overridden
      // and the test would pass at 1.0 without ever trying 2.0.
      readerTextScale = 2.0;
      addTearDown(() => readerTextScale = 1.0);

      final errors = await _collectErrors(() => _pumpQuotes(tester, const Size(320, 568)));
      // Prove the scale really reached the screen, rather than trusting it.
      final scaler = MediaQuery.textScalerOf(tester.element(find.text(_ben)));
      expect(scaler.scale(10), greaterThan(10));

      expect(errors.where((e) => e.contains('overflowed')), isEmpty);

      await tester.tap(find.text(_ben));
      await tester.pumpAndSettle();
      expect(_openProfileName(tester), _ben);
    });
  });
}
