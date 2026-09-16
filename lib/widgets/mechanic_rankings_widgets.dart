import 'package:flutter/material.dart';
import 'package:on_go_shared/on_go_shared.dart';

import '../data/mechanic_account_store.dart';
import '../data/mechanic_performance_store.dart';
import '../data/mechanic_rank_store.dart';
import '../data/quote_store.dart';
import '../data/review_store.dart';
import '../theme/app_theme.dart';
import 'app_widgets.dart';

/// What the Rankings list is ordered by.
enum RankingSort { rank, ratings, reviews }

/// One mechanic as the Rankings list shows them.
class MechanicRankingEntry {
  const MechanicRankingEntry({
    required this.name,
    required this.rank,
    required this.rating,
    required this.reviewCount,
  });

  final String name;
  final MechanicRank rank;

  /// The average of their profile reviews; 0 without any.
  final double rating;
  final int reviewCount;
}

/// Mechanic Rankings — discovering mechanics by rank, rating and reviews.
///
/// Shared by the Client and Mechanic tabs. This is NOT the competitive
/// seasonal leaderboard (seasons, placement, Gem badges, seasonal multiplier —
/// see `LeaderboardStore`, which is kept separate and not shown yet): nothing
/// here is seasonal, and a mechanic's place in the list is only where the
/// chosen sort puts them.
///
/// Every value is real: rank from [MechanicRankStore], rating and review count
/// from the profile reviews in [ReviewStore].
class MechanicRankingsView extends StatefulWidget {
  const MechanicRankingsView({super.key, required this.onOpenMechanic, this.highlightName});

  final void Function(String mechanicName) onOpenMechanic;

  /// Marked "You".
  final String? highlightName;

  /// Everyone this device knows as a mechanic: the signed-in mechanic account,
  /// mechanics who quoted or worked a job, and mechanics with profile reviews
  /// or recorded jobs. There is no mechanic directory in the API yet.
  static List<MechanicRankingEntry> entries() {
    final names = <String>{
      QuoteNotificationStore.currentMechanicName,
      ...QuoteNotificationStore.instance.knownMechanicNames,
      ...ReviewStore.instance.reviewedMechanics,
      for (final outcome in MechanicPerformanceStore.instance.all) outcome.mechanicId,
    }..removeWhere((name) => name.trim().isEmpty);
    final reviews = ReviewStore.instance;
    return [
      for (final name in names)
        MechanicRankingEntry(
          name: name,
          rank: MechanicRankStore.instance.rankFor(name),
          rating: reviews.averageRatingFor(name),
          reviewCount: reviews.ratingCountFor(name),
        ),
    ];
  }

  /// [entries] narrowed to [rank] (all ranks when null) and [query], in [sort]
  /// order — highest first unless [ascending]. Ties fall to the other two
  /// criteria, then the name, so the order never shuffles between rebuilds.
  static List<MechanicRankingEntry> arrange(
    List<MechanicRankingEntry> entries, {
    required RankingSort sort,
    bool ascending = false,
    MechanicRank? rank,
    String query = '',
  }) {
    final needle = query.trim().toLowerCase();
    final list = entries
        .where((e) => rank == null || e.rank == rank)
        .where((e) => needle.isEmpty || e.name.toLowerCase().contains(needle))
        .toList();

    int byRank(MechanicRankingEntry a, MechanicRankingEntry b) => a.rank.index.compareTo(b.rank.index);
    int byRating(MechanicRankingEntry a, MechanicRankingEntry b) => a.rating.compareTo(b.rating);
    int byReviews(MechanicRankingEntry a, MechanicRankingEntry b) => a.reviewCount.compareTo(b.reviewCount);

    final order = switch (sort) {
      RankingSort.rank => [byRank, byRating, byReviews],
      RankingSort.ratings => [byRating, byReviews, byRank],
      RankingSort.reviews => [byReviews, byRating, byRank],
    };

    list.sort((a, b) {
      for (final compare in order) {
        final result = compare(a, b);
        if (result != 0) return ascending ? result : -result;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  @override
  State<MechanicRankingsView> createState() => _MechanicRankingsViewState();
}

class _MechanicRankingsViewState extends State<MechanicRankingsView> {
  late final Listenable _sources = Listenable.merge([
    ReviewStore.instance,
    MechanicRankStore.instance.changes,
    QuoteNotificationStore.instance,
    MechanicAccountStore.instance,
  ]);

  RankingSort _filter = RankingSort.rank;
  bool _ascending = false;
  bool _filterOpen = false;
  String _query = '';

  String _reviewLabel(int count) => count >= 1000
      ? '${(count / 1000).toStringAsFixed(0)}k reviews'
      : '$count review${count == 1 ? '' : 's'}';

  Widget _trailingFor(MechanicRankingEntry entry) {
    switch (_filter) {
      case RankingSort.rank:
        return TierBadge(tier: entry.rank.label);
      case RankingSort.ratings:
        return RatingStars(rating: entry.rating);
      case RankingSort.reviews:
        return Text(_reviewLabel(entry.reviewCount), style: TextStyle(fontSize: 14, color: AppColors.textdark));
    }
  }

  Widget _filterPill(String label, RankingSort value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() {
        _filter = value;
        _filterOpen = false;
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          border: Border.all(color: AppColors.textmedium.withValues(alpha: 0.55)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: selected ? AppColors.textlight : AppColors.textdark)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _sources,
      builder: (context, _) {
        final sorted = MechanicRankingsView.arrange(
          MechanicRankingsView.entries(),
          sort: _filter,
          ascending: _ascending,
          query: _query,
        );

        return Stack(
          children: [
            ListView(
              padding: context.layout.pageInsets,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(24)),
                        child: TextField(
                          onChanged: (v) => setState(() => _query = v),
                          decoration: const InputDecoration(
                            hintText: 'Search mechanics...',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(icon: const Icon(Icons.search), onPressed: () {}),
                    IconButton(
                      tooltip: _ascending ? 'Lowest first' : 'Highest first',
                      icon: const Icon(Icons.swap_vert),
                      onPressed: () => setState(() => _ascending = !_ascending),
                    ),
                    IconButton(
                      tooltip: 'Filter',
                      icon: const Icon(Icons.filter_list),
                      onPressed: () => setState(() => _filterOpen = !_filterOpen),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (sorted.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('No mechanics match.',
                          style: TextStyle(color: AppColors.textdark.withValues(alpha: 0.55))),
                    ),
                  ),
                ...sorted.asMap().entries.map((item) {
                  final place = item.key + 1;
                  final entry = item.value;
                  final isYou = entry.name == widget.highlightName;
                  return GestureDetector(
                    onTap: () => widget.onOpenMechanic(entry.name),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.textdark.withValues(alpha: 0.2)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            child: Text('$place', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          ),
                          const SizedBox(width: 8),
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: AppColors.background,
                            child: Icon(Icons.person, color: AppColors.textdark.withValues(alpha: 0.55)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(entry.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                ),
                                if (isYou) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration:
                                        BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(4)),
                                    child: Text('You',
                                        style: TextStyle(
                                            fontSize: 10, color: AppColors.textlight, fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _trailingFor(entry),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
            if (_filterOpen) ...[
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() => _filterOpen = false),
                  child: Container(color: Colors.transparent),
                ),
              ),
              Positioned(
                top: 58,
                right: 20,
                width: 150,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.textmedium.withValues(alpha: 0.55)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text('Filter', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                      _filterPill('Rank', RankingSort.rank),
                      _filterPill('Ratings', RankingSort.ratings),
                      _filterPill('Reviews', RankingSort.reviews),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
