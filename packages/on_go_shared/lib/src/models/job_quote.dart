import 'json.dart';

/// A mechanic's offer on a Normal or Urgent request.
///
/// An Emergency is not quoted: the first mechanic to accept it takes it, and
/// the server records that accept as a quote with [accepted] set. Its price is
/// not the job's price; that is agreed in person and lands on the request as
/// `ServiceRequest.agreedPaymentAmount`.
class JobQuote {
  final String id;
  final String requestId;
  final String mechanicId;
  final String mechanicName;

  /// The mechanic's price for the job, in pesos.
  final double price;

  /// Promised time to reach the client, in minutes. Once the quote is
  /// accepted, the client's cancel lock counts down against it.
  final int etaMinutes;

  /// The mechanic's rating when the quote was sent.
  final double rating;

  final bool accepted;
  final DateTime? withdrawnAt;
  final DateTime? rejectedAt;
  final DateTime createdAt;

  const JobQuote({
    required this.id,
    required this.requestId,
    required this.mechanicId,
    required this.mechanicName,
    required this.price,
    required this.etaMinutes,
    required this.createdAt,
    this.rating = 0,
    this.accepted = false,
    this.withdrawnAt,
    this.rejectedAt,
  });

  /// Still on the table: not accepted, withdrawn or rejected.
  bool get isLive => !accepted && withdrawnAt == null && rejectedAt == null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'requestId': requestId,
        'mechanicId': mechanicId,
        'mechanicName': mechanicName,
        'price': price,
        'etaMinutes': etaMinutes,
        'rating': rating,
        'accepted': accepted,
        'withdrawnAt': writeDateOrNull(withdrawnAt),
        'rejectedAt': writeDateOrNull(rejectedAt),
        'createdAt': writeDate(createdAt),
      };

  factory JobQuote.fromJson(Map<String, dynamic> json) => JobQuote(
        id: readString(json['id']),
        requestId: readString(json['requestId']),
        mechanicId: readString(json['mechanicId']),
        mechanicName: readString(json['mechanicName']),
        price: readDouble(json['price']),
        etaMinutes: readInt(json['etaMinutes']),
        rating: readDouble(json['rating']),
        accepted: readBool(json['accepted']),
        withdrawnAt: readDateOrNull(json['withdrawnAt']),
        rejectedAt: readDateOrNull(json['rejectedAt']),
        createdAt: readDate(json['createdAt']),
      );
}

/// What a mechanic sends to quote a request.
class QuoteSubmission {
  /// Pesos, zero or more.
  final double price;

  /// Minutes to reach the client. The server refuses an ETA past the
  /// urgency's completion window.
  final int etaMinutes;

  const QuoteSubmission({required this.price, required this.etaMinutes});

  Map<String, dynamic> toJson() => {'price': price, 'etaMinutes': etaMinutes};
}
