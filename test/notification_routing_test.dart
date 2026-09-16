import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_go/data/app_session.dart';
import 'package:on_go/data/mechanic_account_store.dart';
import 'package:on_go/data/mechanic_notification_store.dart';
import 'package:on_go/data/quote_store.dart';
import 'package:on_go/screens/auth/client_ui/active/active_request_screen.dart';
import 'package:on_go/screens/auth/client_ui/home/quotes_screen.dart';
import 'package:on_go/screens/auth/client_ui/notifications/client_notifications_screen.dart';
import 'package:on_go/screens/auth/mechanic_ui/mechanic_home_screen.dart';
import 'package:on_go/theme/app_theme.dart';

import 'responsive_layout_test.dart' show app;

const _ana = 'Ana Reyes';
const _ben = 'Ben Cruz';

const _sizes = <String, Size>{
  'phone': Size(390, 844),
  'tablet': Size(834, 1112),
};

HelpRequest _request(String id, {String urgency = 'Normal', String client = 'Client'}) =>
    HelpRequest(
      id: id,
      problem: 'Flat tire: Rear left, no spare',
      location: 'Puerto Princesa City',
      urgency: urgency,
      createdAt: DateTime.now(),
      clientName: client,
    );

QuoteNotificationStore get _store => QuoteNotificationStore.instance;

/// One job with a quote from each of two mechanics — so a notification that
/// opened the wrong quote, or always the first, cannot pass.
void _seedTwoQuotes(String requestId) {
  _store.submitRequest(_request(requestId));
  _store.mechanicSendQuote(requestId,
      mechanicName: _ana, price: '₱450', eta: const Duration(minutes: 20), rating: 4.8);
  _store.mechanicSendQuote(requestId,
      mechanicName: _ben, price: '₱380', eta: const Duration(minutes: 35), rating: 4.2);
}

ClientNotification _quoteNotificationFrom(String mechanic) => _store.clientNotifications
    .firstWhere((n) => n.kind == ClientNotificationKind.quoteReceived && n.mechanicName == mechanic);

MechanicNotification _mechanicNote(MechanicNotificationKind kind, {String? requestId}) =>
    MechanicNotification(
      id: 'n-$kind',
      kind: kind,
      mechanicName: QuoteNotificationStore.currentMechanicName,
      clientName: 'Client',
      detail: '',
      createdAt: DateTime.now(),
      requestId: requestId,
    );

Future<void> _pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app(size, child));
  await tester.pumpAndSettle();
}

/// The mechanic shell, pumped without waiting to settle: its Emergency pill
/// pulses for as long as unviewed emergencies are waiting, which is an
/// animation with no end.
Future<void> _pumpShell(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app(size, const MechanicHomeScreen()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// The shell builds every tab, including ones that reach for device plugins
/// no test host has. Those are not what these tests are about, so they are
/// set aside — anything else still fails the test.
void _ignorePluginErrors() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    final e = details.exception;
    if (e is MissingPluginException || e is PlatformException) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

void main() {
  setUp(() {
    QuoteNotificationStore.instance.clear();
    MechanicNotificationStore.instance.clear();
    MechanicAccountStore.instance.enterDemoMode();
    AppSession.instance.setRole(AppRole.client, viewerName: 'Client');
  });

  // ---------------------------------------------------------------------
  // What each notification carries
  // ---------------------------------------------------------------------

  group('notifications carry what they refer to', () {
    test('a quote notification names its job, its mechanic and its exact quote', () {
      _seedTwoQuotes('r1');
      final fromBen = _quoteNotificationFrom(_ben);
      final bensQuote = _store.quotesForRequest('r1').firstWhere((q) => q.mechanicName == _ben);

      expect(fromBen.kind, ClientNotificationKind.quoteReceived);
      expect(fromBen.requestId, 'r1');
      expect(fromBen.mechanicName, _ben);
      expect(fromBen.quoteId, bensQuote.id);
    });

    test('an emergency alert names its job', () {
      _store.submitRequest(_request('e1', urgency: 'Emergency'));
      final alert = MechanicNotificationStore.instance
          .notificationsFor(QuoteNotificationStore.currentMechanicName)
          .single;
      expect(alert.kind, MechanicNotificationKind.emergencyPosted);
      expect(alert.requestId, 'e1');
    });

    test('accepted and rejected quote notifications name their quote', () {
      _seedTwoQuotes('r1');
      final anasQuote = _store.quotesForRequest('r1').firstWhere((q) => q.mechanicName == _ana);
      final bensQuote = _store.quotesForRequest('r1').firstWhere((q) => q.mechanicName == _ben);
      _store.clientRejectQuote(bensQuote.id);
      _store.clientAcceptQuote(anasQuote.id);

      final accepted = MechanicNotificationStore.instance
          .notificationsFor(_ana)
          .firstWhere((n) => n.kind == MechanicNotificationKind.quoteAccepted);
      final rejected = MechanicNotificationStore.instance
          .notificationsFor(_ben)
          .firstWhere((n) => n.kind == MechanicNotificationKind.quoteRejected);
      expect(accepted.quoteId, anasQuote.id);
      expect(rejected.quoteId, bensQuote.id);
    });
  });

  // ---------------------------------------------------------------------
  // Client routing
  // ---------------------------------------------------------------------

  group('client routing', () {
    test('a quote opens that job\'s quotes with that exact quote selected', () {
      _seedTwoQuotes('r1');
      for (final mechanic in [_ana, _ben]) {
        final route = _store.routeForClientNotification(_quoteNotificationFrom(mechanic));
        final quote = _store.quotesForRequest('r1').firstWhere((q) => q.mechanicName == mechanic);
        expect(route, isA<OpenJobQuotes>());
        expect((route as OpenJobQuotes).requestId, 'r1');
        expect(route.quoteId, quote.id, reason: 'the $mechanic notification opened the wrong quote');
      }
    });

    test('a quote for a completed job is not opened', () {
      _seedTwoQuotes('r1');
      final note = _quoteNotificationFrom(_ana);
      _store.requestFor('r1')!.status = RequestStatus.completed;

      final route = _store.routeForClientNotification(note);
      expect(route, isA<NotificationUnavailable>());
      expect((route as NotificationUnavailable).message,
          'This quote is no longer available because the job has been completed.');
      // The notification itself is kept.
      expect(_store.clientNotifications, contains(note));
    });

    test('the accepted quote opens the job; the passed-over one explains', () {
      _seedTwoQuotes('r1');
      final anasQuote = _store.quotesForRequest('r1').firstWhere((q) => q.mechanicName == _ana);
      final fromAna = _quoteNotificationFrom(_ana);
      final fromBen = _quoteNotificationFrom(_ben);
      _store.clientAcceptQuote(anasQuote.id);

      expect(_store.routeForClientNotification(fromAna), isA<OpenClientJob>());
      final other = _store.routeForClientNotification(fromBen);
      expect(other, isA<NotificationUnavailable>());
      expect((other as NotificationUnavailable).message, contains('another mechanic'));
    });

    test('a deleted job does not break — it explains', () {
      _seedTwoQuotes('r1');
      final note = _quoteNotificationFrom(_ana);
      _store.clientDeleteRequest('r1');

      final route = _store.routeForClientNotification(note);
      expect(route, isA<NotificationUnavailable>());
      expect((route as NotificationUnavailable).message, 'This job no longer exists.');
    });

    test('progress notifications follow the job to where it is now', () {
      _store.submitRequest(_request('e1', urgency: 'Emergency'));
      _store.mechanicAcceptEmergency('e1',
          mechanicName: _ana, eta: const Duration(minutes: 15), rating: 4.8);
      final accepted = _store.clientNotifications
          .firstWhere((n) => n.kind == ClientNotificationKind.jobAccepted);

      expect(_store.routeForClientNotification(accepted), isA<OpenClientJob>());

      _store.requestFor('e1')!.status = RequestStatus.completed;
      final done = _store.routeForClientNotification(accepted);
      expect(done, isA<NotificationUnavailable>());
      expect((done as NotificationUnavailable).message, contains('completed'));
    });

    test('routing a notification does not change its read state', () {
      _seedTwoQuotes('r1');
      final before = _store.clientUnreadNotificationCount;
      _store.routeForClientNotification(_quoteNotificationFrom(_ana));
      expect(_store.clientUnreadNotificationCount, before);
    });
  });

  // ---------------------------------------------------------------------
  // Mechanic routing
  // ---------------------------------------------------------------------

  group('mechanic routing', () {
    String me() => QuoteNotificationStore.currentMechanicName;

    MechanicNotification alertFor(String requestId) => MechanicNotificationStore.instance
        .notificationsFor(me())
        .firstWhere((n) => n.requestId == requestId);

    test('an open emergency opens that emergency on the Emergency list', () {
      _store.submitRequest(_request('e1', urgency: 'Emergency'));
      _store.submitRequest(_request('e2', urgency: 'Emergency'));

      final route = _store.routeForMechanicNotification(alertFor('e2'), me());
      expect(route, isA<OpenJobInList>());
      expect((route as OpenJobInList).requestId, 'e2');
      expect(route.emergency, isTrue);
    });

    test('an emergency this mechanic accepted opens their active job', () {
      _store.submitRequest(_request('e1', urgency: 'Emergency'));
      final alert = alertFor('e1');
      _store.mechanicAcceptEmergency('e1', mechanicName: me(), eta: const Duration(minutes: 15), rating: 4.5);

      final route = _store.routeForMechanicNotification(alert, me());
      expect(route, isA<OpenMechanicJob>());
      expect((route as OpenMechanicJob).requestId, 'e1');
    });

    test('an emergency someone else took, or that is gone, explains', () {
      _store.submitRequest(_request('e1', urgency: 'Emergency'));
      _store.submitRequest(_request('e2', urgency: 'Emergency'));
      final taken = alertFor('e1');
      final gone = alertFor('e2');

      _store.mechanicAcceptEmergency('e1', mechanicName: _ana, eta: const Duration(minutes: 15), rating: 4.8);
      _store.clientDeleteRequest('e2');

      final takenRoute = _store.routeForMechanicNotification(taken, me());
      expect((takenRoute as NotificationUnavailable).message,
          'Another mechanic has already accepted this emergency job.');
      final goneRoute = _store.routeForMechanicNotification(gone, me());
      expect((goneRoute as NotificationUnavailable).message, contains('no longer available'));
    });

    test('an accepted quote opens the job, until it is no longer theirs', () {
      _store.submitRequest(_request('r1'));
      _store.mechanicSendQuote('r1', mechanicName: me(), price: '₱400', eta: const Duration(minutes: 20), rating: 4.5);
      _store.clientAcceptQuote(_store.quotesForRequest('r1').single.id);
      final accepted = MechanicNotificationStore.instance
          .notificationsFor(me())
          .firstWhere((n) => n.kind == MechanicNotificationKind.quoteAccepted);

      expect(_store.routeForMechanicNotification(accepted, me()), isA<OpenMechanicJob>());

      AppSession.instance.setRole(AppRole.mechanic, viewerName: me());
      _store.mechanicCancelJob('r1', 'Van broke down');
      final route = _store.routeForMechanicNotification(accepted, me());
      expect((route as NotificationUnavailable).message, 'This job is no longer assigned to you.');
    });

    test('notifications about the mechanic open their tab', () {
      expect(
        (_store.routeForMechanicNotification(_mechanicNote(MechanicNotificationKind.paymentReceived), me())
                as OpenMechanicTab)
            .tab,
        MechanicHomeTab.earning,
      );
      expect(
        (_store.routeForMechanicNotification(_mechanicNote(MechanicNotificationKind.rated), me())
                as OpenMechanicTab)
            .tab,
        MechanicHomeTab.profile,
      );
      expect(
        (_store.routeForMechanicNotification(_mechanicNote(MechanicNotificationKind.accountApproved), me())
                as OpenMechanicTab)
            .tab,
        MechanicHomeTab.jobs,
      );
    });
  });

  // ---------------------------------------------------------------------
  // On screen, phone and tablet
  // ---------------------------------------------------------------------

  for (final entry in _sizes.entries) {
    group('on a ${entry.key}', () {
      final size = entry.value;

      testWidgets('tapping a quote notification opens that quote, highlighted', (tester) async {
        _seedTwoQuotes('r1');
        await _pumpAt(tester, size, const ClientNotificationsScreen());

        await tester.tap(find.text('$_ben sent you a quote.'));
        await tester.pumpAndSettle();

        expect(find.byType(QuotesScreen), findsOneWidget);

        Finder tintedAncestorOf(String name) => find.ancestor(
              of: find.text(name),
              matching: find.byWidgetPredicate((w) =>
                  w is DecoratedBox &&
                  w.decoration is BoxDecoration &&
                  (w.decoration as BoxDecoration).color != null),
            );
        expect(tintedAncestorOf(_ben), findsOneWidget, reason: "Ben's quote should be highlighted");
        expect(tintedAncestorOf(_ana), findsNothing, reason: "Ana's quote should not be");

        final row = tester.getRect(find.text(_ben));
        expect(row.bottom, lessThanOrEqualTo(size.height));
      });

      testWidgets('a quote for a completed job explains and stays put', (tester) async {
        _seedTwoQuotes('r1');
        _store.requestFor('r1')!.status = RequestStatus.completed;
        await _pumpAt(tester, size, const ClientNotificationsScreen());

        await tester.tap(find.text('$_ana sent you a quote.'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(QuotesScreen), findsNothing);
        expect(find.text('This quote is no longer available because the job has been completed.'),
            findsOneWidget);
        // Still listed.
        expect(find.text('$_ana sent you a quote.'), findsOneWidget);
      });

      testWidgets('tapping an accepted quote opens the job in progress', (tester) async {
        _seedTwoQuotes('r1');
        final anasQuote = _store.quotesForRequest('r1').firstWhere((q) => q.mechanicName == _ana);
        _store.clientAcceptQuote(anasQuote.id);
        await _pumpAt(tester, size, const ClientNotificationsScreen());

        await tester.tap(find.text('$_ana sent you a quote.'));
        // The job screen ticks every second, so it never "settles".
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(ActiveRequestScreen), findsOneWidget);
      });

      testWidgets('tapping an emergency alert opens that emergency job', (tester) async {
        _ignorePluginErrors();

        // Enough emergencies that the one we want is well below the fold.
        const clients = ['Carla', 'Dino', 'Elsa', 'Fidel', 'Gina', 'Hugo'];
        for (var i = 0; i < clients.length; i++) {
          _store.submitRequest(_request('e$i', urgency: 'Emergency', client: clients[i]));
        }
        final target = clients.last;

        await _pumpShell(tester, size);
        final me = QuoteNotificationStore.currentMechanicName;
        expect(MechanicNotificationStore.instance.unreadCountFor(me), clients.length);
        expect(_store.hasUnseenEmergencyJobs, isTrue);

        await tester.tap(find.byType(NotificationBell));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(MechanicNotificationStore.instance.unreadCountFor(me), 0);

        await tester.tap(find.text('$target posted an emergency job near you.'));
        // Landing on the Emergency list counts as viewing it, which is what
        // stops the pulse — so from here the screen can, and must, settle.
        await tester.pumpAndSettle();
        expect(_store.hasUnseenEmergencyJobs, isFalse);

        // Back in the shell, on the job itself.
        expect(find.text('$target posted an emergency job near you.'), findsNothing);
        final card = find.text(target);
        expect(card, findsOneWidget);
        final rect = tester.getRect(card);
        expect(rect.top, greaterThanOrEqualTo(0), reason: 'the emergency job was not scrolled into view');
        expect(rect.bottom, lessThanOrEqualTo(size.height), reason: 'the emergency job was not scrolled into view');

        bool outlined(String client) {
          final spot = tester.widget<AnimatedContainer>(find
              .ancestor(
                of: find.text(client),
                matching: find.byWidgetPredicate(
                    (w) => w is AnimatedContainer && w.foregroundDecoration is BoxDecoration),
              )
              .first);
          final border = (spot.foregroundDecoration as BoxDecoration).border as Border;
          return border.top.color.a > 0.5;
        }

        expect(outlined(target), isTrue, reason: 'the opened emergency should be outlined');
        // And only that one — checked across every card currently built, since
        // the list builds lazily and the first cards are scrolled out of it.
        final lit = tester
            .widgetList<AnimatedContainer>(find.byWidgetPredicate((w) =>
                w is AnimatedContainer &&
                w.foregroundDecoration is BoxDecoration &&
                (w.foregroundDecoration as BoxDecoration).border is Border))
            .where((c) =>
                ((c.foregroundDecoration as BoxDecoration).border as Border).top.color.a > 0.5);
        expect(lit, hasLength(1), reason: 'only the opened emergency should be outlined');

        // Read state is untouched by following the notification.
        expect(MechanicNotificationStore.instance.unreadCountFor(me), 0);

        // The outline is a pointer, not a state — it goes after a few seconds.
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        expect(outlined(target), isFalse);
      });

      testWidgets('an emergency someone else took explains and stays on the list', (tester) async {
        _ignorePluginErrors();
        _store.submitRequest(_request('e1', urgency: 'Emergency', client: 'Carla'));
        _store.mechanicAcceptEmergency('e1', mechanicName: _ana, eta: const Duration(minutes: 15), rating: 4.8);

        await _pumpAt(tester, size, const MechanicHomeScreen());
        await tester.tap(find.byType(NotificationBell));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Carla posted an emergency job near you.'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Another mechanic has already accepted this emergency job.'), findsOneWidget);
        expect(find.text('Carla posted an emergency job near you.'), findsOneWidget);
      });
    });
  }
}
