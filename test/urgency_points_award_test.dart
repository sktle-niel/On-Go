import 'package:flutter_test/flutter_test.dart';
import 'package:on_go/data/app_session.dart';
import 'package:on_go/data/mechanic_account_store.dart';
import 'package:on_go/data/mechanic_notification_store.dart';
import 'package:on_go/data/points_policy_store.dart';
import 'package:on_go/data/points_wallet_store.dart';
import 'package:on_go/data/quote_store.dart';
import 'package:on_go/data/urgency_policy_store.dart';
import 'package:on_go_shared/on_go_shared.dart';

import 'performance_test_support.dart';

QuoteNotificationStore get _store => QuoteNotificationStore.instance;

/// Takes one job of [urgency] from upload to payment, the way the two apps
/// drive the store, and returns it.
HelpRequest _paidJob(String urgency) {
  final id = 'award-$urgency';
  AppSession.instance.setRole(AppRole.client, viewerName: 'Client');
  _store.submitRequest(HelpRequest(
    id: id,
    problem: 'Flat tire',
    location: 'Puerto Princesa City',
    urgency: urgency,
    createdAt: DateTime.now(),
    clientName: 'Client',
    surcharge: additionalChargeFor(urgency),
  ));
  _store.mechanicSendQuote(
    id,
    mechanicName: QuoteNotificationStore.currentMechanicName,
    price: '₱450',
    eta: const Duration(hours: 1),
    rating: 4.8,
  );
  _store.clientAcceptQuote(_store.quotesForRequest(id).first.id);

  AppSession.instance.setRole(AppRole.mechanic, viewerName: QuoteNotificationStore.currentMechanicName);
  _store.mechanicCompleteService(id);

  AppSession.instance.setRole(AppRole.client, viewerName: 'Client');
  _store.clientConfirmPayment(id);
  return _store.requestFor(id)!;
}

void main() {
  setUp(() {
    _store.clear();
    resetPerformanceStores();
    MechanicNotificationStore.instance.clear();
    MechanicAccountStore.instance.enterDemoMode();
  });

  tearDown(() {
    PointsPolicyStore.instance.debugSet(PointsPolicy.defaults);
    UrgencyPolicyStore.instance.debugSet(UrgencyPolicy.defaults);
  });

  for (final (urgency, points, charge) in const [('Normal', 1.0, 10.0), ('Urgent', 3.0, 50.0), ('Emergency', 5.0, 100.0)]) {
    test('$urgency: client and mechanic both earn $points pts; the charge is ₱$charge', () {
      final wallet = PointsWalletStore.instance;
      final mechanic = QuoteNotificationStore.currentMechanicName;
      final clientBefore = wallet.balanceFor('Client');
      final mechanicBefore = wallet.balanceFor(mechanic);

      final job = urgency == 'Emergency' ? _paidEmergency() : _paidJob(urgency);

      expect(job.paymentCompleted, isTrue);
      expect(job.pointsAwarded, points);
      expect(wallet.balanceFor('Client') - clientBefore, points);
      expect(wallet.balanceFor(mechanic) - mechanicBefore, points);
      expect(job.platformFeeCharged, charge);
    });
  }

  test("the admin's points apply to both sides, whatever the payout", () {
    PointsPolicyStore.instance.debugSet(PointsPolicy.defaults.withPoints('Urgent', 8));
    final wallet = PointsWalletStore.instance;
    final mechanic = QuoteNotificationStore.currentMechanicName;
    final mechanicBefore = wallet.balanceFor(mechanic);

    final job = _paidJob('Urgent');

    expect(job.pointsAwarded, 8, reason: 'not a per-peso rate on the ₱450 payout');
    expect(wallet.balanceFor(mechanic) - mechanicBefore, 8);
  });
}

/// Emergency skips quoting: the mechanic claims the job and sets the agreed
/// price in person.
HelpRequest _paidEmergency() {
  const id = 'award-Emergency';
  final mechanic = QuoteNotificationStore.currentMechanicName;
  AppSession.instance.setRole(AppRole.client, viewerName: 'Client');
  _store.submitRequest(HelpRequest(
    id: id,
    problem: 'Engine will not start',
    location: 'Puerto Princesa City',
    urgency: 'Emergency',
    createdAt: DateTime.now(),
    clientName: 'Client',
    surcharge: additionalChargeFor('Emergency'),
  ));

  AppSession.instance.setRole(AppRole.mechanic, viewerName: mechanic);
  _store.mechanicAcceptEmergency(
    id,
    mechanicName: mechanic,
    eta: const Duration(hours: 1),
    rating: 4.8,
  );
  _store.mechanicSetPaymentAmount(id, 800);
  _store.mechanicCompleteService(id);

  AppSession.instance.setRole(AppRole.client, viewerName: 'Client');
  _store.clientConfirmPayment(id);
  return _store.requestFor(id)!;
}
