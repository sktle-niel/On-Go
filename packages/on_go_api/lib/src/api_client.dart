import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:on_go_shared/on_go_shared.dart';

import 'api_environment.dart';
import 'api_errors.dart';
import 'api_session.dart';

/// Called with every failed request, so an app can log the server's
/// `requestId` alongside what it was doing.
typedef ApiErrorLogger = void Function(String method, String path, ApiException error);

/// One file for a multipart request.
class ApiUpload {
  const ApiUpload({
    required this.field,
    required this.bytes,
    required this.fileName,
    this.contentType,
  });

  final String field;
  final List<int> bytes;
  final String fileName;

  /// e.g. `image/png`. Sent as the part's content type when given.
  final String? contentType;
}

/// The one place the apps make HTTP requests.
///
/// * Builds URLs from [ApiEnvironment]; tokens only ever go in the
///   `Authorization` header.
/// * On `401 token_expired` it refreshes the session once and retries the
///   request once. A second failure is returned, never retried again.
/// * On `token_invalid` or `account_inactive` it ends the session.
/// * Turns every failure — no network, a timeout, an error envelope — into an
///   [ApiException].
class ApiClient {
  ApiClient({
    required this.environment,
    required this.session,
    http.Client? httpClient,
    this.logger,
  }) : _http = httpClient ?? http.Client();

  final ApiEnvironment environment;
  final ApiSession session;
  final ApiErrorLogger? logger;
  final http.Client _http;

  Future<Object?> get(String path, {Map<String, String>? query, bool authenticated = false}) =>
      send('GET', path, query: query, authenticated: authenticated);

  Future<Object?> post(String path, {Object? body, bool authenticated = false, String? bearerToken}) =>
      send('POST', path, body: body, authenticated: authenticated, bearerToken: bearerToken);

  Future<Object?> put(String path, {Object? body, bool authenticated = false}) =>
      send('PUT', path, body: body, authenticated: authenticated);

  Future<Object?> patch(String path, {Object? body, bool authenticated = false}) =>
      send('PATCH', path, body: body, authenticated: authenticated);

  Future<Object?> delete(String path, {Map<String, String>? query, bool authenticated = false}) =>
      send('DELETE', path, query: query, authenticated: authenticated);

  /// Sends a JSON request and returns the decoded body (null for 204).
  ///
  /// [authenticated] sends the session's access token and handles its expiry.
  /// [bearerToken] sends that token instead, as-is, with no refresh — for
  /// sign-out, which runs after the session has already been cleared.
  Future<Object?> send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool authenticated = false,
    String? bearerToken,
  }) {
    final uri = environment.uri(path, query);
    return _call(method, path, authenticated, bearerToken, () {
      final request = http.Request(method, uri)..headers['Accept'] = 'application/json';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json; charset=utf-8';
        request.bodyBytes = utf8.encode(jsonEncode(body));
      }
      return request;
    });
  }

  /// Sends a multipart request carrying [file].
  Future<Object?> upload(String method, String path, ApiUpload file, {bool authenticated = true}) {
    final uri = environment.uri(path);
    return _call(method, path, authenticated, null, () {
      final contentType = file.contentType;
      return http.MultipartRequest(method, uri)
        ..headers['Accept'] = 'application/json'
        ..files.add(http.MultipartFile.fromBytes(
          file.field,
          file.bytes,
          filename: file.fileName,
          contentType: contentType == null ? null : MediaType.parse(contentType),
        ));
    });
  }

  Future<Object?> _call(
    String method,
    String path,
    bool authenticated,
    String? bearerToken,
    http.BaseRequest Function() build,
  ) async {
    try {
      if (bearerToken != null) {
        return await _result(await _perform(build, bearerToken), authenticated: false);
      }
      if (!authenticated) {
        return await _result(await _perform(build, null), authenticated: false);
      }
      return await _authorized(build);
    } on ApiException catch (error) {
      logger?.call(method, path, error);
      rethrow;
    }
  }

  Future<Object?> _authorized(http.BaseRequest Function() build) async {
    final token = session.accessToken;
    if (token == null) {
      throw const ApiException(
        ApiErrorKind.unauthenticated,
        'Please sign in to continue.',
        code: ApiErrorCodes.unauthorized,
      );
    }

    var response = await _perform(build, token);
    if (response.statusCode == 401 && _codeOf(response) == ApiErrorCodes.tokenExpired) {
      // Another request may have refreshed while this one was out; only
      // refresh if the token this one used is still the current one.
      if (session.accessToken == token && !await session.refresh()) {
        throw apiExceptionFromResponse(response.statusCode, _text(response));
      }
      final fresh = session.accessToken;
      if (fresh == null) throw apiExceptionFromResponse(response.statusCode, _text(response));
      // Once. Whatever this answers is the answer.
      response = await _perform(build, fresh);
    }
    return _result(response, authenticated: true);
  }

  Future<http.Response> _perform(http.BaseRequest Function() build, String? token) async {
    final request = build();
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    try {
      final streamed = await _http.send(request).timeout(environment.requestTimeout);
      return await http.Response.fromStream(streamed).timeout(environment.requestTimeout);
    } on TimeoutException catch (error) {
      throw ApiException(ApiErrorKind.unreachable, timeoutMessage, cause: error);
    } on ApiException {
      rethrow;
    } on Exception catch (error) {
      // http.ClientException everywhere, SocketException/HandshakeException on
      // dart:io: the request never got an answer.
      throw ApiException(ApiErrorKind.unreachable, unreachableMessage, cause: error);
    }
  }

  Future<Object?> _result(http.Response response, {required bool authenticated}) async {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return _decode(response);

    final error = apiExceptionFromResponse(status, _text(response));
    if (authenticated) {
      switch (error.code) {
        case ApiErrorCodes.tokenInvalid:
          await session.end(SessionEndReason.invalid, message: error.message);
        case ApiErrorCodes.accountInactive:
          await session.end(SessionEndReason.accountInactive, message: error.message);
        case ApiErrorCodes.forbidden:
          session.reportForbidden();
      }
    }
    throw error;
  }

  Object? _decode(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(_text(response));
    } on FormatException catch (error) {
      throw ApiException(
        ApiErrorKind.unknown,
        'The On Go server sent a response this app could not read.',
        statusCode: response.statusCode,
        cause: error,
      );
    }
  }

  /// The body as UTF-8 whatever the headers say — `package:http` would fall
  /// back to Latin-1 for a JSON response that names no charset.
  static String _text(http.Response response) => utf8.decode(response.bodyBytes, allowMalformed: true);

  static String? _codeOf(http.Response response) {
    try {
      final decoded = jsonDecode(_text(response));
      if (decoded is Map && decoded['error'] is Map) {
        final code = (decoded['error'] as Map)['code'];
        return code is String ? code : null;
      }
    } on FormatException {
      // Not the envelope.
    }
    return null;
  }

  void close() => _http.close();
}

/// A response body that must be an object.
Map<String, dynamic> responseObject(Object? json) {
  if (json is Map) return Map<String, dynamic>.from(json);
  throw const ApiException(
    ApiErrorKind.unknown,
    'The On Go server sent a response this app could not read.',
  );
}

/// A response body that must be a list of objects.
List<Map<String, dynamic>> responseList(Object? json) {
  if (json is List) {
    return [for (final item in json.whereType<Map>()) Map<String, dynamic>.from(item)];
  }
  throw const ApiException(
    ApiErrorKind.unknown,
    'The On Go server sent a response this app could not read.',
  );
}
