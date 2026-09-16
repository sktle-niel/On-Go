import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/backend/mobile_backend.dart';
import 'app_session.dart';
import 'chat_store.dart';
import 'mechanic_notification_store.dart';
import 'points_policy_store.dart';
import 'points_wallet_store.dart';
import 'mechanic_account_store.dart';
import 'job_evaluation_store.dart';
import 'leaderboard_store.dart';
import 'mechanic_performance_store.dart';
import 'point_transaction_store.dart';
import 'urgency_policy_store.dart';

enum RequestStatus { pending, matched, completed }

/// The units a mechanic can quote an ETA in.
enum EtaUnit { minutes, hours, days }

extension EtaUnitDisplay on EtaUnit {
  /// The dropdown label, singular or plural to match [value].
  String labelFor(int value) {
    final plural = value == 1 ? '' : 's';
    switch (this) {
      case EtaUnit.minutes:
        return 'Minute$plural';
      case EtaUnit.hours:
        return 'Hour$plural';
      case EtaUnit.days:
        return 'Day$plural';
    }
  }

  Duration toDuration(int value) {
    switch (this) {
      case EtaUnit.minutes:
        return Duration(minutes: value);
      case EtaUnit.hours:
        return Duration(hours: value);
      case EtaUnit.days:
        return Duration(days: value);
    }
  }
}

/// How an ETA reads on screen. A mechanic picks a whole number of one unit,
/// so this prints back exactly what they chose — "30 mins", "1 hour", "2 days".
String formatEtaDuration(Duration eta) {
  final minutes = eta.inMinutes;
  if (minutes <= 0) return 'now';
  if (minutes % (24 * 60) == 0) {
    final days = minutes ~/ (24 * 60);
    return '$days day${days == 1 ? '' : 's'}';
  }
  if (minutes % 60 == 0) {
    final hours = minutes ~/ 60;
    return '$hours hour${hours == 1 ? '' : 's'}';
  }
  return '$minutes min${minutes == 1 ? '' : 's'}';
}

class MechanicQuote {
  final String id;
  final String requestId;
  final String mechanicName;
  final String price;

  /// How long the mechanic says it will take them to REACH the client — a
  /// real duration, not free text, because the client's job details count
  /// down against it and the client is told when it runs out. See
  /// [expectedArrivalAt].
  final Duration etaDuration;

  final double rating;
  bool accepted;

  /// Set when the MECHANIC took their own offer back, before it was accepted.
  /// See [QuoteNotificationStore.mechanicWithdrawQuote].
  DateTime? withdrawnAt;

  /// Set when the CLIENT turned this offer down. See
  /// [QuoteNotificationStore.clientRejectQuote].
  DateTime? rejectedAt;

  MechanicQuote({
    required this.id,
    required this.requestId,
    required this.mechanicName,
    required this.price,
    required this.etaDuration,
    required this.rating,
    this.accepted = false,
    this.withdrawnAt,
    this.rejectedAt,
  });

  bool get isWithdrawn => withdrawnAt != null;
  bool get isRejected => rejectedAt != null;

  /// Whether this quote is still on the table. A withdrawn or rejected quote
  /// is kept as a record — the mechanic is told their quote was rejected, and
  /// a rejected quote is what stops them re-sending the same offer — but it is
  /// no longer an offer, so the client never sees it and it can never be
  /// accepted. [QuoteNotificationStore.quotesForRequest] returns only these.
  bool get isLive => withdrawnAt == null && rejectedAt == null;

  /// The ETA as text, for anywhere that just displays it.
  String get eta => formatEtaDuration(etaDuration);
}

double parsePesoAmount(String price) {
  final digits = price.replaceAll(RegExp(r'[^0-9.]'), '');
  return double.tryParse(digits) ?? 0;
}

class PaymentQrPayload {
  final String requestId;
  final String mechanicName;
  final double amount;
  const PaymentQrPayload({required this.requestId, required this.mechanicName, required this.amount});
}

const _qrPrefix = 'ONGOPAY';

String buildPaymentQrData({required String requestId, required String mechanicName, required double amount}) {
  return '$_qrPrefix|$requestId|$mechanicName|${amount.toStringAsFixed(2)}';
}

PaymentQrPayload? parsePaymentQrData(String raw) {
  final parts = raw.split('|');
  if (parts.length != 4 || parts[0] != _qrPrefix) return null;
  final amount = double.tryParse(parts[3]);
  if (amount == null) return null;
  return PaymentQrPayload(requestId: parts[1], mechanicName: parts[2], amount: amount);
}

const _accountQrPrefix = 'ONGOACCOUNT';

String buildMechanicAccountQrData(String mechanicName) => '$_accountQrPrefix|$mechanicName';

/// Dispatch order for urgency — Emergency first, then Urgent, then Normal.
/// The one ordering rule; anything that sorts by urgency goes through this.
int urgencyPriority(String urgency) {
  switch (urgency) {
    case 'Emergency':
      return 0;
    case 'Urgent':
      return 1;
    default:
      return 2;
  }
}

/// How long a mechanic has to COMPLETE a new job of [urgency], counted from
/// the moment they accept it — or null when that urgency has no time limit
/// (None in the admin's settings; Normal by default). A job with no window
/// runs on the ETA its mechanic quotes, and nothing caps that ETA.
///
/// Read from [UrgencyPolicyStore], which follows the admin's settings. This is
/// what a NEW job is given: each job keeps the window it was created with (see
/// [HelpRequest.completionWindow]), which is what the Accepted tab's
/// countdown, the "Time Remaining" sort, the auto-expiry sweep and the ETA cap
/// all run on — so changing a setting never moves a deadline already running.
Duration? completionWindowFor(String urgency) =>
    UrgencyPolicyStore.instance.current.termsFor(urgency).completionTime.duration;

/// A completion promise in words — "Completed within 12 hours" / "3 days" —
/// or, with no window, the mechanic's ETA.
String completionWindowLabelFor(Duration? window) => window == null
    ? 'Completed within the mechanic\'s quoted ETA'
    : 'Completed within ${formatEtaDuration(window)}';

/// The promise a new job of [urgency] would carry — what the Urgency Level
/// picker shows, read from the same settings the job's deadline is set from.
String completionWindowLabel(String urgency) => completionWindowLabelFor(completionWindowFor(urgency));

/// The additional charge a new job of [urgency] carries, in pesos — fixed onto
/// the job as [HelpRequest.surcharge] when it is uploaded.
double additionalChargeFor(String urgency) =>
    UrgencyPolicyStore.instance.current.termsFor(urgency).additionalCharge;

/// How a remaining-time value reads on screen, switching format at the 24h
/// mark: 24h or more counts days, hours and minutes ("4d 23h 59m",
/// "2d 06h 15m", and "1d 00h 00m" at exactly a day); under 24h it ticks down
/// to the second ("23h 59m 59s" → "1h 5m 20s" → "0h 0m 0s"). Lives here, with
/// the deadlines themselves, so every screen shows one countdown format.
String formatTimeRemaining(Duration remaining) {
  if (remaining >= const Duration(hours: 24)) {
    final hours = (remaining.inHours % 24).toString().padLeft(2, '0');
    final minutes = (remaining.inMinutes % 60).toString().padLeft(2, '0');
    return '${remaining.inDays}d ${hours}h ${minutes}m';
  }
  return '${remaining.inHours}h ${remaining.inMinutes % 60}m ${remaining.inSeconds % 60}s';
}

/// The problem report a client uploads from NeedHelpScreen.
class HelpRequest {
  final String id;
  final String problem;
  final String location;
  final String urgency; // 'Normal' | 'Urgent' | 'Emergency'
  final DateTime createdAt;
  final String clientName;
  /// What this job's urgency promises the client, in words. Derived rather
  /// than stored so it always matches [completionWindow] — the deadline the
  /// job is really held to.
  String get durationLabel => completionWindowLabelFor(completionWindow);

  /// ONGO's additional charge for this job's urgency, in pesos — the admin's
  /// setting at the moment the job was uploaded (₱10 Normal, ₱50 Urgent,
  /// ₱100 Emergency by default). This is PLATFORM revenue, not part of the
  /// job price: the client pays it on top of the mechanic's amount at
  /// checkout, and it never reaches the mechanic's payout. See
  /// [clientTotalPaymentAmount].
  final double surcharge;

  final double? clientLat;
  final double? clientLng;

  RequestStatus status;
  DateTime? matchedAt;

  bool navigating;
  bool enRoute;
  bool arrived;
  bool workStarted;
  bool serviceCompleted;
  bool paymentCompleted;
  DateTime? navigatingAt;
  DateTime? enRouteAt;
  DateTime? arrivedAt;
  DateTime? workStartedAt;
  DateTime? serviceCompletedAt;
  DateTime? paymentCompletedAt;

  /// Points the MECHANIC earned on this job — the points its urgency awarded
  /// the client, times the mechanic's [pointsMultiplier], at the rates in force
  /// when it was paid. Kept per job for the mechanic's lifetime total; never
  /// shown per job, since what a job awards is the admin's to see.
  double? pointsAwarded;

  /// The multiplier [pointsAwarded] was worked out with — the mechanic's rank
  /// multiplier plus any bonus — as it stood when the job was paid.
  double? pointsMultiplier;

  /// Points the client spent to cover this job's priority fee, or null when
  /// they paid it in pesos. 1 pt = ₱1, so this doubles as the peso value.
  double? feePaidWithPoints;
  DateTime? completedAt;

  String? lastCancelReason;
  String? lastCancelledBy;
  DateTime? lastCancelledAt;

  /// Set once the client has been told the mechanic's ETA ran out, so the
  /// notification is raised exactly once per acceptance. Cleared whenever the
  /// job is accepted afresh, since that starts a new ETA.
  DateTime? etaPassedNotifiedAt;

  /// Set when an accepted job was handed back to the pool because the
  /// mechanic didn't finish it inside [completionWindow] — see
  /// [QuoteNotificationStore.expireOverdueJobs]. This is what the client's
  /// Jobs screen reads to tell them the mechanic ran out of time.
  /// Cleared the moment the client accepts a new quote.
  DateTime? expiredAt;
  String? expiredByMechanic;

  /// EMERGENCY ONLY. Normal/Urgent jobs already have a firm price from the
  /// mechanic's quote (sent and accepted before the job started) — that
  /// price never changes and is never negotiated in-app, so this field
  /// stays null for them. Emergency jobs skip quoting entirely, so this is
  /// how the mechanic sets (and can update) the price once they and the
  /// client agree on one in person. See [effectivePaymentAmount] for the
  /// single rule both charging and display always follow.
  double? agreedPaymentAmount;
  DateTime? agreedPaymentAmountSetAt;

  /// THE PAYMENT RECORD for this job — the mechanic's amount as it was
  /// actually charged, stamped once by
  /// [QuoteNotificationStore.clientConfirmPayment] and never recomputed.
  /// Mirrors `payments.amount` in the backend schema.
  ///
  /// This is what history must read. Re-deriving a finished job's amount from
  /// its quote is what made emergency jobs show the placeholder price the
  /// accept record carries instead of the amount the client and mechanic
  /// actually agreed on.
  double? amountPaid;

  /// The priority fee actually booked as ONGO revenue for this job. Stays
  /// null until the client pays — [QuoteNotificationStore.clientConfirmPayment]
  /// sets it at the same moment it reports the payment to
  /// [PlatformRevenueApi.reportCompletedPayment], so it doubles as the record
  /// of "this job's fee has already been counted". Mirrors
  /// `payments.platform_fee`.
  double? platformFeeCharged;

  HelpRequest({
    required this.id,
    required this.problem,
    required this.location,
    required this.urgency,
    required this.createdAt,
    this.clientName = 'Client',
    this.surcharge = 0,
    this.clientLat,
    this.clientLng,
    this.status = RequestStatus.pending,
    this.matchedAt,
    this.navigating = false,
    this.enRoute = false,
    this.arrived = false,
    this.workStarted = false,
    this.serviceCompleted = false,
    this.paymentCompleted = false,
    this.navigatingAt,
    this.enRouteAt,
    this.arrivedAt,
    this.workStartedAt,
    this.serviceCompletedAt,
    this.paymentCompletedAt,
    this.pointsAwarded,
    this.feePaidWithPoints,
    this.completedAt,
    this.lastCancelReason,
    this.lastCancelledBy,
    this.lastCancelledAt,
    this.expiredAt,
    this.expiredByMechanic,
    this.agreedPaymentAmount,
    this.agreedPaymentAmountSetAt,
    this.amountPaid,
    this.platformFeeCharged,
    Duration? completionWindow,
  }) : completionWindow = completionWindow ?? completionWindowFor(urgency);

  /// The full amount the client handed over — the mechanic's share plus the
  /// priority fee. Null until the job has actually been paid.
  double? get totalPaid =>
      amountPaid == null ? null : amountPaid! + (platformFeeCharged ?? 0);

  bool get isEmergency => urgency == 'Emergency';
  bool get hasClientCoordinates => clientLat != null && clientLng != null;

  /// The ONGO priority fee for this job, as an amount. Charged to the client
  /// at checkout only — never added to what the mechanic is paid.
  double get platformFee => surcharge;

  /// How long this job's mechanic has to finish it: the admin's completion
  /// time for its urgency AS IT WAS when the job was created, so a later
  /// change to the setting never moves a deadline already running. Null when
  /// that urgency had no time limit — the job then runs on the mechanic's ETA.
  final Duration? completionWindow;

  /// The moment this job must be finished by, anchored to [matchedAt] — the
  /// instant the mechanic accepted. Because it is derived from that stored
  /// timestamp rather than from when a widget was built, the countdown keeps
  /// running across rebuilds, navigation and reopening the app instead of
  /// restarting.
  ///
  /// Null for a Normal job even once accepted: there is no completion
  /// deadline to reach, so nothing counts down against one and the expiry
  /// sweep passes it over. What the client is owed on a Normal job is the
  /// arrival time on the quote they accepted — see [timeUntilArrival].
  DateTime? get completionDeadline {
    final window = completionWindow;
    return window == null ? null : matchedAt?.add(window);
  }

  /// Time left, never negative. Null when no deadline is running: the job
  /// isn't accepted, or the mechanic has reached Work in Progress — once they
  /// are actually working on it the clock stops for good, and with it the
  /// expiry, because [deadlinePassed] and every countdown on screen read this
  /// one method.
  Duration? timeRemaining([DateTime? now]) {
    final deadline = completionDeadline;
    if (deadline == null || workStarted || serviceCompleted || status != RequestStatus.matched) {
      return null;
    }
    final left = deadline.difference(now ?? DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Accepted, not yet under way, and out of time —
  /// [QuoteNotificationStore.expireOverdueJobs] is what acts on this.
  bool deadlinePassed([DateTime? now]) {
    final remaining = timeRemaining(now);
    return remaining != null && remaining == Duration.zero;
  }
}

/// THE single rule for "how much does this job actually cost" — every
/// screen and every calculation (QR generation, payment confirmation,
/// earnings totals, card displays) goes through this and NOTHING computes
/// its own version of this logic separately:
///   - Emergency: whatever the mechanic most recently set via
///     mechanicSetPaymentAmount — null until they set one.
///   - Normal/Urgent: the accepted quote's price, always. Never negotiable,
///     never overridden — the client already agreed to this exact number
///     when they accepted the quote.
/// When the mechanic is due at the client: the moment the job was matched
/// (the client accepted the quote, or the mechanic claimed the emergency)
/// plus the ETA quoted. Null until a quote is accepted.
///
/// This is what makes an ETA a commitment rather than a note: the client's
/// job details count down to it, and [QuoteNotificationStore.notifyLateArrivals]
/// tells the client when it passes.
DateTime? expectedArrivalAt(HelpRequest request, MechanicQuote? acceptedQuote) {
  final matchedAt = request.matchedAt;
  if (matchedAt == null || acceptedQuote == null) return null;
  return matchedAt.add(acceptedQuote.etaDuration);
}

/// Time left before the mechanic is due, never negative. Null when no
/// countdown applies: the job isn't accepted, or the mechanic has arrived.
Duration? timeUntilArrival(HelpRequest request, MechanicQuote? acceptedQuote, [DateTime? now]) {
  final due = expectedArrivalAt(request, acceptedQuote);
  if (due == null || request.arrived || request.status != RequestStatus.matched) return null;
  final left = due.difference(now ?? DateTime.now());
  return left.isNegative ? Duration.zero : left;
}

/// The ETA has run out and the mechanic still isn't there.
bool arrivalIsOverdue(HelpRequest request, MechanicQuote? acceptedQuote, [DateTime? now]) {
  final remaining = timeUntilArrival(request, acceptedQuote, now);
  return remaining != null && remaining == Duration.zero;
}

/// True while the mechanic still has time left on the ETA they committed to —
/// the window in which the client may NOT cancel.
///
/// The mechanic gave a time and is being held to it, so the client cannot pull
/// the job out from under them mid-journey. It unlocks the instant the ETA runs
/// out and stays unlocked from then on, and it is never locked once the
/// mechanic has arrived, because [timeUntilArrival] stops the countdown there.
bool clientCancelLockedByEta(HelpRequest request, MechanicQuote? acceptedQuote, [DateTime? now]) {
  final remaining = timeUntilArrival(request, acceptedQuote, now);
  return remaining != null && remaining > Duration.zero;
}

/// THE longest ETA a mechanic may promise on [request] — null when any ETA is
/// allowed.
///
/// A job with a completion window (Urgent and Emergency by default) must be
/// FINISHED inside it,
/// so an arrival time longer than what is left of that window is a promise the
/// job cannot keep: the mechanic would still be driving when the job was
/// already due. The cap is therefore the window itself before the job is
/// accepted (the clock starts on acceptance, so all of it is still ahead) and
/// whatever is left of it afterwards.
///
/// A job with no window (Normal by default) has nothing to cap it — its timing
/// IS the mechanic's ETA.
Duration? maxEtaFor(HelpRequest request, [DateTime? now]) {
  final window = request.completionWindow;
  if (window == null) return null;
  // Null while the job is still pending — the window has not started, so the
  // whole of it is available to quote against.
  return request.timeRemaining(now) ?? window;
}

/// Whether [eta] is a promise [request] can keep. The one rule both the quote
/// form and the store check, so a screen cannot send an ETA the store would
/// have to reject.
bool etaIsWithinCompletionWindow(HelpRequest request, Duration eta, [DateTime? now]) {
  final max = maxEtaFor(request, now);
  return max == null || eta <= max;
}

/// Why an over-long ETA was refused, in the words the mechanic needs: what
/// they entered, what the job allows, and which urgency imposed it. Null when
/// [eta] is fine.
String? etaTooLongReason(HelpRequest request, Duration eta, [DateTime? now]) {
  final max = maxEtaFor(request, now);
  if (max == null || eta <= max) return null;
  return 'A ${request.urgency} job must be completed within '
      '${formatEtaDuration(request.completionWindow!)}, and '
      '${formatTimeRemaining(max)} of that is left. Your ETA has to fit '
      'inside it — enter ${formatEtaDuration(max)} or less.';
}

/// What a live job is counting down to, and how long is left.
enum JobCountdownKind {
  /// A job with a completion window: its own completion deadline.
  completion,

  /// A job with no completion window: the arrival time the mechanic quoted.
  arrival,
}

class JobCountdown {
  final JobCountdownKind kind;
  final Duration remaining;
  const JobCountdown(this.kind, this.remaining);

  /// What the countdown is called on screen.
  String get label => kind == JobCountdownKind.completion ? 'Time Remaining' : 'Arriving in';
}

/// THE single answer to "what is this job counting down to" — read by the
/// Accepted tab's live row and by its Time Remaining sort, so the two can
/// never disagree about which clock a job is on.
///
/// Urgent and Emergency count down to their completion deadline, exactly as
/// before. Normal counts down to the mechanic's quoted arrival instead, since
/// that is now the only timing a Normal job carries. Null when neither clock
/// is running — the job isn't accepted, the mechanic has arrived (arrival), or
/// work is under way (completion).
JobCountdown? jobCountdown(HelpRequest request, MechanicQuote? acceptedQuote, [DateTime? now]) {
  if (request.completionWindow != null) {
    final remaining = request.timeRemaining(now);
    return remaining == null ? null : JobCountdown(JobCountdownKind.completion, remaining);
  }
  if (request.workStarted || request.serviceCompleted) return null;
  final remaining = timeUntilArrival(request, acceptedQuote, now);
  return remaining == null ? null : JobCountdown(JobCountdownKind.arrival, remaining);
}

double? effectivePaymentAmount(HelpRequest request, MechanicQuote? acceptedQuote) {
  if (request.isEmergency) return request.agreedPaymentAmount;
  return acceptedQuote == null ? null : parsePesoAmount(acceptedQuote.price);
}

/// What the CLIENT is charged at checkout: the mechanic's amount
/// ([effectivePaymentAmount]) plus ONGO's priority fee for the job's urgency
/// (the additional charge fixed on the job when it was uploaded). The two
/// halves stay apart on purpose — the
/// mechanic is paid [effectivePaymentAmount] and nothing more, while the fee
/// is booked as platform revenue by [QuoteNotificationStore.clientConfirmPayment].
/// Null whenever the mechanic's amount isn't known yet.
double? clientTotalPaymentAmount(HelpRequest request, MechanicQuote? acceptedQuote) {
  final mechanicAmount = effectivePaymentAmount(request, acceptedQuote);
  return mechanicAmount == null ? null : mechanicAmount + request.platformFee;
}

/// THE single rule for "what did this job actually cost" — what every HISTORY
/// view must use, on both the client and the mechanic side, so the two always
/// quote the same figure for the same job.
///
/// Prefers [HelpRequest.amountPaid], the record stamped when the client paid.
/// That matters most for Emergency jobs: their accept record carries no real
/// price (the amount is agreed in person afterwards), so anything reading
/// `quote.price` for a finished emergency reports a number that was never
/// charged. Falls back to [effectivePaymentAmount] for jobs that aren't paid
/// yet, and for any that completed before the amount was being recorded.
double? settledPaymentAmount(HelpRequest request, MechanicQuote? acceptedQuote) =>
    request.amountPaid ?? effectivePaymentAmount(request, acceptedQuote);

/// What a client's bell can tell them about. Each value is raised from the
/// one store method that performs it, so a notification can never be recorded
/// for something that didn't actually happen.
enum ClientNotificationKind {
  /// A mechanic sent a quote for one of the client's requests.
  quoteReceived,

  /// A mechanic took the job on. Emergency jobs only — for Normal and Urgent
  /// ones the CLIENT is the one who accepts a quote, so there is no
  /// mechanic-side acceptance to report.
  jobAccepted,

  /// The mechanic started working on the job.
  workStarted,

  /// The service is finished and the mechanic is waiting to be paid.
  awaitingPayment,

  /// The ETA the mechanic committed to has run out and they still haven't
  /// arrived. Raised by [QuoteNotificationStore.notifyLateArrivals].
  etaPassed,

  /// The mechanic dropped a job they had accepted. Raised by
  /// [QuoteNotificationStore.mechanicCancelJob] — the client is left waiting
  /// on someone who is no longer coming, so this cannot be left to them
  /// noticing the card changed.
  jobCancelled,
}

/// One entry in the client's notification list.
class ClientNotification {
  final String id;
  final ClientNotificationKind kind;

  /// The job this is about. Every client notification has one, so every one
  /// can be followed back to the job — see
  /// [QuoteNotificationStore.routeForClientNotification].
  final String requestId;

  /// The mechanic involved. Mechanics are keyed by name throughout the app
  /// (ReviewStore, quotes, profiles), so this doubles as their identifier.
  final String mechanicName;

  /// The specific quote, for [ClientNotificationKind.quoteReceived] — so
  /// tapping it opens THAT mechanic's offer rather than the job's whole list.
  /// Null for kinds that are about the job rather than an offer.
  final String? quoteId;

  /// The problem text as it read when the notification was raised, so the
  /// list still makes sense if the request is gone.
  final String problem;
  final DateTime createdAt;

  /// Extra context captured when the entry was raised, for the kinds that
  /// carry one — currently the mechanic's reason for cancelling. Stored on the
  /// entry rather than read back off the request, so the notification still
  /// says why even after the job is re-accepted by someone else and the
  /// request's own `lastCancelReason` has moved on.
  final String? detail;

  /// Cleared by [QuoteNotificationStore.markClientNotificationsSeen] — this is
  /// what the bell's badge counts.
  bool read;

  ClientNotification({
    required this.id,
    required this.kind,
    required this.requestId,
    required this.mechanicName,
    required this.problem,
    required this.createdAt,
    this.quoteId,
    this.detail,
    this.read = false,
  });

  String get title {
    switch (kind) {
      case ClientNotificationKind.quoteReceived:
        return 'New quote received';
      case ClientNotificationKind.jobAccepted:
        return 'Mechanic accepted your job';
      case ClientNotificationKind.workStarted:
        return 'Mechanic started the job';
      case ClientNotificationKind.awaitingPayment:
        return 'Waiting for your payment';
      case ClientNotificationKind.etaPassed:
        return 'Mechanic is late — you can now cancel';
      case ClientNotificationKind.jobCancelled:
        return 'Mechanic cancelled your job';
    }
  }

  String get message {
    switch (kind) {
      case ClientNotificationKind.quoteReceived:
        return '$mechanicName sent you a quote.';
      case ClientNotificationKind.jobAccepted:
        return '$mechanicName accepted your job and is on the way.';
      case ClientNotificationKind.workStarted:
        return '$mechanicName has started working on your job.';
      case ClientNotificationKind.awaitingPayment:
        return '$mechanicName finished the service and is waiting for payment.';
      case ClientNotificationKind.etaPassed:
        return '$mechanicName\'s ETA has passed and they haven\'t arrived yet. '
            'You can now cancel this job if you want to.';
      case ClientNotificationKind.jobCancelled:
        // The reason is the mechanic's own words, typed into a box, so it is
        // punctuated here before being read as part of a sentence. Without a
        // reason the client is still told what happened and what happens next.
        final reason = detail?.trim();
        if (reason == null || reason.isEmpty) {
          return '$mechanicName cancelled your job. Your request is open for quotes again.';
        }
        final ended = RegExp(r'[.!?]$').hasMatch(reason) ? reason : '$reason.';
        return '$mechanicName cancelled your job: $ended '
            'Your request is open for quotes again.';
    }
  }
}

/// Where tapping a notification leads.
///
/// Decided by [QuoteNotificationStore.routeForClientNotification] and
/// [QuoteNotificationStore.routeForMechanicNotification] at the moment of the
/// tap, from the job's CURRENT state rather than the state it was in when the
/// notification was raised. A quote notification from last week must not open
/// a quote for a job that has since been finished, so the screens never decide
/// this for themselves — they only carry out the route they are handed.
sealed class NotificationRoute {
  const NotificationRoute();
}

/// The client's Quotes view for one job. [quoteId], when set, is the offer the
/// notification was about, and the screen spotlights it.
class OpenJobQuotes extends NotificationRoute {
  final String requestId;
  final String? quoteId;
  const OpenJobQuotes(this.requestId, {this.quoteId});
}

/// The client's progress screen for a job a mechanic is on.
class OpenClientJob extends NotificationRoute {
  final String requestId;
  const OpenClientJob(this.requestId);
}

/// The mechanic's active-job screen for a job assigned to them.
class OpenMechanicJob extends NotificationRoute {
  final String requestId;
  const OpenMechanicJob(this.requestId);
}

/// A job still open to mechanics, shown in place on the mechanic's Jobs
/// screen — the Emergency tab for an emergency, Available otherwise. There is
/// no separate job-detail screen for an open job: its card IS the job, with
/// the actions on it, so the card is what gets opened.
class OpenJobInList extends NotificationRoute {
  final String requestId;
  final bool emergency;
  const OpenJobInList(this.requestId, {required this.emergency});
}

/// The mechanic shell's tabs a notification can land on.
enum MechanicHomeTab { jobs, earning, profile }

/// One of the mechanic shell's own tabs, for notifications about the mechanic
/// rather than one job — a payment lands on Earning, a rating on the Profile
/// that lists reviews.
class OpenMechanicTab extends NotificationRoute {
  final MechanicHomeTab tab;
  const OpenMechanicTab(this.tab);
}

/// What the notification referred to has been deleted, finished, or taken by
/// someone else. The notification itself stays; tapping it explains instead of
/// opening a screen with nothing sensible to show.
class NotificationUnavailable extends NotificationRoute {
  final String message;
  const NotificationUnavailable(this.message);
}

class QuoteNotificationStore extends ChangeNotifier {
  QuoteNotificationStore._internal();
  static final QuoteNotificationStore instance = QuoteNotificationStore._internal();

  static String get currentMechanicName {
    final name = MechanicAccountStore.instance.name;
    return name.isEmpty ? 'You' : name;
  }

  final List<HelpRequest> _requests = [];
  final List<MechanicQuote> _allQuotes = [];
  int _unseenCount = 0;

  /// Every mechanic this device has seen quote or work a job — what the
  /// Mechanic Rankings list is built from until the API has a mechanic
  /// directory.
  Set<String> get knownMechanicNames => {for (final quote in _allQuotes) quote.mechanicName};
  final Set<String> _seenClientQuoteIds = {};
  final Set<String> _seenEmergencyRequestIds = {};
  final List<ClientNotification> _clientNotifications = [];

  // ---------------------------------------------------------------------
  // Client notification bell
  // ---------------------------------------------------------------------

  /// Everything the client's bell has to show, newest first.
  List<ClientNotification> get clientNotifications => List.unmodifiable(_clientNotifications);

  /// What the bell's badge displays. Zero hides the badge.
  int get clientUnreadNotificationCount => _clientNotifications.where((n) => !n.read).length;

  /// Called when the client opens the notifications list — this is what makes
  /// the badge go away.
  void markClientNotificationsSeen() {
    if (clientUnreadNotificationCount == 0) return;
    for (final n in _clientNotifications) {
      n.read = true;
    }
    notifyListeners();
  }

  /// Where tapping [notification] should take the client, given the job as it
  /// stands right now. See [NotificationRoute].
  NotificationRoute routeForClientNotification(ClientNotification notification) {
    final request = requestFor(notification.requestId);
    if (request == null) {
      return const NotificationUnavailable('This job no longer exists.');
    }

    if (notification.kind == ClientNotificationKind.quoteReceived) {
      if (request.status == RequestStatus.completed) {
        return const NotificationUnavailable(
            'This quote is no longer available because the job has been completed.');
      }

      // By id first. The name fallback only covers an entry raised before
      // quotes were tagged, and it only ever finds an offer still standing.
      final quote = (notification.quoteId == null ? null : quoteById(notification.quoteId!)) ??
          _liveQuoteFrom(request.id, notification.mechanicName);
      if (quote == null || quote.isWithdrawn) {
        return const NotificationUnavailable(
            'This quote is no longer available because the mechanic withdrew it.');
      }
      if (quote.isRejected) {
        return const NotificationUnavailable(
            'This quote is no longer available because you rejected it.');
      }
      if (request.status == RequestStatus.matched) {
        // The offer became the job — its progress is what there is to see now.
        return quote.accepted
            ? OpenClientJob(request.id)
            : const NotificationUnavailable(
                'This quote is no longer available because you accepted another mechanic\'s quote.');
      }
      return OpenJobQuotes(request.id, quoteId: quote.id);
    }

    // Every other client notification is about the job's progress, so it
    // follows the job to wherever it is now.
    switch (request.status) {
      case RequestStatus.completed:
        return const NotificationUnavailable(
            'This job has already been completed. You can find it in History.');
      case RequestStatus.matched:
        return OpenClientJob(request.id);
      case RequestStatus.pending:
        // Back on the market — after a cancellation, say — so its quotes are
        // the useful thing to see.
        return OpenJobQuotes(request.id);
    }
  }

  MechanicQuote? _liveQuoteFrom(String requestId, String mechanicName) {
    for (final q in _allQuotes) {
      if (q.requestId == requestId && q.mechanicName == mechanicName && q.isLive) return q;
    }
    return null;
  }

  /// Where tapping [notification] should take [mechanicName], given the job
  /// as it stands right now. See [NotificationRoute].
  NotificationRoute routeForMechanicNotification(
    MechanicNotification notification,
    String mechanicName,
  ) {
    switch (notification.kind) {
      case MechanicNotificationKind.paymentReceived:
        return const OpenMechanicTab(MechanicHomeTab.earning);
      case MechanicNotificationKind.rated:
        return const OpenMechanicTab(MechanicHomeTab.profile);
      case MechanicNotificationKind.accountApproved:
        return const OpenMechanicTab(MechanicHomeTab.jobs);
      case MechanicNotificationKind.emergencyPosted:
      case MechanicNotificationKind.quoteAccepted:
      case MechanicNotificationKind.quoteRejected:
        break;
    }

    final isEmergencyAlert = notification.kind == MechanicNotificationKind.emergencyPosted;
    final requestId = notification.requestId;
    final request = requestId == null ? null : requestFor(requestId);
    if (request == null) {
      return NotificationUnavailable(isEmergencyAlert
          ? 'This emergency job is no longer available. The client may have cancelled it.'
          : 'This job no longer exists.');
    }

    switch (request.status) {
      case RequestStatus.completed:
        return NotificationUnavailable(isEmergencyAlert
            ? 'This emergency job has already been completed.'
            : 'This job has already been completed.');
      case RequestStatus.matched:
        if (acceptedQuoteFor(request.id)?.mechanicName == mechanicName) {
          return OpenMechanicJob(request.id);
        }
        return NotificationUnavailable(isEmergencyAlert
            ? 'Another mechanic has already accepted this emergency job.'
            : 'This job is no longer assigned to you.');
      case RequestStatus.pending:
        // An accepted quote whose job is open again was handed back — by the
        // client, the clock, or the mechanic themselves.
        if (notification.kind == MechanicNotificationKind.quoteAccepted) {
          return const NotificationUnavailable('This job is no longer assigned to you.');
        }
        return OpenJobInList(request.id, emergency: request.isEmergency);
    }
  }

  /// Records one event for the client. Callers notify listeners themselves —
  /// every one of them already does at the end of the action.
  void _addClientNotification(
    ClientNotificationKind kind,
    HelpRequest request,
    String mechanicName, {
    String? quoteId,
    String? detail,
  }) {
    _clientNotifications.insert(
      0,
      ClientNotification(
        id: '${DateTime.now().microsecondsSinceEpoch}_${_clientNotifications.length}',
        kind: kind,
        requestId: request.id,
        mechanicName: mechanicName,
        problem: request.problem,
        createdAt: DateTime.now(),
        quoteId: quoteId,
        detail: detail,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Client-facing API
  // ---------------------------------------------------------------------

  List<HelpRequest> get myPendingRequests {
    final list = _requests.where((r) => r.status == RequestStatus.pending).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  List<HelpRequest> get myActiveJobs =>
      _requests.where((r) => r.status == RequestStatus.matched).toList();

  List<HelpRequest> get myCompletedJobs {
    final list = _requests.where((r) => r.status == RequestStatus.completed).toList();
    list.sort((a, b) =>
        (b.paymentCompletedAt ?? b.completedAt ?? b.createdAt).compareTo(a.paymentCompletedAt ?? a.completedAt ?? a.createdAt));
    return list;
  }

  HelpRequest? get activeRequest {
    final unfinished = _requests.where((r) => r.status != RequestStatus.completed).toList();
    if (unfinished.isNotEmpty) {
      unfinished.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return unfinished.last;
    }
    return _requests.isEmpty ? null : _requests.last;
  }

  List<MechanicQuote> get quotes {
    final req = activeRequest;
    if (req == null) return const [];
    return _allQuotes.where((q) => q.requestId == req.id && q.isLive).toList();
  }

  /// The offers still on the table for [requestId] — what the client sees and
  /// the only ones they can act on. Withdrawn and rejected quotes are filtered
  /// out here, once, so no screen has to remember to do it.
  List<MechanicQuote> quotesForRequest(String requestId) =>
      _allQuotes.where((q) => q.requestId == requestId && q.isLive).toList();

  /// Every quote record for [requestId], live or not. Internal: the lifecycle
  /// sweeps need the withdrawn and rejected ones too, so a stale `accepted`
  /// flag can never survive on a record the client can no longer see.
  List<MechanicQuote> _quoteRecordsFor(String requestId) =>
      _allQuotes.where((q) => q.requestId == requestId).toList();

  int get unseenCount => _unseenCount;
  bool get hasAcceptedQuote => quotes.any((q) => q.accepted);

  int unseenQuoteCountForRequest(String requestId) =>
      quotesForRequest(requestId).where((q) => !_seenClientQuoteIds.contains(q.id)).length;

  int get totalUnseenQuoteCountForClient =>
      myPendingRequests.fold(0, (sum, r) => sum + unseenQuoteCountForRequest(r.id));

  void markRequestQuotesSeen(String requestId) {
    _seenClientQuoteIds.addAll(quotesForRequest(requestId).map((q) => q.id));
    notifyListeners();
  }

  HelpRequest? requestFor(String requestId) {
    try {
      return _requests.firstWhere((r) => r.id == requestId);
    } catch (_) {
      return null;
    }
  }

  MechanicQuote? quoteById(String quoteId) {
    try {
      return _allQuotes.firstWhere((q) => q.id == quoteId);
    } catch (_) {
      return null;
    }
  }

  void submitRequest(HelpRequest request) {
    _requests.add(request);
    // Emergencies go out to every mechanic — nobody owns one until a mechanic
    // accepts it, so this is the one broadcast notification.
    if (request.isEmergency) {
      MechanicNotificationStore.instance.add(
        kind: MechanicNotificationKind.emergencyPosted,
        mechanicName: null,
        clientName: request.clientName,
        detail: '${request.problem} · ${request.location}',
        requestId: request.id,
      );
    }
    notifyListeners();
  }

  void markSeen() {
    if (_unseenCount == 0) return;
    _unseenCount = 0;
    notifyListeners();
  }

  void clientAcceptQuote(String quoteId) {
    final quote = quoteById(quoteId);
    if (quote == null) return;
    // A withdrawn or rejected quote is not an offer any more. The client's
    // list never shows one, but a screen holding a stale id must not be able
    // to accept an offer that was taken off the table.
    if (!quote.isLive) return;
    final req = requestFor(quote.requestId);
    if (req == null) return;

    for (final q in _quoteRecordsFor(quote.requestId)) {
      q.accepted = q.id == quoteId;
    }
    req.status = RequestStatus.matched;
    req.matchedAt = DateTime.now();
    req.etaPassedNotifiedAt = null;
    req.lastCancelReason = null;
    req.lastCancelledBy = null;
    req.lastCancelledAt = null;
    // A fresh acceptance restarts the completion clock and clears any notice
    // about the previous mechanic running out of time.
    req.expiredAt = null;
    req.expiredByMechanic = null;
    MechanicNotificationStore.instance.add(
      kind: MechanicNotificationKind.quoteAccepted,
      mechanicName: quote.mechanicName,
      clientName: req.clientName,
      detail: '${req.problem} · ${quote.price}',
      requestId: req.id,
      quoteId: quote.id,
    );
    notifyListeners();
  }

  void acceptQuote(String quoteId) => clientAcceptQuote(quoteId);

  bool clientRevertToPending(String requestId) {
    if (AppSession.instance.currentRole != AppRole.client) {
      throw StateError('Only the Client UI can cancel a request.');
    }
    final req = requestFor(requestId);
    if (req == null || req.status != RequestStatus.matched) return false;
    // The mechanic is still inside the ETA they promised — enforced here, not
    // only in the UI, so no screen can cancel around it.
    if (clientCancelLockedByEta(req, acceptedQuoteFor(requestId))) return false;

    for (final q in _quoteRecordsFor(requestId)) {
      q.accepted = false;
    }
    req.status = RequestStatus.pending;
    req.matchedAt = null;
    req.etaPassedNotifiedAt = null;
    req.navigating = false;
    req.enRoute = false;
    req.arrived = false;
    req.workStarted = false;
    req.serviceCompleted = false;
    req.navigatingAt = null;
    req.enRouteAt = null;
    req.arrivedAt = null;
    req.workStartedAt = null;
    req.serviceCompletedAt = null;
    req.agreedPaymentAmount = null;
    req.agreedPaymentAmountSetAt = null;
    notifyListeners();
    return true;
  }

  bool clientDeleteRequest(String requestId) {
    if (AppSession.instance.currentRole != AppRole.client) {
      throw StateError('Only the Client UI can delete a request.');
    }
    final req = requestFor(requestId);
    if (req == null || req.paymentCompleted) return false;
    // Deleting an accepted job is a cancellation by another name, so the same
    // ETA lock applies. An uploaded request nobody has taken is never locked.
    if (clientCancelLockedByEta(req, acceptedQuoteFor(requestId))) return false;
    _requests.removeWhere((r) => r.id == requestId);
    _allQuotes.removeWhere((q) => q.requestId == requestId);
    _clientNotifications.removeWhere((n) => n.requestId == requestId);
    MechanicNotificationStore.instance.removeForRequest(requestId);
    ChatStore.instance.clearChat(requestId);
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------------
  // Mechanic-facing API — accept / quote
  // ---------------------------------------------------------------------

  List<HelpRequest> get availableJobs =>
      _requests.where((r) => r.status == RequestStatus.pending).toList();

  /// Emergency jobs still open that the mechanic hasn't looked at in the
  /// Emergency tab yet — what makes the Emergency filter button pulse.
  ///
  /// Only jobs still in [availableJobs] count, so one that gets accepted or
  /// expires stops raising the alert on its own. Tracked by id, so a newly
  /// posted emergency is unseen again even after an earlier one was viewed.
  List<HelpRequest> get unseenEmergencyJobs => availableJobs
      .where((r) => r.isEmergency && !_seenEmergencyRequestIds.contains(r.id))
      .toList();

  bool get hasUnseenEmergencyJobs => unseenEmergencyJobs.isNotEmpty;

  /// Called when the mechanic opens the Emergency Jobs list — this is what
  /// stops the pulse.
  void markEmergencyJobsSeen() {
    final unseen = unseenEmergencyJobs;
    if (unseen.isEmpty) return;
    _seenEmergencyRequestIds.addAll(unseen.map((r) => r.id));
    notifyListeners();
  }

  /// This mechanic's offer on [requestId] while it is still standing — what
  /// turns their "Send Quote" button into "Withdraw Quote". Null once they
  /// withdraw it or the client rejects it, because neither is an offer any
  /// more.
  MechanicQuote? mechanicLiveQuoteFor(String requestId, String mechanicName) {
    for (final q in _allQuotes) {
      if (q.requestId == requestId && q.mechanicName == mechanicName && q.isLive) return q;
    }
    return null;
  }

  /// Whether this mechanic already had an offer turned down on this job. A
  /// rejection has to mean something: without this the mechanic could send the
  /// same quote straight back and the client would be answering it forever.
  /// Withdrawing their own quote carries no such block — that was their own
  /// decision, and re-quoting is the point of taking it back.
  bool mechanicQuoteWasRejected(String requestId, String mechanicName) => _allQuotes.any(
      (q) => q.requestId == requestId && q.mechanicName == mechanicName && q.isRejected);

  /// Whether this mechanic has a quote on the job that is still live. Kept as
  /// the name every caller already uses; a withdrawn quote is deliberately not
  /// one, since the whole point of withdrawing is to be able to quote again.
  bool mechanicHasQuoted(String requestId, String mechanicName) =>
      mechanicLiveQuoteFor(requestId, mechanicName) != null;

  /// The mechanic takes their own offer back.
  ///
  /// Only while it has NOT been accepted: once the client has accepted, the
  /// two are committed to each other and pulling out is a cancellation, which
  /// goes through [mechanicCancelJob] and carries a reason the client is told.
  /// Returns false when there is nothing of theirs to withdraw.
  bool mechanicWithdrawQuote(String requestId, {required String mechanicName}) {
    final quote = mechanicLiveQuoteFor(requestId, mechanicName);
    if (quote == null || quote.accepted) return false;

    quote.withdrawnAt = DateTime.now();
    // The client can no longer see the quote, so they must not be left with a
    // notification pointing at it either.
    _clientNotifications.removeWhere((n) =>
        n.kind == ClientNotificationKind.quoteReceived &&
        n.requestId == requestId &&
        n.mechanicName == mechanicName);
    _seenClientQuoteIds.remove(quote.id);
    if (_unseenCount > 0) _unseenCount--;
    notifyListeners();
    return true;
  }

  /// The client turns an offer down.
  ///
  /// The quote leaves their list and the mechanic is told, so a rejection is
  /// an answer rather than silence. An accepted quote cannot be rejected —
  /// backing out of a job the client already agreed to is a cancellation, and
  /// goes through [clientRevertToPending] with the ETA lock that applies to it.
  bool clientRejectQuote(String quoteId) {
    if (AppSession.instance.currentRole != AppRole.client) {
      throw StateError('Only the Client UI can reject a quote.');
    }
    final quote = quoteById(quoteId);
    if (quote == null || !quote.isLive || quote.accepted) return false;
    final req = requestFor(quote.requestId);

    quote.rejectedAt = DateTime.now();
    _clientNotifications.removeWhere((n) =>
        n.kind == ClientNotificationKind.quoteReceived &&
        n.requestId == quote.requestId &&
        n.mechanicName == quote.mechanicName);
    if (_unseenCount > 0) _unseenCount--;
    MechanicNotificationStore.instance.add(
      kind: MechanicNotificationKind.quoteRejected,
      mechanicName: quote.mechanicName,
      clientName: req?.clientName ?? 'The client',
      detail: '${req?.problem ?? 'Job'} · ${quote.price}',
      requestId: quote.requestId,
      quoteId: quote.id,
    );
    notifyListeners();
    return true;
  }

  void mechanicSendQuote(
    String requestId, {
    required String mechanicName,
    required String price,
    required Duration eta,
    required double rating,
  }) {
    if (!MechanicAccountStore.instance.canPerformJobActions) {
      throw StateError('Your mechanic account must be approved before you can send quotes.');
    }
    if (mechanicHasQuoted(requestId, mechanicName)) {
      throw StateError('You have already sent a quote for this job.');
    }
    if (mechanicQuoteWasRejected(requestId, mechanicName)) {
      throw StateError('The client rejected your quote for this job, so you cannot quote it again.');
    }
    // The ETA has to fit inside what is left of an Urgent or Emergency job's
    // completion window. Checked here as well as on the form, so no screen can
    // promise an arrival the job's own deadline rules out.
    final request = requestFor(requestId);
    if (request != null) {
      final tooLong = etaTooLongReason(request, eta);
      if (tooLong != null) throw StateError(tooLong);
    }
    final quote = MechanicQuote(
      id: '${DateTime.now().microsecondsSinceEpoch}_${_allQuotes.length}',
      requestId: requestId,
      mechanicName: mechanicName,
      price: price,
      etaDuration: eta,
      rating: rating,
    );
    _allQuotes.add(quote);
    _unseenCount++;
    final req = requestFor(requestId);
    if (req != null) {
      _addClientNotification(
        ClientNotificationKind.quoteReceived,
        req,
        mechanicName,
        quoteId: quote.id,
      );
    }
    notifyListeners();
  }

  bool mechanicHasActiveEmergency(String mechanicName) {
    return _requests.any((r) =>
        r.isEmergency &&
        r.status == RequestStatus.matched &&
        acceptedQuoteFor(r.id)?.mechanicName == mechanicName);
  }

  /// An emergency accept record is NOT a quote — emergencies skip quoting
  /// entirely and the amount is agreed in person afterwards, via
  /// [mechanicSetPaymentAmount]. So [price] stays empty by design: writing a
  /// placeholder figure here is what made finished emergency jobs report a
  /// price nobody ever charged.
  bool mechanicAcceptEmergency(
    String requestId, {
    required String mechanicName,
    String price = '',
    required Duration eta,
    required double rating,
  }) {
    final req = _requests.firstWhere((r) => r.id == requestId);
    if (req.status != RequestStatus.pending) return false;
    if (mechanicHasActiveEmergency(mechanicName)) return false;
    if (!MechanicAccountStore.instance.canPerformJobActions) return false;
    // An emergency must be finished within its window, so the arrival time
    // claimed on the way in cannot already overrun it.
    if (!etaIsWithinCompletionWindow(req, eta)) return false;

    _allQuotes.add(MechanicQuote(
      id: '${DateTime.now().microsecondsSinceEpoch}_${_allQuotes.length}',
      requestId: requestId,
      mechanicName: mechanicName,
      price: price,
      etaDuration: eta,
      rating: rating,
      accepted: true,
    ));
    req.status = RequestStatus.matched;
    req.matchedAt = DateTime.now();
    req.etaPassedNotifiedAt = null;
    req.lastCancelReason = null;
    req.lastCancelledBy = null;
    req.lastCancelledAt = null;
    req.expiredAt = null;
    req.expiredByMechanic = null;
    _unseenCount++;
    _addClientNotification(ClientNotificationKind.jobAccepted, req, mechanicName);
    notifyListeners();
    return true;
  }

  MechanicQuote? acceptedQuoteFor(String requestId) {
    for (final q in _allQuotes) {
      if (q.requestId == requestId && q.accepted) return q;
    }
    return null;
  }

  List<HelpRequest> matchedJobsFor(String mechanicName) => _requests
      .where((r) =>
          r.status == RequestStatus.matched &&
          acceptedQuoteFor(r.id)?.mechanicName == mechanicName)
      .toList();

  List<HelpRequest> completedJobsFor(String mechanicName) => _requests
      .where((r) =>
          r.status == RequestStatus.completed &&
          acceptedQuoteFor(r.id)?.mechanicName == mechanicName)
      .toList();

  // ---------------------------------------------------------------------
  // Service-status workflow
  // ---------------------------------------------------------------------

  void mechanicStartNavigating(String requestId) {
    if (AppSession.instance.currentRole != AppRole.mechanic) {
      throw StateError('Only the Mechanic UI can start navigating to a job.');
    }
    final req = requestFor(requestId);
    if (req == null || req.navigating) return;
    req.navigating = true;
    req.navigatingAt = DateTime.now();
    notifyListeners();
  }

  void mechanicMarkEnRoute(String requestId) {
    final req = requestFor(requestId);
    if (req == null || req.enRoute || req.status != RequestStatus.matched) return;
    req.enRoute = true;
    req.enRouteAt = DateTime.now();
    notifyListeners();
  }

  void mechanicMarkArrived(String requestId) {
    final req = requestFor(requestId);
    if (req == null || req.arrived || req.status != RequestStatus.matched) return;
    req.arrived = true;
    req.arrivedAt = DateTime.now();
    if (!req.enRoute) {
      req.enRoute = true;
      req.enRouteAt = req.arrivedAt;
    }
    notifyListeners();
  }

  void mechanicStartWork(String requestId) {
    if (AppSession.instance.currentRole != AppRole.mechanic) {
      throw StateError('Only the Mechanic UI can start work on a job.');
    }
    final req = requestFor(requestId);
    if (req == null || req.workStarted) return;
    req.workStarted = true;
    req.workStartedAt = DateTime.now();
    _addClientNotification(
      ClientNotificationKind.workStarted,
      req,
      acceptedQuoteFor(requestId)?.mechanicName ?? 'Your mechanic',
    );
    notifyListeners();
  }

  void mechanicCompleteService(String requestId) {
    if (AppSession.instance.currentRole != AppRole.mechanic) {
      throw StateError('Only the Mechanic UI can mark a service complete.');
    }
    final req = requestFor(requestId);
    if (req == null || req.serviceCompleted) return;
    req.serviceCompleted = true;
    req.serviceCompletedAt = DateTime.now();
    // Service done means the mechanic is now waiting to be paid.
    _addClientNotification(
      ClientNotificationKind.awaitingPayment,
      req,
      acceptedQuoteFor(requestId)?.mechanicName ?? 'Your mechanic',
    );
    notifyListeners();
  }

  /// EMERGENCY-ONLY. Sets (or updates) the price the mechanic and client
  /// agreed on in person — refuses outright for Normal/Urgent jobs, which
  /// always use their quote price and never go through this negotiation
  /// step at all. See [effectivePaymentAmount] for the full rule.
  bool mechanicSetPaymentAmount(String requestId, double amount) {
    if (AppSession.instance.currentRole != AppRole.mechanic) {
      throw StateError('Only the Mechanic UI can set the payment amount.');
    }
    final req = requestFor(requestId);
    if (req == null || req.paymentCompleted) return false;
    if (!req.isEmergency) {
      throw StateError('Normal and Urgent jobs use their quoted price — only Emergency jobs need a payment amount set.');
    }
    if (amount <= 0) return false;
    req.agreedPaymentAmount = amount;
    req.agreedPaymentAmountSetAt = DateTime.now();
    notifyListeners();
    return true;
  }

  bool mechanicCancelJob(String requestId, String reason) {
    if (AppSession.instance.currentRole != AppRole.mechanic) {
      throw StateError('Only the Mechanic UI can cancel a job.');
    }
    final req = requestFor(requestId);
    if (req == null || req.status != RequestStatus.matched) return false;
    if (req.isEmergency || req.navigating) return false;

    final mechanicName = acceptedQuoteFor(requestId)?.mechanicName;

    for (final q in _quoteRecordsFor(requestId)) {
      q.accepted = false;
    }
    req.status = RequestStatus.pending;
    req.matchedAt = null;
    req.etaPassedNotifiedAt = null;
    req.navigating = false;
    req.enRoute = false;
    req.arrived = false;
    req.workStarted = false;
    req.serviceCompleted = false;
    req.navigatingAt = null;
    req.enRouteAt = null;
    req.arrivedAt = null;
    req.workStartedAt = null;
    req.serviceCompletedAt = null;
    req.agreedPaymentAmount = null;
    req.agreedPaymentAmountSetAt = null;
    req.lastCancelReason = reason;
    req.lastCancelledBy = mechanicName;
    req.lastCancelledAt = DateTime.now();
    // Kept as an event: the job's own fields were just reset, and this is what
    // the mechanic's completion rate and seasonal score read.
    if (mechanicName != null) {
      MechanicPerformanceStore.instance.recordDropped(req, mechanicName, JobOutcomeKind.cancelledByMechanic);
    }

    // The client is waiting on someone who is no longer coming — that has to
    // reach the bell, not just change a card they may not be looking at. The
    // reason travels with the entry so it still reads correctly later.
    _addClientNotification(
      ClientNotificationKind.jobCancelled,
      req,
      mechanicName ?? 'Your mechanic',
      detail: reason,
    );

    // Chat intentionally NOT cleared — the job reverts to Pending (still
    // visible, still chattable there), not removed. See clientDeleteRequest
    // for the one action that actually clears chat.

    notifyListeners();
    return true;
  }

  /// AUTOMATIC — no role gate, because nobody performs this: it is the clock
  /// running out. Every job still unfinished at its
  /// [HelpRequest.completionDeadline] goes back to Pending, so it leaves the
  /// mechanic's Accepted list and is open to mechanics again, and is stamped
  /// [HelpRequest.expiredAt] / [HelpRequest.expiredByMechanic] so the client's
  /// Jobs screen can tell them the mechanic ran out of time. A job the
  /// mechanic has actually started (Work in Progress onwards) is never
  /// touched — the countdown that drives this stops the moment work begins,
  /// so there is no expiry running behind the hidden timer.
  ///
  /// Safe to call as often as you like — a job it has already dealt with is
  /// no longer `matched`, so it is skipped. Returns how many expired, and
  /// only notifies when something actually did.
  /// Tells the client, once, about every accepted job whose quoted ETA has
  /// run out with the mechanic still not there.
  ///
  /// The clock starts at [HelpRequest.matchedAt] — the moment the quote was
  /// accepted — and stops the instant the mechanic marks themselves arrived,
  /// so a mechanic who makes it on time is never reported late. Safe to call
  /// as often as you like: [HelpRequest.etaPassedNotifiedAt] makes it fire
  /// once per acceptance. Returns how many clients were notified.
  int notifyLateArrivals([DateTime? now]) {
    var raised = 0;
    for (final req in _requests) {
      if (req.etaPassedNotifiedAt != null) continue;
      final quote = acceptedQuoteFor(req.id);
      if (!arrivalIsOverdue(req, quote, now)) continue;
      req.etaPassedNotifiedAt = now ?? DateTime.now();
      _addClientNotification(ClientNotificationKind.etaPassed, req, quote!.mechanicName);
      raised++;
    }
    if (raised > 0) notifyListeners();
    return raised;
  }

  int expireOverdueJobs([DateTime? now]) {
    var expired = 0;
    for (final req in _requests) {
      if (_expireIfOverdue(req, now)) expired++;
    }
    if (expired > 0) notifyListeners();
    return expired;
  }

  bool _expireIfOverdue(HelpRequest req, [DateTime? now]) {
    if (!req.deadlinePassed(now)) return false;

    final mechanicName = acceptedQuoteFor(req.id)?.mechanicName;
    if (mechanicName != null) {
      MechanicPerformanceStore.instance.recordDropped(req, mechanicName, JobOutcomeKind.expired, now: now);
    }

    if (req.isEmergency) {
      // An emergency "quote" is just the accept record (there is no quoting
      // step), so it goes with the mechanic who let the window lapse —
      // otherwise the client would be offered it as a real quote to accept.
      _allQuotes.removeWhere((q) => q.requestId == req.id && q.mechanicName == mechanicName);
    } else {
      for (final q in _quoteRecordsFor(req.id)) {
        q.accepted = false;
      }
    }

    req.status = RequestStatus.pending;
    req.matchedAt = null;
    req.etaPassedNotifiedAt = null;
    req.navigating = false;
    req.enRoute = false;
    req.arrived = false;
    req.workStarted = false;
    req.serviceCompleted = false;
    req.navigatingAt = null;
    req.enRouteAt = null;
    req.arrivedAt = null;
    req.workStartedAt = null;
    req.serviceCompletedAt = null;
    req.agreedPaymentAmount = null;
    req.agreedPaymentAmountSetAt = null;

    final at = now ?? DateTime.now();
    req.expiredAt = at;
    req.expiredByMechanic = mechanicName;
    req.lastCancelReason = 'Did not complete the job within the allowed time.';
    req.lastCancelledBy = mechanicName;
    req.lastCancelledAt = at;

    // Chat intentionally NOT cleared — the request is still alive and still
    // chattable, exactly as after mechanicCancelJob.
    return true;
  }

  /// CLIENT action only — the ONLY way payment (and therefore the job) can
  /// ever be marked complete. The client is charged
  /// [clientTotalPaymentAmount] — never anything parsed from a scanned or
  /// pasted code, which could be stale.
  ///
  /// The split is settled here and only here: the mechanic's
  /// [effectivePaymentAmount] drives their payout and the client's loyalty
  /// points exactly as before, and the payment is reported to
  /// [PlatformRevenueApi.reportCompletedPayment] as ONGO revenue — the Admin
  /// income screens that read it live in the console website. A job can only
  /// be paid once (the paymentCompleted guard below), so the payment can never
  /// be booked twice.
  /// [payFeeWithPoints] spends the client's points on the job's priority fee
  /// instead of charging it, at 1 pt = ₱1. Ignored when the job carries no
  /// fee, and refused when the balance will not cover it — see
  /// [canPayFeeWithPoints], which is what the checkout screen offers on.
  double? clientConfirmPayment(String requestId, {bool payFeeWithPoints = false}) {
    if (AppSession.instance.currentRole != AppRole.client) {
      throw StateError('Only the Client UI can confirm a payment.');
    }
    final req = requestFor(requestId);
    if (req == null) return null;
    if (!req.serviceCompleted) return null;
    if (req.paymentCompleted) return null;

    final quote = acceptedQuoteFor(requestId);
    final amount = effectivePaymentAmount(req, quote);
    if (amount == null) return null;

    // Both awards come from the configured rules, never from a number written
    // here — an admin changing a rate in the console changes what this pays
    // out, with nothing in this method to update.
    final policy = PointsPolicyStore.instance.current;
    final points = policy.pointsFor(req.urgency);
    // The mechanic's multiplier as it stood BEFORE this job counted — rank,
    // and while the leaderboard is live their seasonal placement, are earned
    // on what was already done, not on the job being paid. Held to the
    // configured cap.
    final leaderboard = LeaderboardStore.instance;
    final multiplier =
        quote == null ? PointsMultiplier.none : leaderboard.multiplierFor(quote.mechanicName);
    final seasonId = leaderboard.activeSeason?.id;

    req.paymentCompleted = true;
    req.paymentCompletedAt = DateTime.now();
    // The mechanic earns what the client earns for the urgency, multiplied —
    // never scaled by the size of the payout.
    req.pointsAwarded = multiplier.apply(points);
    req.pointsMultiplier = multiplier.total;
    // The payment record. Stamped once, here, from the amount actually
    // charged — history reads this rather than re-deriving from the quote.
    req.amountPaid = amount;
    req.status = RequestStatus.completed;
    req.completedAt = req.paymentCompletedAt;

    // The priority fee, settled before it is booked: points cover it or the
    // client is charged it, never both.
    final fee = req.platformFee;
    if (fee > 0) {
      req.platformFeeCharged = fee;
      if (payFeeWithPoints) {
        final spent = PointsWalletStore.instance.debit(
          owner: req.clientName,
          kind: PointsEntryKind.clientPaidSurcharge,
          points: pointsForPesos(fee),
          note: '${req.urgency} priority fee · ${req.problem}',
          pesos: fee,
        );
        // Only recorded when the debit actually went through; a short balance
        // leaves the fee charged as normal rather than quietly waived.
        if (spent != null) req.feePaidWithPoints = pointsForPesos(fee);
      }
    }
    // Every successful payment is reported, fee or no fee: the fee is ONGO's
    // revenue, and the payment itself is one Admin transaction either way.
    //
    // Not awaited, and deliberately: the client has paid, the job is complete,
    // and none of that is contingent on the console hearing about it. The
    // report is idempotent on the request id, so the API client re-sends it
    // after a network failure; one that still fails has been logged with the
    // server's requestId and must not surface as a crash here.
    unawaited(MobileBackend.instance.revenue
        .reportCompletedPayment(
          CompletedPaymentReport(
            requestId: req.id,
            platformFee: fee,
            paidAt: req.paymentCompletedAt!,
            urgency: RevenueUrgency.fromJobUrgency(req.urgency),
          ),
        )
        .catchError((Object _) {}));

    if (quote != null) {
      MechanicNotificationStore.instance.add(
        kind: MechanicNotificationKind.paymentReceived,
        mechanicName: quote.mechanicName,
        clientName: req.clientName,
        // The mechanic's payout, not the client's total — the priority fee is
        // ONGO's cut and never reaches them.
        detail: '${req.problem} · ₱${amount.toStringAsFixed(0)}',
        requestId: req.id,
      );
    }

    // The client's reward for the job, and the mechanic's for being paid for
    // it. Both land in the one ledger the balances are read from.
    PointsWalletStore.instance.credit(
      owner: req.clientName,
      kind: PointsEntryKind.clientJobCompleted,
      points: points,
      note: '${req.urgency} job · ${req.problem}',
    );
    if (quote != null) {
      PointsWalletStore.instance.credit(
        owner: quote.mechanicName,
        kind: PointsEntryKind.mechanicJobCompleted,
        points: req.pointsAwarded ?? 0,
        note: req.problem,
      );
      // Why those points: base × rank × seasonal, capped — once per job.
      PointTransactionStore.instance.record(PointTransaction.forJob(
        jobId: req.id,
        mechanicId: quote.mechanicName,
        basePoints: points,
        multiplier: multiplier,
        at: req.paymentCompletedAt!,
        seasonId: seasonId,
      ));
      // The raw records the mechanic's reputation, rank and seasonal score
      // are calculated from — and the evaluation the client now owes this job.
      MechanicPerformanceStore.instance.recordCompleted(req, quote);
      JobEvaluationStore.instance.requireFor(req, quote);
    }

    // Chat intentionally NOT cleared — see clientDeleteRequest.

    notifyListeners();
    return points;
  }

  /// Whether [requestId]'s priority fee could be paid with the client's
  /// points right now. False when there is no fee to pay.
  bool canPayFeeWithPoints(String requestId) {
    final req = requestFor(requestId);
    if (req == null || req.platformFee <= 0) return false;
    return PointsWalletStore.instance
        .canAfford(req.clientName, pointsForPesos(req.platformFee));
  }

  // ---------------------------------------------------------------------
  // Mechanic financials
  // ---------------------------------------------------------------------

  /// The mechanic's payout — [effectivePaymentAmount] only. Priority fees are
  /// deliberately excluded: they are ONGO revenue and were never part of what
  /// the mechanic quoted or agreed to.
  double totalEarningsFor(String mechanicName) {
    double sum = 0;
    for (final req in completedJobsFor(mechanicName)) {
      final quote = acceptedQuoteFor(req.id);
      // Same rule the client's history uses, so a job is worth the same
      // figure on both sides.
      sum += settledPaymentAmount(req, quote) ?? 0;
    }
    return sum;
  }

  /// THE mechanic's Available Balance: what their jobs paid, plus what they
  /// have converted from points. The single definition every screen showing
  /// a balance reads, so one conversion moves it everywhere at once.
  ///
  /// Derived on every call, never stored — there is no copy for a screen to
  /// keep that could go stale. A screen showing it must listen to BOTH this
  /// store (jobs paid) and [PointsWalletStore] (conversions).
  double availableBalanceFor(String mechanicName) =>
      totalEarningsFor(mechanicName) +
      PointsWalletStore.instance.convertedPesosFor(mechanicName);

  /// Points this mechanic has earned across every job they finished — the
  /// lifetime figure the earnings history adds up to.
  ///
  /// NOT what they can spend: converting points to balance draws them down,
  /// and that is tracked in [PointsWalletStore]. Read the wallet's balance for
  /// anything the mechanic is about to spend.
  double totalPointsFor(String mechanicName) {
    double sum = 0;
    for (final req in completedJobsFor(mechanicName)) {
      sum += req.pointsAwarded ?? 0;
    }
    return sum;
  }

  void clear() {
    _requests.clear();
    _allQuotes.clear();
    _unseenCount = 0;
    _seenClientQuoteIds.clear();
    _seenEmergencyRequestIds.clear();
    _clientNotifications.clear();
    MechanicNotificationStore.instance.clear();
    notifyListeners();
  }
}