import 'package:flutter/material.dart';
import '../../../../widgets/rank_widgets.dart';
import '../../../../data/app_session.dart';
import '../../../../data/job_evaluation_store.dart';
import '../../../../data/mechanic_contact_store.dart';
import '../../../../data/mechanic_credential_store.dart';
import '../../../../data/mechanic_rank_store.dart';
import '../../../../data/review_store.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/app_widgets.dart';
import '../../../../widgets/common_widgets.dart';
import '../../../../widgets/credential_widgets.dart';
import '../../../../widgets/evaluation_widgets.dart';
import '../../../../widgets/mechanic_details_card.dart';
import '../../../../widgets/performance_widgets.dart';

enum _ReviewFilter { all, rating, mostRelevant }

class MechanicProfileViewScreen extends StatefulWidget {
  final String name;
  const MechanicProfileViewScreen({super.key, required this.name});

  /// Opens [name]'s profile on top of the current screen.
  ///
  /// The one way into this screen from anywhere in the client app — quotes,
  /// Mechanic Rankings, service history, a finished job. It used to be written
  /// out at each of those places; keeping it here means they cannot drift into
  /// opening it differently.
  ///
  /// [name] is the key everything on the profile is looked up by (reviews,
  /// credentials, contact details, completed jobs), so pass the name exactly as
  /// the record that led here carries it — `quote.mechanicName`, not a label.
  static Future<void> open(BuildContext context, String name) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MechanicProfileViewScreen(name: name)),
    );
  }

  @override
  State<MechanicProfileViewScreen> createState() => _MechanicProfileViewScreenState();
}

class _MechanicProfileViewScreenState extends State<MechanicProfileViewScreen> {
  final _store = ReviewStore.instance;
  final _credentials = MechanicCredentialStore.instance;
  final _contacts = MechanicContactStore.instance;
  final _ranks = MechanicRankStore.instance.changes;
  final _evaluations = JobEvaluationStore.instance;
  _ReviewFilter _filter = _ReviewFilter.all;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChange);
    _credentials.addListener(_onChange);
    _contacts.addListener(_onChange);
    _ranks.addListener(_onChange);
    _evaluations.addListener(_onChange);
  }

  @override
  void dispose() {
    _store.removeListener(_onChange);
    _credentials.removeListener(_onChange);
    _contacts.removeListener(_onChange);
    _ranks.removeListener(_onChange);
    _evaluations.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  List<MechanicReview> _applyFilter(List<MechanicReview> reviews) {
    final list = [...reviews];
    switch (_filter) {
      case _ReviewFilter.rating:
        list.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case _ReviewFilter.mostRelevant:
        list.sort((a, b) => b.helpfulCount.compareTo(a.helpfulCount));
        break;
      case _ReviewFilter.all:
        break; // reviewsFor already returns most-recent-first
    }
    return list;
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays >= 365) {
      final years = (diff.inDays / 365).floor();
      return '$years year${years == 1 ? '' : 's'} ago';
    }
    if (diff.inDays >= 30) {
      final months = (diff.inDays / 30).floor();
      return '$months month${months == 1 ? '' : 's'} ago';
    }
    if (diff.inDays >= 1) return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    return 'today';
  }

  /// Only a client, and never about themselves, writes a profile review.
  bool get _canReview =>
      AppSession.instance.currentRole == AppRole.client && widget.name != ReviewStore.currentClientName;

  /// CLIENT-ONLY write path — the dialog itself is only reachable from this
  /// client-side screen, and ReviewStore.submitReview backstops that at
  /// runtime by throwing if the active shell isn't the Client UI (see its
  /// doc comment). If that ever fires, we surface it instead of crashing.
  Future<void> _openReviewDialog() async {
    final existing = _store.reviewByCurrentClientFor(widget.name);
    int selected = existing?.rating ?? 0;
    final controller = TextEditingController(text: existing?.comment ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Write a review' : 'Edit your review'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (i) {
                    return IconButton(
                      tooltip: '${i + 1} star${i == 0 ? '' : 's'}',
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      constraints: const BoxConstraints(),
                      icon: Icon(i < selected ? Icons.star : Icons.star_border, color: AppColors.warning, size: 30),
                      onPressed: () => setDialogState(() => selected = i + 1),
                    );
                  }),
                ),
              ),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'Share your experience...'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: selected == 0 ? null : () => Navigator.pop(ctx, true),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      try {
        _store.submitReview(mechanicName: widget.name, rating: selected, comment: controller.text.trim());
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Review saved'), duration: AppDurations.snackBar));
      } on StateError catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message), duration: AppDurations.snackBar));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final credentials = _credentials.publicFor(widget.name);
    final contact = _contacts.contactFor(widget.name);
    final reviews = _applyFilter(_store.reviewsFor(widget.name));
    final average = _store.averageRatingFor(widget.name);
    final distribution = _store.ratingDistributionFor(widget.name);
    final alreadyReviewed = _store.reviewByCurrentClientFor(widget.name) != null;
    final rank = MechanicRankStore.instance.rankFor(widget.name);
    final muted = AppColors.textdark.withValues(alpha: 0.55);
    // This client's own completed job with this mechanic that still owes its
    // job evaluation, if there is one — separate from the profile review.
    final pendingJob = _canReview
        ? _evaluations
            .pendingForClient(ReviewStore.currentClientName)
            .where((evaluation) => evaluation.mechanicId == widget.name)
            .firstOrNull
        : null;
    final viewerId = AppSession.instance.currentViewerName;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textmedium,
        title: const Text('Mechanic Profile'),
      ),
      body: ListView(
        padding: context.layout.pageInsets,
        children: [
          AppCard(
            padding: const EdgeInsets.all(16),
            color: AppColors.surface,
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.background,
                      child: Icon(Icons.person, color: muted, size: 44),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.name,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w800),
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined, size: 14, color: muted),
                              const SizedBox(width: 2),
                              // Takes what is left beside the pin and
                              // ellipses, rather than demanding its own width
                              // and running off the card.
                              Expanded(
                                child: Text('Puerto Princesa City',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Current rank, overall rating and review count.
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              TierBadge(tier: rank.label),
                              // One text, so it ellipses at large text sizes
                              // instead of overflowing the card.
                              Text.rich(
                                TextSpan(children: [
                                  TextSpan(text: '★ ', style: TextStyle(color: AppColors.warning)),
                                  TextSpan(
                                      text: reviews.isEmpty ? '—' : average.toStringAsFixed(1),
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                  TextSpan(
                                      text: ' · ${reviews.length} review${reviews.length == 1 ? '' : 's'}',
                                      style: TextStyle(color: muted)),
                                ]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Measured from recorded jobs and job evaluations — no fixed text.
                MechanicPerformanceSection(mechanicName: widget.name),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // The rank only — the multiplier and progress are the mechanic's.
          MechanicRankCard(mechanicName: widget.name, showProgress: false),
          const SizedBox(height: 16),
          // How to reach this mechanic. Read from the directory, since a
          // profile opened from a job card has only their name to go on.
          MechanicDetailsCard(phone: contact.phone, email: contact.email),
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.all(16),
            color: AppColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Certifications', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                // The documents and certifications this mechanic uploaded at
                // registration. Their Mechanic ID is never among them —
                // publicFor withholds it from every profile.
                if (credentials.isEmpty)
                  Text('No documents or certifications uploaded yet.', style: TextStyle(fontSize: 12, color: muted))
                else
                  ...credentials.map((c) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: CredentialRow(credential: c, onView: () => showCredentialPreview(context, c)),
                      )),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Client-only block — a mechanic can't review themselves, so this
          // has no counterpart on the Mechanic profile. It gets its own card
          // so the rest of the screen keeps the same card rhythm.
          AppCard(
            padding: const EdgeInsets.all(16),
            color: AppColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Review Summary', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                RatingSummaryBars(
                  average: average,
                  distribution: distribution,
                  reviewCount: reviews.length,
                ),
                if (_canReview) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _openReviewDialog,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(alreadyReviewed ? 'Edit your review' : 'Write a review'),
                    ),
                  ),
                ],
                if (pendingJob != null) ...[
                  const SizedBox(height: 12),
                  // The job evaluation is a separate thing: about one
                  // completed job, not this profile.
                  Text('You also have a completed job with this mechanic to evaluate.',
                      style: TextStyle(fontSize: 11, color: muted)),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => evaluateJob(context, pendingJob.jobId),
                      icon: const Icon(Icons.rate_review_outlined, size: 18),
                      label: const Text('Evaluate your job'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.all(16),
            color: AppColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Reviews', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    if (reviews.isNotEmpty)
                      Row(
                        children: [
                          Icon(Icons.star, size: 14, color: AppColors.warning),
                          const SizedBox(width: 2),
                          Text(average.toStringAsFixed(1), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          Text(' (${reviews.length})', style: TextStyle(fontSize: 12, color: muted)),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 12),
                // Wrap, not Row: all three stay on screen, and tappable, on a
                // narrow phone at a large text size.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FilterChip(label: 'All', selected: _filter == _ReviewFilter.all, onTap: () => setState(() => _filter = _ReviewFilter.all)),
                    _FilterChip(label: 'Rating', selected: _filter == _ReviewFilter.rating, onTap: () => setState(() => _filter = _ReviewFilter.rating)),
                    _FilterChip(
                        label: 'Most Relevant',
                        selected: _filter == _ReviewFilter.mostRelevant,
                        onTap: () => setState(() => _filter = _ReviewFilter.mostRelevant)),
                  ],
                ),
                const SizedBox(height: 16),
                if (reviews.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('No reviews yet.', style: TextStyle(color: muted, fontSize: 13)),
                  )
                else
                  ...reviews.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _ReviewCard(
                          reviewId: r.id,
                          name: r.clientName,
                          timeAgo: _timeAgo(r.date),
                          rating: r.rating,
                          comment: r.comment.isEmpty ? '(No comment left)' : r.comment,
                          helpfulCount: r.helpfulCount,
                          likedByMe: r.likedByViewer(viewerId),
                          onToggleLike: () => _store.toggleHelpful(r.id),
                        ),
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withValues(alpha: 0.1) : AppColors.surface,
            border: Border.all(color: selected ? AppColors.primary : AppColors.textdark.withValues(alpha: 0.2)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.primary : AppColors.textdark.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final String reviewId;
  final String name;
  final String timeAgo;
  final int rating;
  final String comment;
  final int helpfulCount;
  final bool likedByMe;
  final VoidCallback? onToggleLike;

  const _ReviewCard({
    required this.reviewId,
    required this.name,
    required this.timeAgo,
    required this.rating,
    required this.comment,
    required this.helpfulCount,
    required this.likedByMe,
    required this.onToggleLike,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          Row(
            children: [
              CircleAvatar(
                  radius: 16, backgroundColor: AppColors.background, child: Icon(Icons.person, size: 18, color: AppColors.textdark.withValues(alpha: 0.55))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    Text(timeAgo, style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(
              5,
              (i) => Icon(i < rating ? Icons.star : Icons.star_border, color: AppColors.warning, size: 14),
            ),
          ),
          const SizedBox(height: 8),
          Text(comment, style: TextStyle(fontSize: 12, color: AppColors.textdark)),
          const SizedBox(height: 8),
          InkWell(
            onTap: onToggleLike,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              // Tall enough to hit with a thumb, and flush left with the
              // review text above it.
              padding: const EdgeInsets.fromLTRB(0, 10, 12, 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(likedByMe ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
                      size: 14, color: likedByMe ? AppColors.primary : AppColors.textdark.withValues(alpha: 0.55)),
                  const SizedBox(width: 4),
                  Text('$helpfulCount',
                      style: TextStyle(
                          fontSize: 11,
                          color: likedByMe ? AppColors.primary : AppColors.textdark.withValues(alpha: 0.55),
                          fontWeight: likedByMe ? FontWeight.w700 : FontWeight.normal)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
