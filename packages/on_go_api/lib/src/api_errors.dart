import 'dart:convert';

import 'package:on_go_shared/on_go_shared.dart';

/// Shown when a request never got an answer.
const String unreachableMessage =
    "Can't reach On Go right now. Check your connection and try again.";

/// Shown when a request got no answer in time.
const String timeoutMessage =
    'On Go took too long to answer. Check your connection and try again.';

/// The [ApiErrorKind] for a response, from its status and `error.code`.
///
/// The mapping the integration guide gives: 401 is always
/// [ApiErrorKind.unauthenticated]; 403 [ApiErrorKind.forbidden] (including
/// `account_inactive` and `wrong_surface`); 400/409/413/423/429
/// [ApiErrorKind.rejected]; 501 [ApiErrorKind.unsupported]; 500, 503 and
/// anything unexpected [ApiErrorKind.unknown].
ApiErrorKind apiErrorKindFor(int statusCode, String? code) {
  if (statusCode == 501 || code == ApiErrorCodes.notImplemented) {
    return ApiErrorKind.unsupported;
  }
  return switch (statusCode) {
    401 => ApiErrorKind.unauthenticated,
    403 => ApiErrorKind.forbidden,
    404 => ApiErrorKind.notFound,
    400 || 409 || 413 || 423 || 429 => ApiErrorKind.rejected,
    _ => ApiErrorKind.unknown,
  };
}

/// Reads the error envelope every failing route sends —
/// `{ "error": { code, message, details?, requestId? } }` — into an
/// [ApiException]. A body that is not the envelope (a proxy's HTML page, say)
/// still becomes an exception with the status and a plain message.
ApiException apiExceptionFromResponse(int statusCode, String body) {
  Map<String, dynamic>? error;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map && decoded['error'] is Map) {
      error = Map<String, dynamic>.from(decoded['error'] as Map);
    }
  } on FormatException {
    // Not JSON; fall through to the status alone.
  }

  if (error == null) {
    return ApiException(
      apiErrorKindFor(statusCode, null),
      fallbackMessageFor(statusCode),
      statusCode: statusCode,
    );
  }

  final code = _stringOrNull(error['code']);
  final rawDetails = error['details'];
  return ApiException(
    apiErrorKindFor(statusCode, code),
    _stringOrNull(error['message']) ?? fallbackMessageFor(statusCode),
    code: code,
    statusCode: statusCode,
    requestId: _stringOrNull(error['requestId']),
    details: rawDetails is List
        ? [
            for (final item in rawDetails.whereType<Map>())
              ApiFieldError(
                path: '${item['path'] ?? ''}',
                message: '${item['message'] ?? ''}',
              ),
          ]
        : const [],
    // `details` is a list of field errors on validation_failed, and an object
    // on a refusal that carries a fact — a cancel under the ETA lock carries
    // `cancellableAt`. Dropping the object form would lose that.
    info: rawDetails is Map ? Map<String, dynamic>.from(rawDetails) : const {},
  );
}

/// Words for a status whose body carried no message of its own.
String fallbackMessageFor(int statusCode) => switch (statusCode) {
      401 => 'Please sign in again.',
      403 => "You don't have permission to do that.",
      404 => "That couldn't be found.",
      413 => 'That is too large to send.',
      423 => 'This account is locked for now. Try again later.',
      429 => 'Too many attempts. Please wait a moment and try again.',
      501 => "This isn't available yet.",
      503 => 'On Go is busy right now. Please try again shortly.',
      >= 500 => 'Something went wrong on the On Go server. Please try again later.',
      _ => "The request couldn't be completed.",
    };

String? _stringOrNull(Object? value) => value is String && value.isNotEmpty ? value : null;
