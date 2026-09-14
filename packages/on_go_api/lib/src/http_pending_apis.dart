import 'package:on_go_shared/on_go_shared.dart';

import 'api_client.dart';
import 'event_socket.dart';
import 'remote_value.dart';

// The domains below are in the API contract — routes, guards and body shapes
// are final — but the server answers `501 not_implemented` until their backend
// steps land (verification: Step 5, moderators and the audit log: Step 6).
//
// They are built against the contract so an app can switch them on without
// touching a screen (see ApiFeatures). Until then every call fails with an
// ApiException whose isNotImplemented is true, and every watch* stream emits
// that error rather than inventing data.

/// [AccountVerificationApi] over `/api/v1/verification-requests` and
/// `/api/v1/moderation/activity`. Pending: Step 5.
class HttpAccountVerificationApi implements AccountVerificationApi {
  HttpAccountVerificationApi(
    this._client, {
    EventSocket? events,
    Duration pollInterval = const Duration(seconds: 60),
  })  : _events = events,
        _pollInterval = pollInterval {
    _queue = RemoteValue<List<AccountVerificationRequest>>(
      fetch: listRequests,
      events: events,
      eventName: ApiEventNames.verificationRequestUpdated,
      pollInterval: pollInterval,
    );
  }

  final ApiClient _client;
  final EventSocket? _events;
  final Duration _pollInterval;
  late final RemoteValue<List<AccountVerificationRequest>> _queue;

  @override
  Future<AccountVerificationRequest> submit(SubmitVerificationRequest request) async {
    final filed = AccountVerificationRequest.fromJson(responseObject(await _client.post(
      ApiEndpoints.verificationRequests,
      body: request.toJson(),
      authenticated: true,
    )));
    _queue.refreshQuietly(force: true);
    return filed;
  }

  @override
  Future<List<AccountVerificationRequest>> listRequests({
    ApprovalStatus? status,
    bool escalatedOnly = false,
    String? search,
  }) async {
    final json = await _client.get(
      ApiEndpoints.verificationRequests,
      query: {
        if (status != null) 'status': status.wireName,
        if (escalatedOnly) 'escalatedOnly': 'true',
        if (search != null && search.isNotEmpty) 'search': search,
      },
      authenticated: true,
    );
    return responseList(json).map(AccountVerificationRequest.fromJson).toList(growable: false);
  }

  @override
  Future<AccountVerificationRequest?> findRequest(String requestId) async {
    try {
      return AccountVerificationRequest.fromJson(responseObject(await _client.get(
        ApiEndpoints.verificationRequest(requestId),
        authenticated: true,
      )));
    } on ApiException catch (error) {
      if (error.kind == ApiErrorKind.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<AccountVerificationRequest> decide(String requestId, ModerationDecision decision) async {
    final decided = AccountVerificationRequest.fromJson(responseObject(await _client.post(
      ApiEndpoints.verificationDecision(requestId),
      body: decision.toJson(),
      authenticated: true,
    )));
    _queue.refreshQuietly(force: true);
    return decided;
  }

  @override
  Future<List<ModerationActivity>> listActivity({int limit = 50}) async {
    final json = await _client.get(
      ApiEndpoints.moderationActivity,
      query: {'limit': '$limit'},
      authenticated: true,
    );
    return responseList(json).map(ModerationActivity.fromJson).toList(growable: false);
  }

  @override
  Stream<AccountVerificationRequest?> watchRequest(String requestId) =>
      RemoteValue<AccountVerificationRequest?>(
        fetch: () => findRequest(requestId),
        events: _events,
        eventName: ApiEventNames.verificationRequestUpdated,
        matches: (event) => event.data['id'] == requestId,
        fromEvent: (event) => AccountVerificationRequest.fromJson(event.data),
        pollInterval: _pollInterval,
      ).watch();

  @override
  Stream<List<AccountVerificationRequest>> watchRequests() => _queue.watch();
}

/// [ModeratorDirectoryApi] over `/api/v1/moderators` and `/api/v1/audit-log`.
/// Admin only. Pending: Step 6.
class HttpModeratorDirectoryApi implements ModeratorDirectoryApi {
  HttpModeratorDirectoryApi(
    this._client, {
    EventSocket? events,
    Duration pollInterval = const Duration(seconds: 60),
  }) {
    _roster = RemoteValue<List<ModeratorAccount>>(
      fetch: listModerators,
      events: events,
      eventName: ApiEventNames.moderatorUpdated,
      pollInterval: pollInterval,
    );
    _audit = RemoteValue<List<AuditEntry>>(
      fetch: listAuditLog,
      events: events,
      // A roster change is what writes an audit entry.
      eventName: ApiEventNames.moderatorUpdated,
      pollInterval: pollInterval,
    );
  }

  final ApiClient _client;
  late final RemoteValue<List<ModeratorAccount>> _roster;
  late final RemoteValue<List<AuditEntry>> _audit;

  void _changed() {
    _roster.refreshQuietly(force: true);
    _audit.refreshQuietly(force: true);
  }

  @override
  Future<List<ModeratorAccount>> listModerators() async =>
      responseList(await _client.get(ApiEndpoints.moderators, authenticated: true))
          .map(ModeratorAccount.fromJson)
          .toList(growable: false);

  @override
  Stream<List<ModeratorAccount>> watchModerators() => _roster.watch();

  @override
  Future<ModeratorAccount> createModerator(CreateModeratorRequest request) async {
    final created = ModeratorAccount.fromJson(responseObject(await _client.post(
      ApiEndpoints.moderators,
      body: request.toJson(),
      authenticated: true,
    )));
    _changed();
    return created;
  }

  @override
  Future<void> removeModerator(String moderatorId, {String? reason}) async {
    await _client.delete(
      ApiEndpoints.moderator(moderatorId),
      query: {if (reason != null && reason.isNotEmpty) 'reason': reason},
      authenticated: true,
    );
    _changed();
  }

  @override
  Future<ModeratorAccount> updatePermissions(String moderatorId, ModeratorPermissions permissions) async {
    final updated = ModeratorAccount.fromJson(responseObject(await _client.put(
      ApiEndpoints.moderatorPermissions(moderatorId),
      body: permissions.toJson(),
      authenticated: true,
    )));
    _changed();
    return updated;
  }

  @override
  Future<ModeratorAccount> updateProfile(String moderatorId, {String? name, String? photoUrl}) async {
    final updated = ModeratorAccount.fromJson(responseObject(await _client.patch(
      ApiEndpoints.moderatorProfile(moderatorId),
      body: {
        if (name != null) 'name': name,
        if (photoUrl != null) 'photoUrl': photoUrl,
      },
      authenticated: true,
    )));
    _changed();
    return updated;
  }

  @override
  Future<List<AuditEntry>> listAuditLog() async =>
      responseList(await _client.get(ApiEndpoints.auditLog, authenticated: true))
          .map(AuditEntry.fromJson)
          .toList(growable: false);

  @override
  Stream<List<AuditEntry>> watchAuditLog() => _audit.watch();
}
