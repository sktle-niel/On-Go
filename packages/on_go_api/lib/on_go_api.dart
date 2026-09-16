/// The On Go API client, shared by the mobile app and the admin console.
///
/// `package:on_go_shared` says what the two front ends exchange; this package
/// is how it travels — HTTP for requests, one WebSocket for live events — as
/// implementations of the same interfaces the local services implement.
///
/// Start at [OnGoApi]. See README.md for what is live and what still answers
/// `501 not_implemented`.
library;

export 'src/api_client.dart';
export 'src/api_environment.dart';
export 'src/api_errors.dart';
export 'src/api_session.dart';
export 'src/auth_session_payload.dart';
export 'src/event_socket.dart';
export 'src/http_auth_api.dart';
export 'src/http_jobs_api.dart';
export 'src/http_pending_apis.dart';
export 'src/http_platform_apis.dart';
export 'src/on_go_api_connection.dart';
export 'src/refresh_token_store.dart';
export 'src/remote_value.dart';
