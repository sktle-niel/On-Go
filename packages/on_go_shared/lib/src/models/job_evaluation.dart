import 'json.dart';

/// Structured feedback a client can add to a job evaluation — quick to tap,
/// and countable in a way free text is not.
enum EvaluationTag {
  professional('professional', 'Professional', positive: true),
  goodCommunication('good_communication', 'Good communication', positive: true),
  fastService('fast_service', 'Fast service', positive: true),
  qualityWork('quality_work', 'Quality work', positive: true),
  fairPricing('fair_pricing', 'Fair pricing', positive: true),
  arrivedLate('arrived_late', 'Arrived late', positive: false),
  poorCommunication('poor_communication', 'Poor communication', positive: false),
  jobIncomplete('job_incomplete', 'Job incomplete', positive: false),
  unexpectedCharge('unexpected_charge', 'Unexpected charge', positive: false),
  poorWorkmanship('poor_workmanship', 'Poor workmanship', positive: false),
  other('other', 'Other', positive: false);

  const EvaluationTag(this.wireName, this.label, {required this.positive});

  final String wireName;
  final String label;
  final bool positive;

  static List<EvaluationTag> get positives => values.where((tag) => tag.positive).toList();

  static List<EvaluationTag> get negatives => values.where((tag) => !tag.positive).toList();

  static EvaluationTag? fromWire(String value) {
    for (final tag in values) {
      if (tag.wireName == value) return tag;
    }
    return null;
  }
}

/// Where a job's evaluation stands.
enum EvaluationStatus {
  /// The job is paid and complete; the client owes it an evaluation.
  required('required'),

  /// The client evaluated it. Locked from here on.
  submitted('submitted'),

  /// No longer counts — the job was invalidated (refunded, fraudulent) or an
  /// admin removed the evaluation. Kept, never deleted, with the reason.
  voided('voided');

  const EvaluationStatus(this.wireName);

  final String wireName;

  static EvaluationStatus fromWire(String value) =>
      values.firstWhere((status) => status.wireName == value, orElse: () => EvaluationStatus.required);
}

/// What a client gives when evaluating a job: stars, and optionally tags and
/// a few words.
class EvaluationSubmission {
  const EvaluationSubmission({required this.rating, this.tags = const {}, this.feedback = ''});

  final int rating;
  final Set<EvaluationTag> tags;
  final String feedback;

  static const int maxFeedbackLength = 500;

  /// Why this cannot be submitted, or null when it can.
  String? get problem {
    if (rating < 1 || rating > 5) return 'Choose a rating from 1 to 5 stars.';
    if (feedback.trim().length > maxFeedbackLength) {
      return 'Keep written feedback under $maxFeedbackLength characters.';
    }
    return null;
  }
}

/// The job an evaluation is about, as it stood when it was paid. Kept with the
/// evaluation so the record — and the client's history — outlives the job.
class EvaluatedJobSummary {
  const EvaluatedJobSummary({
    required this.problem,
    required this.location,
    required this.urgency,
    required this.paidAt,
    this.amountPaid,
  });

  final String problem;
  final String location;
  final String urgency;
  final DateTime paidAt;

  /// What the mechanic was paid, in pesos.
  final double? amountPaid;

  Map<String, dynamic> toJson() => {
        'problem': problem,
        'location': location,
        'urgency': urgency,
        'paidAt': writeDate(paidAt),
        'amountPaid': amountPaid,
      };

  factory EvaluatedJobSummary.fromJson(Map<String, dynamic> json) => EvaluatedJobSummary(
        problem: readString(json['problem']),
        location: readString(json['location']),
        urgency: readString(json['urgency']),
        paidAt: readDate(json['paidAt']),
        amountPaid: json['amountPaid'] is num ? readDouble(json['amountPaid']) : null,
      );
}

/// A client's evaluation of ONE completed job — `job_evaluations` in a backend:
/// `job_id` (unique), `client_id`, `mechanic_id`, `rating`, `tags`, `feedback`,
/// `submitted_at`.
///
/// It belongs to the job, not to the mechanic: a client who hires the same
/// mechanic three times evaluates three jobs. A mechanic's overall rating is
/// the aggregate of these, never a number overwritten on their profile.
///
/// [clientId] is always kept, even though mechanics are only ever shown the
/// [anonymous] view — fraud checks, duplicate prevention and disputes need to
/// know who wrote it.
class JobEvaluation {
  const JobEvaluation({
    required this.jobId,
    required this.clientId,
    required this.mechanicId,
    required this.job,
    required this.requiredAt,
    this.status = EvaluationStatus.required,
    this.clientAccountId,
    this.rating,
    this.tags = const {},
    this.feedback = '',
    this.submittedAt,
    this.voidedAt,
    this.voidReason,
  });

  /// Derived from the job, so there can only ever be one evaluation per job:
  /// a second one is the same record.
  String get id => idForJob(jobId);

  static String idForJob(String jobId) => 'evaluation_$jobId';

  final String jobId;

  /// The client the job belongs to, as the job records them.
  final String clientId;

  /// The On Go API account of the client who submitted it, when there was one.
  final String? clientAccountId;

  final String mechanicId;
  final EvaluatedJobSummary job;

  /// When the job became eligible — payment confirmed and the job complete.
  final DateTime requiredAt;

  final EvaluationStatus status;
  final int? rating;
  final Set<EvaluationTag> tags;
  final String feedback;
  final DateTime? submittedAt;
  final DateTime? voidedAt;
  final String? voidReason;

  /// `evaluation_required`: the client still owes this job an evaluation.
  bool get evaluationRequired => status == EvaluationStatus.required;

  /// `evaluation_submitted`.
  bool get evaluationSubmitted => status == EvaluationStatus.submitted;

  /// Whether it counts toward the mechanic's rating and everything built on it.
  bool get counts => status == EvaluationStatus.submitted && rating != null;

  JobEvaluation submitted(EvaluationSubmission submission, {required DateTime at, String? clientAccountId}) =>
      _copy(
        status: EvaluationStatus.submitted,
        rating: submission.rating,
        tags: submission.tags,
        feedback: submission.feedback.trim(),
        submittedAt: at,
        clientAccountId: clientAccountId ?? this.clientAccountId,
      );

  JobEvaluation voided(String reason, {required DateTime at}) =>
      _copy(status: EvaluationStatus.voided, voidedAt: at, voidReason: reason);

  JobEvaluation _copy({
    EvaluationStatus? status,
    int? rating,
    Set<EvaluationTag>? tags,
    String? feedback,
    DateTime? submittedAt,
    String? clientAccountId,
    DateTime? voidedAt,
    String? voidReason,
  }) =>
      JobEvaluation(
        jobId: jobId,
        clientId: clientId,
        mechanicId: mechanicId,
        job: job,
        requiredAt: requiredAt,
        status: status ?? this.status,
        clientAccountId: clientAccountId ?? this.clientAccountId,
        rating: rating ?? this.rating,
        tags: tags ?? this.tags,
        feedback: feedback ?? this.feedback,
        submittedAt: submittedAt ?? this.submittedAt,
        voidedAt: voidedAt ?? this.voidedAt,
        voidReason: voidReason ?? this.voidReason,
      );

  /// What a mechanic may see: no client, no job id (which their own job list
  /// would map back to a client), and only the day it was written.
  AnonymousEvaluation get anonymous {
    final at = submittedAt ?? requiredAt;
    return AnonymousEvaluation(
      // Not [id], which carries the job id in plain text.
      id: 'review_${_stableHash('$jobId|$clientId').toRadixString(36)}',
      rating: rating ?? 0,
      tags: tags,
      feedback: feedback,
      submittedOn: DateTime(at.year, at.month, at.day),
    );
  }

  Map<String, dynamic> toJson() => {
        'jobId': jobId,
        'clientId': clientId,
        'clientAccountId': clientAccountId,
        'mechanicId': mechanicId,
        'job': job.toJson(),
        'requiredAt': writeDate(requiredAt),
        'status': status.wireName,
        'rating': rating,
        'tags': [for (final tag in tags) tag.wireName],
        'feedback': feedback,
        'submittedAt': writeDateOrNull(submittedAt),
        'voidedAt': writeDateOrNull(voidedAt),
        'voidReason': voidReason,
      };

  factory JobEvaluation.fromJson(Map<String, dynamic> json) => JobEvaluation(
        jobId: readString(json['jobId']),
        clientId: readString(json['clientId']),
        clientAccountId: readStringOrNull(json['clientAccountId']),
        mechanicId: readString(json['mechanicId']),
        job: EvaluatedJobSummary.fromJson(readObject(json['job'])),
        requiredAt: readDate(json['requiredAt']),
        status: EvaluationStatus.fromWire(readString(json['status'])),
        rating: json['rating'] is num ? readInt(json['rating']) : null,
        tags: {
          for (final wire in readStringList(json['tags']))
            if (EvaluationTag.fromWire(wire) != null) EvaluationTag.fromWire(wire)!,
        },
        feedback: readString(json['feedback']),
        submittedAt: readDateOrNull(json['submittedAt']),
        voidedAt: readDateOrNull(json['voidedAt']),
        voidReason: readStringOrNull(json['voidReason']),
      );
}

/// An evaluation as a mechanic sees it: what was said, never who said it.
/// 32-bit FNV-1a: the same on every run and platform, unlike `hashCode`, so a
/// review keeps its id across restarts.
int _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash;
}

class AnonymousEvaluation {
  const AnonymousEvaluation({
    required this.id,
    required this.rating,
    required this.tags,
    required this.feedback,
    required this.submittedOn,
  });

  final String id;
  final int rating;
  final Set<EvaluationTag> tags;
  final String feedback;

  /// The day only — an exact time would line it up with the job it came from.
  final DateTime submittedOn;
}

/// An average that says how much it rests on: 5.0 from one rating is not 4.8
/// from two hundred.
class RatingSummary {
  const RatingSummary({this.count = 0, this.average = 0, this.distribution = const {}});

  factory RatingSummary.of(Iterable<int> ratings) {
    final list = ratings.where((rating) => rating >= 1 && rating <= 5).toList();
    if (list.isEmpty) return const RatingSummary();
    final counts = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    for (final rating in list) {
      counts[rating] = counts[rating]! + 1;
    }
    return RatingSummary(
      count: list.length,
      average: list.reduce((a, b) => a + b) / list.length,
      distribution: counts,
    );
  }

  final int count;

  /// 0 when there are no ratings — check [count] before showing it.
  final double average;

  /// Ratings per star.
  final Map<int, int> distribution;

  bool get isEmpty => count == 0;

  /// The share of ratings at [stars] or above, or null with no ratings.
  double? shareAtLeast(int stars) {
    if (count == 0) return null;
    final atLeast = distribution.entries.where((e) => e.key >= stars).fold<int>(0, (sum, e) => sum + e.value);
    return atLeast / count;
  }
}

/// What kind of problem a client is reporting. Separate from the rating: a
/// poor service is a rating, a dispute is a report.
enum ProblemCategory {
  noShow('no_show', "The mechanic didn't show up"),
  payment('payment', 'A payment or charge problem'),
  damage('damage', 'Damage to my vehicle'),
  safety('safety', 'A safety concern'),
  fraud('fraud', 'Suspected fraud'),
  other('other', 'Something else');

  const ProblemCategory(this.wireName, this.label);

  final String wireName;
  final String label;

  static ProblemCategory fromWire(String value) =>
      values.firstWhere((category) => category.wireName == value, orElse: () => ProblemCategory.other);
}

enum ProblemReportStatus {
  open('open'),
  underReview('under_review'),
  resolved('resolved');

  const ProblemReportStatus(this.wireName);

  final String wireName;

  static ProblemReportStatus fromWire(String value) =>
      values.firstWhere((status) => status.wireName == value, orElse: () => ProblemReportStatus.open);
}

/// A client reporting a problem with a job — for disputes, fraud and
/// anything that needs a person to look at it. Never inferred from a low
/// rating.
class ProblemReport {
  const ProblemReport({
    required this.id,
    required this.jobId,
    required this.clientId,
    required this.mechanicId,
    required this.category,
    required this.description,
    required this.createdAt,
    this.status = ProblemReportStatus.open,
  });

  final String id;
  final String jobId;
  final String clientId;
  final String mechanicId;
  final ProblemCategory category;
  final String description;
  final DateTime createdAt;
  final ProblemReportStatus status;

  static const int maxDescriptionLength = 1000;

  Map<String, dynamic> toJson() => {
        'id': id,
        'jobId': jobId,
        'clientId': clientId,
        'mechanicId': mechanicId,
        'category': category.wireName,
        'description': description,
        'createdAt': writeDate(createdAt),
        'status': status.wireName,
      };

  factory ProblemReport.fromJson(Map<String, dynamic> json) => ProblemReport(
        id: readString(json['id']),
        jobId: readString(json['jobId']),
        clientId: readString(json['clientId']),
        mechanicId: readString(json['mechanicId']),
        category: ProblemCategory.fromWire(readString(json['category'])),
        description: readString(json['description']),
        createdAt: readDate(json['createdAt']),
        status: ProblemReportStatus.fromWire(readString(json['status'])),
      );
}
