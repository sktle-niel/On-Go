import 'package:flutter/material.dart';
import '../../../../data/quote_store.dart';
import '../../../../data/review_store.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/app_widgets.dart';
import '../profile/mechanic_profile_view_screen.dart';

enum _RankFilter { rank, ratings, reviews }

class _Leader {
  final String name;
  final String tier;
  final double rating;
  final int reviewCount;
  const _Leader({required this.name, required this.tier, required this.rating, required this.reviewCount});
}

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final _reviews = ReviewStore.instance;

  _RankFilter _filter = _RankFilter.rank;
  bool _ascending = false;
  bool _filterOpen = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _reviews.addListener(_onChange);
  }

  @override
  void dispose() {
    _reviews.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  // Todo: there's no multi-mechanic backend yet, so this is always exactly
  // one real entry — the current mechanic account.
  List<_Leader> _buildLeaders() {
    final mechanicName = QuoteNotificationStore.currentMechanicName;
    final mechanicReviews = _reviews.reviewsFor(mechanicName);
    return [
      _Leader(
        name: mechanicName,
        tier: 'Gold',
        rating: mechanicReviews.isEmpty ? 0.0 : _reviews.averageRatingFor(mechanicName),
        reviewCount: mechanicReviews.length,
      ),
    ];
  }

  List<_Leader> _applyFilters(List<_Leader> leaders) {
    final list = leaders.where((l) => l.name.toLowerCase().contains(_query.toLowerCase())).toList();
    list.sort((a, b) {
      final cmp = switch (_filter) {
        _RankFilter.rank => a.rating.compareTo(b.rating),
        _RankFilter.ratings => a.rating.compareTo(b.rating),
        _RankFilter.reviews => a.reviewCount.compareTo(b.reviewCount),
      };
      return _ascending ? cmp : -cmp;
    });
    return list;
  }

  String _reviewLabel(int count) => count >= 1000 ? '${(count / 1000).toStringAsFixed(0)}k reviews' : '$count reviews';

  Widget _trailingFor(_Leader leader) {
    switch (_filter) {
      case _RankFilter.rank:
        return Text(leader.tier, style: TextStyle(fontSize: 14, color: AppColors.textdark));
      case _RankFilter.ratings:
        return RatingStars(rating: leader.rating);
      case _RankFilter.reviews:
        return Text(_reviewLabel(leader.reviewCount), style: TextStyle(fontSize: 14, color: AppColors.textdark));
    }
  }

  Widget _filterPill(String label, _RankFilter value) {
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
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? AppColors.textlight : AppColors.textdark)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _applyFilters(_buildLeaders());

    return Stack(
      children: [
        ListView(
          padding: context.layout.pageInsets,
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(24)),
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        // The list filters as you type, so the magnifier marks
                        // the field instead of being a button that does nothing.
                        prefixIcon: Icon(Icons.search, size: 20, color: AppColors.textdark.withValues(alpha: 0.55)),
                        prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        hintText: 'Search mechanics...',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.swap_vert),
                  tooltip: 'Reverse order',
                  onPressed: () => setState(() => _ascending = !_ascending),
                ),
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  tooltip: 'Filter mechanics',
                  onPressed: () => setState(() => _filterOpen = !_filterOpen),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...sorted.asMap().entries.map((entry) {
              final rank = entry.key + 1;
              final leader = entry.value;
              return GestureDetector(
                onTap: () => MechanicProfileViewScreen.open(context, leader.name),
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
                        child: Text('$rank', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.background,
                        child: Icon(Icons.person, color: AppColors.textdark.withValues(alpha: 0.55)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(leader.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                      _trailingFor(leader),
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
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('Filter', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  _filterPill('Rank', _RankFilter.rank),
                  _filterPill('Ratings', _RankFilter.ratings),
                  _filterPill('Reviews', _RankFilter.reviews),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}