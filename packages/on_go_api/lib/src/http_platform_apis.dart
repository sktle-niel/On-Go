import 'dart:async';

import 'package:on_go_shared/on_go_shared.dart';

import 'api_client.dart';
import 'event_socket.dart';
import 'remote_value.dart';

/// [PointsPolicyApi] over `/api/v1/platform/points-policy`. Live.
///
/// [fetch] is public — the mobile app reads the rules before anyone signs in.
/// [watch] follows `points_policy.updated` while the event socket is
/// connected, and re-fetches on every reconnect.
class HttpPointsPolicyApi implements PointsPolicyApi {
  HttpPointsPolicyApi(this._client, {EventSocket? events}) {
    _live = RemoteValue<PointsPolicy>(
      fetch: fetch,
      events: events,
      eventName: ApiEventNames.pointsPolicyUpdated,
      fromEvent: (event) => event.data.isEmpty ? null : PointsPolicy.fromJson(event.data),
    );
  }

  final ApiClient _client;
  late final RemoteValue<PointsPolicy> _live;

  @override
  Future<PointsPolicy> fetch() async =>
      PointsPolicy.fromJson(responseObject(await _client.get(ApiEndpoints.pointsPolicy)));

  @override
  Stream<PointsPolicy> watch() => _live.watch();

  /// Admin only; anyone else gets [ApiErrorKind.forbidden].
  @override
  Future<PointsPolicy> update(PointsPolicy policy) async {
    final stored = PointsPolicy.fromJson(responseObject(await _client.put(
      ApiEndpoints.pointsPolicy,
      body: policy.toJson(),
      authenticated: true,
    )));
    _live.set(stored);
    return stored;
  }
}

/// [PlatformAppearanceApi] over `/api/v1/platform/appearance`.
///
/// [fetch] is live. [publishBackground] and [clearBackground] are in the
/// contract but answer `501 not_implemented` until object storage lands
/// (Step 7); they are sent anyway, so they start working the day the server
/// does, and until then fail with an [ApiException] whose
/// [ApiException.isNotImplemented] is true.
class HttpPlatformAppearanceApi implements PlatformAppearanceApi {
  HttpPlatformAppearanceApi(this._client, {EventSocket? events}) {
    _live = RemoteValue<PlatformAppearance>(
      fetch: fetch,
      events: events,
      // Planned event: until the server sends it, reconnects re-fetch.
      eventName: ApiEventNames.platformAppearanceUpdated,
      fromEvent: (event) => event.data.isEmpty ? null : PlatformAppearance.fromJson(event.data),
    );
  }

  final ApiClient _client;
  late final RemoteValue<PlatformAppearance> _live;

  @override
  Future<PlatformAppearance> fetch() async =>
      PlatformAppearance.fromJson(responseObject(await _client.get(ApiEndpoints.appearance)));

  @override
  Stream<PlatformAppearance> watch() => _live.watch();

  @override
  Future<PlatformAppearance> publishBackground({
    required List<int> bytes,
    required String fileName,
  }) async {
    final stored = PlatformAppearance.fromJson(responseObject(await _client.upload(
      'PUT',
      ApiEndpoints.appearance,
      ApiUpload(
        field: 'file',
        bytes: bytes,
        fileName: fileName,
        contentType: imageContentTypeFor(fileName),
      ),
    )));
    _live.set(stored);
    return stored;
  }

  @override
  Future<PlatformAppearance> clearBackground() async {
    final stored = PlatformAppearance.fromJson(
      responseObject(await _client.delete(ApiEndpoints.appearance, authenticated: true)),
    );
    _live.set(stored);
    return stored;
  }

  /// The content type for the image formats the API accepts (JPEG, PNG,
  /// WebP), from the file name; null for anything else.
  static String? imageContentTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return null;
  }
}

/// [PlatformRevenueApi] over `/api/v1/payments` and `/api/v1/revenue/summary`.
/// Live.
class HttpPlatformRevenueApi implements PlatformRevenueApi {
  HttpPlatformRevenueApi(
    this._client, {
    EventSocket? events,
    Duration pollInterval = const Duration(seconds: 60),
    List<Duration> retryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 10),
      Duration(seconds: 30),
    ],
    Future<void> Function(Duration delay)? wait,
  })  : _retryDelays = retryDelays,
        _wait = wait ?? Future<void>.delayed {
    // No revenue event exists; the summary polls while it is watched.
    _summary = RemoteValue<PlatformRevenueSummary>(
      fetch: fetchSummary,
      events: events,
      pollInterval: pollInterval,
    );
  }

  final ApiClient _client;
  final List<Duration> _retryDelays;
  final Future<void> Function(Duration delay) _wait;
  late final RemoteValue<PlatformRevenueSummary> _summary;

  /// Idempotent per [CompletedPaymentReport.requestId] on the server, so a
  /// payment that failed to report for want of a network is re-sent: up to
  /// [_retryDelays] more times, for a failure that could pass (no network, a
  /// 5xx, rate limiting). A refusal is not retried.
  @override
  Future<void> reportCompletedPayment(CompletedPaymentReport payment) async {
    var attempt = 0;
    while (true) {
      try {
        await _client.post(ApiEndpoints.payments, body: payment.toJson(), authenticated: true);
        return;
      } on ApiException catch (error) {
        if (!_worthRetrying(error) || attempt >= _retryDelays.length) rethrow;
        await _wait(_retryDelays[attempt++]);
      }
    }
  }

  static bool _worthRetrying(ApiException error) =>
      error.kind == ApiErrorKind.unreachable ||
      error.statusCode == 500 ||
      error.statusCode == 503 ||
      error.code == ApiErrorCodes.rateLimited;

  /// Admin only.
  @override
  Future<PlatformRevenueSummary> fetchSummary() async => PlatformRevenueSummary.fromJson(
        responseObject(await _client.get(ApiEndpoints.revenueSummary, authenticated: true)),
      );

  @override
  Stream<PlatformRevenueSummary> watchSummary() => _summary.watch();
}
