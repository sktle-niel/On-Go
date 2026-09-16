import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_go/data/app_session.dart';
import 'package:on_go/data/mechanic_account_store.dart';
import 'package:on_go/data/mechanic_notification_store.dart';
import 'package:on_go/data/mechanic_rank_store.dart';
import 'package:on_go/data/quote_store.dart';
import 'package:on_go/data/rank_policy_store.dart';
import 'package:on_go/data/review_store.dart';
import 'package:on_go/screens/auth/client_ui/client_home_screen.dart';
import 'package:on_go/screens/auth/client_ui/profile/mechanic_profile_view_screen.dart';
import 'package:on_go/screens/auth/client_ui/rank/rankings_screen.dart';
import 'package:on_go/screens/auth/mechanic_ui/mechanic_home_screen.dart';
import 'package:on_go/screens/auth/mechanic_ui/profile/mechanic_profile_screen.dart';
import 'package:on_go/widgets/app_widgets.dart';
import 'package:on_go/theme/app_theme.dart';
import 'package:on_go/widgets/mechanic_rankings_widgets.dart';
import 'package:on_go_shared/on_go_shared.dart';

import 'performance_test_support.dart';
import 'responsive_layout_test.dart' show app;

const Size _phone = Size(390, 844);

ReviewStore get _reviews => ReviewStore.instance;

void _asClient() => AppSession.instance.setRole(AppRole.client, viewerName: ReviewStore.currentClientName);

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app(_phone, child));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    QuoteNotificationStore.instance.clear();
    resetPerformanceStores();
    MechanicNotificationStore.instance.clear();
    MechanicAccountStore.instance.enterDemoMode();
    RankPolicyStore.instance.debugSet(RankPolicy.defaults);
  });

  tearDown(() {
    resetPerformanceStores();
    RankPolicyStore.instance.debugSet(RankPolicy.defaults);
  });

  group('profile reviews', () {
    test('a client rates and reviews a mechanic; submitting again edits the same review', () {
      _asClient();
      _reviews.submitReview(mechanicName: 'Ana Cruz', rating: 4, comment: 'Knew the car well');
      _reviews.submitReview(mechanicName: 'Ana Cruz', rating: 5, comment: 'Came back to fix a rattle');

      final list = _reviews.reviewsFor('Ana Cruz');
      expect(list, hasLength(1));
      expect(list.single.rating, 5);
      expect(list.single.comment, 'Came back to fix a rattle');
      expect(list.single.clientName, ReviewStore.currentClientName);
      expect(_reviews.averageRatingFor('Ana Cruz'), 5);
      expect(_reviews.ratingCountFor('Ana Cruz'), 1);
    });

    test('only the Client UI can write one', () {
      AppSession.instance.setRole(AppRole.mechanic, viewerName: 'Ana Cruz');
      expect(
        () => _reviews.submitReview(mechanicName: 'Ana Cruz', rating: 5, comment: ''),
        throwsStateError,
      );
      expect(_reviews.reviewsFor('Ana Cruz'), isEmpty);
    });

    test('reviews are saved and come back after a restart', () async {
      _asClient();
      _reviews.submitReview(mechanicName: 'Ana Cruz', rating: 3, comment: 'Fine');
      await _reviews.debugRestart();
      expect(_reviews.reviewsFor('Ana Cruz').single.comment, 'Fine');
    });

    test('the rank counts profile reviews and their average', () {
      RankPolicyStore.instance.debugSet(RankPolicy.defaults.withTier(
        MechanicRank.bronze,
        const RankTier(requirement: RankRequirement(reviews: 1, averageRating: 4), multiplier: 1.25),
      ));
      expect(MechanicRankStore.instance.rankFor('Ana Cruz'), MechanicRank.iron);

      _asClient();
      _reviews.submitReview(mechanicName: 'Ana Cruz', rating: 5, comment: '');
      final standing = MechanicRankStore.instance.standingFor('Ana Cruz');
      expect(standing.reviews, 1);
      expect(standing.averageRating, 5);
      expect(MechanicRankStore.instance.rankFor('Ana Cruz'), MechanicRank.bronze);
    });
  });

  group('arranging the rankings', () {
    const entries = [
      MechanicRankingEntry(name: 'Ana', rank: MechanicRank.gold, rating: 4.2, reviewCount: 3),
      MechanicRankingEntry(name: 'Ben', rank: MechanicRank.iron, rating: 4.9, reviewCount: 1),
      MechanicRankingEntry(name: 'Cara', rank: MechanicRank.platinum, rating: 3.1, reviewCount: 9),
    ];

    List<String> names(List<MechanicRankingEntry> list) => [for (final e in list) e.name];

    test('by rank, rating or reviews — highest first, or lowest first', () {
      expect(names(MechanicRankingsView.arrange(entries, sort: RankingSort.rank)), ['Cara', 'Ana', 'Ben']);
      expect(names(MechanicRankingsView.arrange(entries, sort: RankingSort.ratings)), ['Ben', 'Ana', 'Cara']);
      expect(names(MechanicRankingsView.arrange(entries, sort: RankingSort.ratings, ascending: true)),
          ['Cara', 'Ana', 'Ben']);
      expect(names(MechanicRankingsView.arrange(entries, sort: RankingSort.reviews)), ['Cara', 'Ana', 'Ben']);
      expect(names(MechanicRankingsView.arrange(entries, sort: RankingSort.reviews, ascending: true)),
          ['Ben', 'Ana', 'Cara']);
    });

    test('filtered to one rank, and by search', () {
      expect(names(MechanicRankingsView.arrange(entries, sort: RankingSort.rank, rank: MechanicRank.gold)), ['Ana']);
      expect(MechanicRankingsView.arrange(entries, sort: RankingSort.rank, rank: MechanicRank.silver), isEmpty);
      expect(names(MechanicRankingsView.arrange(entries, sort: RankingSort.rank, query: 'car')), ['Cara']);
    });
  });

  group('screens', () {
    testWidgets('both shells call the tab Rankings, never Leaderboard', (tester) async {
      await _pump(tester, const ClientHomeScreen());
      expect(tester.widget<OnGoBottomNav>(find.byType(OnGoBottomNav)).items.map((i) => i.label),
          ['Home', 'Jobs', 'History', 'Rankings']);

      await tester.pumpWidget(app(_phone, const MechanicHomeScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.widget<OnGoBottomNav>(find.byType(OnGoBottomNav)).items.map((i) => i.label),
          ['Jobs', 'Earning', 'QR', 'Rankings', 'Profile']);
      expect(find.textContaining('Leaderboard'), findsNothing);
    });

    testWidgets('the rankings list shows real ranks and filters by Rank, Ratings and Reviews', (tester) async {
      _asClient();
      _reviews.submitReview(mechanicName: 'Ana Cruz', rating: 5, comment: 'Great');
      await _pump(tester, const RankingsScreen());

      expect(find.text('Ana Cruz'), findsOneWidget);
      expect(find.text('Iron'), findsWidgets, reason: 'every mechanic has a rank');

      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pump();
      expect(find.text('Filter'), findsOneWidget);
      expect(find.text('Rank'), findsOneWidget);
      expect(find.text('Ratings'), findsOneWidget);
      await tester.tap(find.text('Reviews'));
      await tester.pump();
      expect(find.text('1 review'), findsOneWidget);

      // Rank is back in the Filter menu, and ranks show again.
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pump();
      await tester.tap(find.text('Rank'));
      await tester.pump();
      expect(find.text('Iron'), findsWidgets);
    });

    testWidgets('there is no separate row of rank chips — the Filter menu covers Rank', (tester) async {
      await _pump(tester, const RankingsScreen());
      expect(find.text('All ranks'), findsNothing);
      // Rank names still show — but only as a mechanic's badge.
      expect(find.byType(TierBadge), findsWidgets);
      for (final rank in MechanicRank.values) {
        final inBadges = find.descendant(of: find.byType(TierBadge), matching: find.text(rank.label));
        expect(find.text(rank.label).evaluate().length, inBadges.evaluate().length,
            reason: 'no chip for ${rank.label}');
      }
    });

    testWidgets('choosing a mechanic opens their profile, where the client writes a review', (tester) async {
      _asClient();
      // A quote is enough for a mechanic to be known on this device.
      QuoteNotificationStore.instance.submitRequest(HelpRequest(
        id: 'rank-open',
        problem: 'Flat tire',
        location: 'Puerto Princesa City',
        urgency: 'Normal',
        photoPaths: const [],
        createdAt: DateTime.now(),
        clientName: ReviewStore.currentClientName,
      ));
      AppSession.instance.setRole(AppRole.mechanic, viewerName: 'Ana Cruz');
      QuoteNotificationStore.instance
          .mechanicSendQuote('rank-open', mechanicName: 'Ana Cruz', price: '₱450', eta: const Duration(hours: 1), rating: 0);
      _asClient();
      await _pump(tester, const RankingsScreen());

      await tester.tap(find.text('Ana Cruz'));
      await tester.pumpAndSettle();
      expect(find.byType(MechanicProfileViewScreen), findsOneWidget);
      expect(find.text('Iron'), findsWidgets);
      expect(find.text('Review Summary'), findsOneWidget);

      // Buttons further down the profile may sit below the fold; press them
      // directly rather than hit-testing.
      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Write a review')).onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Write a review'), findsNWidgets(2), reason: 'the dialog title and the button');
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.star_border).at(3)).onPressed!();
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, 'Honest and quick');
      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Submit')).onPressed!();
      await tester.pumpAndSettle();

      final saved = _reviews.reviewsFor('Ana Cruz').single;
      expect(saved.rating, 4);
      expect(saved.comment, 'Honest and quick');
      expect(find.text('Edit your review'), findsOneWidget);
      // The Reviews card sits further down the profile; scroll to it.
      await tester.dragUntilVisible(
        find.text('Honest and quick'),
        find.byType(ListView).last,
        const Offset(0, -300),
      );
      expect(find.text('Honest and quick'), findsOneWidget);
      expect(find.text(ReviewStore.currentClientName), findsWidgets, reason: 'a profile review is signed');
    });

    testWidgets("a mechanic sees their own Review Summary, with nothing to write", (tester) async {
      final me = QuoteNotificationStore.currentMechanicName;
      _asClient();
      _reviews.submitReview(mechanicName: me, rating: 4, comment: 'Solid work');
      AppSession.instance.setRole(AppRole.mechanic, viewerName: me);

      await _pump(tester, const MechanicProfileScreen());
      await tester.dragUntilVisible(find.text('Review Summary'), find.byType(ListView).last, const Offset(0, -300));
      expect(find.text('Review Summary'), findsOneWidget);
      final bars = tester.widget<RatingSummaryBars>(find.byType(RatingSummaryBars));
      expect(bars.average, 4);
      expect(bars.reviewCount, 1);
      expect(bars.distribution[4], 1);
      expect(find.text('Write a review'), findsNothing);
    });

    testWidgets('a mechanic reading a profile cannot write a review', (tester) async {
      AppSession.instance.setRole(AppRole.mechanic, viewerName: QuoteNotificationStore.currentMechanicName);
      await _pump(tester, const MechanicProfileViewScreen(name: 'Ana Cruz'));
      expect(find.text('Review Summary'), findsOneWidget);
      expect(find.text('Write a review'), findsNothing);
    });
  });
}
