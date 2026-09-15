import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../data/app_session.dart';
import '../../../../data/mechanic_account_store.dart';
import '../../../../services/backend/mobile_backend.dart';
import '../../../../data/quote_store.dart';
import '../../../../data/mechanic_credential_store.dart';
import '../../../../data/review_store.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/common_widgets.dart';
import '../../../../widgets/credential_widgets.dart';
import '../../../../widgets/mechanic_details_card.dart';

enum _ReviewFilter { all, rating, mostRelevant }

class MechanicProfileScreen extends StatefulWidget {
  /// True when pushed as its own route (drawer, leaderboard tap) — wraps
  /// the content in a Scaffold with the standard red app bar. False when
  /// used as a bottom-nav tab body inside MechanicHomeScreen, which already
  /// supplies its own Scaffold/app bar — wrapping again there would nest
  /// Scaffolds and duplicate the app bar.
  final bool standalone;
  const MechanicProfileScreen({super.key, this.standalone = true});

  @override
  State<MechanicProfileScreen> createState() => _MechanicProfileScreenState();
}

class _MechanicProfileScreenState extends State<MechanicProfileScreen> {
  final _reviews = ReviewStore.instance;
  final _account = MechanicAccountStore.instance;
  final _credentials = MechanicCredentialStore.instance;
  _ReviewFilter _filter = _ReviewFilter.all;

  @override
  void initState() {
    super.initState();
    _reviews.addListener(_onChange);
    _account.addListener(_onChange);
    _credentials.addListener(_onChange);
  }

  @override
  void dispose() {
    _reviews.removeListener(_onChange);
    _account.removeListener(_onChange);
    _credentials.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  String get _approvalNote {
    if (_account.isDemo) return 'Demo Mode';
    if (!_account.isRegistered) return '';
    switch (_account.status) {
      case ApprovalStatus.pending:
        return 'Pending Approval';
      case ApprovalStatus.rejected:
        return 'Account Rejected';
      case ApprovalStatus.approved:
      default:
        return '';
    }
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
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final myName = _account.name.isEmpty ? 'Mechanic' : _account.name;
    final credentials = _credentials.publicFor(myName);
    final reviews = _applyFilter(_reviews.reviewsFor(myName));
    final average = _reviews.averageRatingFor(myName);
    final viewerId = AppSession.instance.currentViewerName;
    final approvalNote = _approvalNote;
    final photo = _account.photoPath;

    final content = ListView(
      padding: context.layout.pageInsets,
      children: [
        AppCard(
          padding: const EdgeInsets.all(16),
          color: AppColors.surface,
          child: Column(
            children: [
              Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: AppColors.background,
                        backgroundImage: photo == null
                            ? null
                            : (_account.photoIsNetwork ? NetworkImage(photo) : FileImage(File(photo))) as ImageProvider?,
                        child: photo == null ? Icon(Icons.person, color: AppColors.textdark.withValues(alpha: 0.55), size: 44) : null,
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(myName,
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w800),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            if (approvalNote.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (approvalNote == 'Account Rejected' ? AppColors.primary : AppColors.warning).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(approvalNote,
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: approvalNote == 'Account Rejected' ? AppColors.primary : AppColors.warning)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined, size: 14, color: AppColors.textdark.withValues(alpha: 0.55)),
                            const SizedBox(width: 2),
                            // The place name takes what is left beside the pin
                            // and ellipses. Bare, it demanded its own full
                            // width and ran off the card on a narrow phone.
                            Expanded(
                              child: Text(
                                'Puerto Princesa City',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textdark.withValues(alpha: 0.55)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _StatBox(value: '${QuoteNotificationStore.instance.completedJobsFor(myName).length}', label: 'Jobs Done'),
                  _StatBox(value: reviews.isEmpty ? '—' : average.toStringAsFixed(1), label: 'Rating'),
                  // Reviews, not years of experience: nothing records
                  // experience yet, and a made-up figure reads as fact.
                  _StatBox(value: '${reviews.length}', label: 'Reviews'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // The same card a client sees on this profile, from the signed-in
        // account rather than the directory.
        MechanicDetailsCard(phone: _account.phone, email: _account.email),
        const SizedBox(height: 16),
        AppCard(
          padding: const EdgeInsets.all(16),
          color: AppColors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Certifications', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              // The documents and certifications this mechanic uploaded when
              // they registered. Their Mechanic ID is deliberately absent —
              // publicFor never returns it.
              if (credentials.isEmpty)
                Text('No documents or certifications uploaded yet.',
                    style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)))
              else
                ...credentials.map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: CredentialRow(credential: c, onView: () => showCredentialPreview(context, c)),
                    )),
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
                        Text(' (${reviews.length})', style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55))),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 12),
              // Wrap, not Row: three chips ending in "Most Relevant" do not
              // fit across a narrow phone, and a chip that has run off the
              // edge cannot be tapped. Wrapping onto a second line keeps all
              // three reachable at every width, and costs nothing on a wide
              // screen where they still sit on one.
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
              // Mechanics can only ever land here to VIEW and (optionally)
              // mark a review helpful — there is no write/edit path on this
              // screen, and ReviewStore.submitReview would throw at runtime
              // even if something tried to call it from this tree.
              if (reviews.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No reviews yet.', style: TextStyle(color: AppColors.textdark.withValues(alpha: 0.55), fontSize: 13)),
                )
              else
                ...reviews.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _ReviewCard(
                        name: r.clientName,
                        timeAgo: _timeAgo(r.date),
                        rating: r.rating,
                        comment: r.comment.isEmpty ? '(No comment left)' : r.comment,
                        helpfulCount: r.helpfulCount,
                        likedByMe: r.likedByViewer(viewerId),
                        onToggleLike: () => _reviews.toggleHelpful(r.id),
                      ),
                    )),
            ],
          ),
        ),
      ],
    );

    if (!widget.standalone) return content;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textmedium,
        title: const Text('Mechanic Profile'),
      ),
      body: content,
    );
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
}

class _StatBox extends StatelessWidget {
  final String value;
  final String label;
  const _StatBox({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.textdark.withValues(alpha: 0.2)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: AppColors.textdark)),
          ],
        ),
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
  final String name;
  final String timeAgo;
  final int rating;
  final String comment;
  final int helpfulCount;
  final bool likedByMe;
  final VoidCallback onToggleLike;

  const _ReviewCard({
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
            // Tall enough to hit with a thumb, and flush left with the review
            // text above it.
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