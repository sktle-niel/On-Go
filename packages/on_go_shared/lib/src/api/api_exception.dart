/// Why a call across the app boundary failed.
///
/// Deliberately transport-neutral: an implementation backed by HTTP maps
/// status codes onto these, and the local pre-backend implementations throw
/// the same kinds, so callers never have to know which one they hold.
enum ApiErrorKind {
  /// No network, DNS failure, timeout — the request never got an answer.
  unreachable,

  /// The caller is not signed in, or the session expired.
  unauthenticated,

  /// Signed in, but not allowed to do this.
  forbidden,

  /// The thing being addressed does not exist.
  notFound,

  /// The request was well-formed but the server refused it (validation, a
  /// duplicate submission, a state that no longer allows the action).
  rejected,

  /// This surface cannot do this at all — the operation belongs to the other
  /// front end, or needs a backend that is not connected yet. A route the
  /// server answers `501 not_implemented` lands here too: see
  /// [ApiException.isNotImplemented].
  unsupported,

  /// Anything else.
  unknown,
}

/// The stable `error.code` values the On Go API sends. Application logic
/// switches on these, never on a message.
abstract final class ApiErrorCodes {
  static const String badRequest = 'bad_request';
  static const String validationFailed = 'validation_failed';
  static const String invalidResetCode = 'invalid_reset_code';
  static const String unauthorized = 'unauthorized';
  static const String invalidCredentials = 'invalid_credentials';
  static const String tokenExpired = 'token_expired';
  static const String tokenInvalid = 'token_invalid';
  static const String forbidden = 'forbidden';
  static const String accountInactive = 'account_inactive';
  static const String wrongSurface = 'wrong_surface';
  static const String notFound = 'not_found';
  static const String conflict = 'conflict';
  static const String payloadTooLarge = 'payload_too_large';
  static const String accountLocked = 'account_locked';
  static const String rateLimited = 'rate_limited';
  static const String internalError = 'internal_error';
  static const String notImplemented = 'not_implemented';
  static const String serviceUnavailable = 'service_unavailable';
}

/// One field a request body failed validation on — an entry of
/// `error.details` on `validation_failed`.
class ApiFieldError {
  /// A JSON pointer into the request body, e.g. `/email`.
  final String path;
  final String message;

  const ApiFieldError({required this.path, required this.message});

  /// The top-level field [path] points at — `email` for `/email` — or '' for
  /// an error about the body as a whole.
  String get field {
    final trimmed = path.startsWith('/') ? path.substring(1) : path;
    final slash = trimmed.indexOf('/');
    return slash < 0 ? trimmed : trimmed.substring(0, slash);
  }

  @override
  String toString() => '$path: $message';
}

/// The single error type every API in this package throws.
class ApiException implements Exception {
  final ApiErrorKind kind;

  /// Safe to show to a person. From a server response this is
  /// `error.message` verbatim.
  final String message;

  /// The underlying failure, when there was one.
  final Object? cause;

  /// The server's stable `error.code`, when the failure came from the API.
  /// Null for local implementations and for failures that never reached it.
  final String? code;

  /// The HTTP status, when there was a response.
  final int? statusCode;

  /// Field-level detail, present on `validation_failed`.
  final List<ApiFieldError> details;

  /// The server's id for this request. Log it, or show it when reporting a
  /// problem — it links to the server log.
  final String? requestId;

  const ApiException(
    this.kind,
    this.message, {
    this.cause,
    this.code,
    this.statusCode,
    this.details = const [],
    this.requestId,
  });

  /// The operation is not available on this surface yet — thrown by the local
  /// implementations for the calls that genuinely need the backend.
  const ApiException.unsupported(String reason)
      : kind = ApiErrorKind.unsupported,
        message = reason,
        cause = null,
        code = null,
        statusCode = null,
        details = const [],
        requestId = null;

  /// The route exists in the contract but the backend has not built it yet
  /// (`501 not_implemented`). An unfinished feature, not a server fault: the
  /// UI should say so and carry on.
  bool get isNotImplemented => code == ApiErrorCodes.notImplemented;

  /// [details] keyed by top-level field, first message per field — what a
  /// form shows under each input.
  Map<String, String> get fieldErrors {
    final errors = <String, String>{};
    for (final detail in details) {
      errors.putIfAbsent(detail.field, () => detail.message);
    }
    return errors;
  }

  @override
  String toString() {
    final extra = [
      if (statusCode != null) '$statusCode',
      if (code != null) code!,
      if (requestId != null) 'requestId=$requestId',
    ].join(' ');
    return 'ApiException(${kind.name}${extra.isEmpty ? '' : ' $extra'}): $message';
  }
}
