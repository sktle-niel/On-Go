import 'package:flutter_test/flutter_test.dart';
import 'package:on_go/data/quote_store.dart';
import 'package:on_go/data/urgency_policy_store.dart';
import 'package:on_go_shared/on_go_shared.dart';

HelpRequest _job(String urgency, {DateTime? matchedAt}) => HelpRequest(
      id: 'job-$urgency',
      problem: 'Flat tire',
      location: 'Puerto Princesa City',
      urgency: urgency,
      photoPaths: const [],
      createdAt: DateTime(2026, 9, 15, 8),
      status: matchedAt == null ? RequestStatus.pending : RequestStatus.matched,
      matchedAt: matchedAt,
    );

void main() {
  tearDown(() => UrgencyPolicyStore.instance.debugSet(UrgencyPolicy.defaults));

  group('the settings themselves', () {
    test('defaults: 1 / 3 / 5 points, ₱10 / ₱50 / ₱100, none / 3 days / 12 hours', () {
      const points = PointsPolicy.defaults;
      const terms = UrgencyPolicy.defaults;

      expect([for (final u in PointsPolicy.urgencies) points.pointsFor(u)], [1, 3, 5]);
      expect([for (final u in PointsPolicy.urgencies) terms.termsFor(u).additionalCharge], [10, 50, 100]);
      expect(terms.normal.completionTime.duration, isNull);
      expect(terms.urgent.completionTime.duration, const Duration(days: 3));
      expect(terms.emergency.completionTime.duration, const Duration(hours: 12));
      expect(terms.termsFor('Something else'), terms.normal);
    });

    test('a completion time is a number and a unit, read back as entered', () {
      expect(const CompletionTime(45, CompletionTimeUnit.minutes).duration, const Duration(minutes: 45));
      expect(const CompletionTime(1, CompletionTimeUnit.hours).label, '1 hour');
      expect(const CompletionTime(3, CompletionTimeUnit.days).label, '3 days');
      expect(const CompletionTime.none().label, 'No time limit');
      expect(const CompletionTime(0, CompletionTimeUnit.hours).isNone, isTrue);

      final policy = UrgencyPolicy.defaults.withTerms(
        'Normal',
        const UrgencyTerms(additionalCharge: 12.5, completionTime: CompletionTime(90, CompletionTimeUnit.minutes)),
      );
      expect(UrgencyPolicy.fromJson(policy.toJson()), policy);
      expect(formatAdditionalCharge(12.5), '₱12.50');
      expect(formatAdditionalCharge(100), '₱100');
    });

    test('a negative charge or a zero-length time is not valid', () {
      expect(
        const UrgencyTerms(additionalCharge: -1, completionTime: CompletionTime.none()).isValid,
        isFalse,
      );
      expect(
        const UrgencyTerms(additionalCharge: 0, completionTime: CompletionTime(0, CompletionTimeUnit.days)).isValid,
        isFalse,
      );
      expect(UrgencyPolicy.defaults.isValid, isTrue);
    });

    test('points: one figure per urgency, for the client and the mechanic alike', () {
      final policy = PointsPolicy.defaults.withPoints('Urgent', 4);
      expect(policy.pointsFor('Urgent'), 4);
      expect(policy.clientUrgent, 4, reason: 'still the API field');
      expect(policy.mechanicPerPeso, PointsPolicy.defaults.mechanicPerPeso,
          reason: 'carried through unchanged; the API requires it');
    });
  });

  group('urgency and ETA rules follow the settings', () {
    test('defaults behave as before: Normal runs on the ETA, Urgent and Emergency are capped', () {
      expect(_job('Normal').completionWindow, isNull);
      expect(maxEtaFor(_job('Normal')), isNull);
      expect(maxEtaFor(_job('Urgent')), const Duration(days: 3));
      expect(maxEtaFor(_job('Emergency')), const Duration(hours: 12));
      expect(_job('Emergency').durationLabel, 'Completed within 12 hours');
      expect(additionalChargeFor('Normal'), 10);
    });

    test('a time for Normal gives it a deadline and an ETA cap; None removes Urgent\'s', () {
      UrgencyPolicyStore.instance.debugSet(const UrgencyPolicy(
        normal: UrgencyTerms(additionalCharge: 20, completionTime: CompletionTime(2, CompletionTimeUnit.hours)),
        urgent: UrgencyTerms(additionalCharge: 60, completionTime: CompletionTime.none()),
        emergency: UrgencyTerms(additionalCharge: 150, completionTime: CompletionTime(30, CompletionTimeUnit.minutes)),
      ));

      final normal = _job('Normal');
      expect(normal.completionWindow, const Duration(hours: 2));
      expect(etaIsWithinCompletionWindow(normal, const Duration(hours: 3)), isFalse);
      expect(etaTooLongReason(normal, const Duration(hours: 3)), contains('Normal job must be completed within 2 hours'));

      final urgent = _job('Urgent');
      expect(urgent.completionWindow, isNull);
      expect(etaIsWithinCompletionWindow(urgent, const Duration(days: 30)), isTrue);
      expect(completionWindowLabel('Urgent'), "Completed within the mechanic's quoted ETA");

      final accepted = DateTime(2026, 9, 15, 9);
      final emergency = _job('Emergency', matchedAt: accepted);
      expect(emergency.completionDeadline, accepted.add(const Duration(minutes: 30)));
      expect(maxEtaFor(emergency, accepted.add(const Duration(minutes: 10))), const Duration(minutes: 20));
      expect(emergency.deadlinePassed(accepted.add(const Duration(minutes: 31))), isTrue);
      expect(completionWindowLabel('Emergency'), 'Completed within 30 mins');
      expect(additionalChargeFor('Emergency'), 150);
    });

    test('a job keeps the window it was created with when the setting changes', () {
      final accepted = DateTime(2026, 9, 15, 9);
      final running = _job('Urgent', matchedAt: accepted);

      UrgencyPolicyStore.instance.debugSet(UrgencyPolicy.defaults.withTerms(
        'Urgent',
        const UrgencyTerms(additionalCharge: 50, completionTime: CompletionTime(1, CompletionTimeUnit.days)),
      ));

      expect(running.completionWindow, const Duration(days: 3));
      expect(running.completionDeadline, accepted.add(const Duration(days: 3)));
      expect(_job('Urgent').completionWindow, const Duration(days: 1), reason: 'new jobs get the new setting');
    });
  });
}
