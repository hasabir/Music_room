import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'client_metadata.dart';

/// Thrown when the backend returns a non-2xx response, or the response body
/// can't be parsed as expected.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.fieldErrors, this.code});

  final int statusCode;
  final String message;

  /// Field-level validation errors, e.g. `{"email": ["already in use"]}`,
  /// as returned by Django REST Framework serializers.
  final Map<String, dynamic>? fieldErrors;

  /// Machine-readable error code the backend includes on specific
  /// responses (e.g. `"suggestion_limit_reached"`, `"vote_limit_reached"`,
  /// `"public_playlist_requires_premium"` — see
  /// docs/SUBSCRIPTION_BONUS.md) — `null` for the many error responses
  /// that don't set one. Lets callers branch on a stable identifier
  /// instead of parsing [message] text.
  final String? code;

  @override
  String toString() => 'ApiException($statusCode, $message)';
}

/// Thin wrapper around [http.Client] for JSON APIs.
///
/// Centralizes request/response handling (encoding, status checks, error
/// parsing) so individual features don't each reimplement it.
class ApiClient {
  ApiClient({http.Client? httpClient})
    : _httpClient = MetadataClient(httpClient ?? http.Client());

  final http.Client _httpClient;

  static const _jsonHeaders = {'Content-Type': 'application/json'};
  static const _timeout = Duration(seconds: 15);

  Future<Map<String, dynamic>> post(
    Uri uri, {
    required Map<String, dynamic> body,
    String? accessToken,
  }) async {
    late final http.Response response;
    try {
      response = await _httpClient
          .post(
            uri,
            headers: {
              ..._jsonHeaders,
              if (accessToken != null) 'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw ApiException(0, 'The request timed out. Please try again.');
    } catch (error) {
      throw ApiException(
        0,
        'Unable to connect to the server. Please try again.',
      );
    }

    return _decode(response);
  }

  /// PATCHes a single file field as `multipart/form-data`, for endpoints
  /// with an `ImageField`/`FileField` (JSON can't carry binary data).
  ///
  /// Takes raw [fileBytes] rather than a file path: `http.MultipartFile
  /// .fromPath` reads through `dart:io`, which has no web implementation
  /// and throws `UnsupportedError` there unconditionally — `fromBytes` has
  /// no such platform split, so callers read bytes via `XFile.readAsBytes()`
  /// (works on every platform image_picker supports, including web, where
  /// `XFile.path` is a `blob:` URL rather than a real filesystem path).
  Future<Map<String, dynamic>> patchMultipartFile(
    Uri uri, {
    required String fieldName,
    required Uint8List fileBytes,
    required String filename,
    String? accessToken,
  }) async {
    final request = http.MultipartRequest('PATCH', uri);
    if (accessToken != null) {
      request.headers['Authorization'] = 'Bearer $accessToken';
    }
    request.files.add(
      http.MultipartFile.fromBytes(fieldName, fileBytes, filename: filename),
    );

    late final http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await _httpClient.send(request).timeout(_timeout);
    } on TimeoutException {
      throw ApiException(0, 'The request timed out. Please try again.');
    } catch (error) {
      throw ApiException(
        0,
        'Unable to connect to the server. Please try again.',
      );
    }

    return _decode(await http.Response.fromStream(streamedResponse));
  }

  Future<Map<String, dynamic>> patch(
    Uri uri, {
    required Map<String, dynamic> body,
    String? accessToken,
  }) async {
    late final http.Response response;
    try {
      response = await _httpClient
          .patch(
            uri,
            headers: {
              ..._jsonHeaders,
              if (accessToken != null) 'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw ApiException(0, 'The request timed out. Please try again.');
    } catch (error) {
      throw ApiException(
        0,
        'Unable to connect to the server. Please try again.',
      );
    }

    return _decode(response);
  }

  Future<void> delete(Uri uri, {String? accessToken}) async {
    late final http.Response response;
    try {
      response = await _httpClient
          .delete(
            uri,
            headers: accessToken == null
                ? null
                : {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw ApiException(0, 'The request timed out. Please try again.');
    } catch (error) {
      throw ApiException(
        0,
        'Unable to connect to the server. Please try again.',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) return;
    _decode(response);
  }

  /// Like [delete], but for the rare endpoint that returns a JSON body on
  /// success (e.g. vote retraction, which reports the updated vote count).
  Future<Map<String, dynamic>> deleteWithResponse(
    Uri uri, {
    String? accessToken,
  }) async {
    late final http.Response response;
    try {
      response = await _httpClient
          .delete(
            uri,
            headers: accessToken == null
                ? null
                : {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw ApiException(0, 'The request timed out. Please try again.');
    } catch (error) {
      throw ApiException(
        0,
        'Unable to connect to the server. Please try again.',
      );
    }

    return _decode(response);
  }

  Future<Map<String, dynamic>> get(Uri uri, {String? accessToken}) async {
    late final http.Response response;
    try {
      response = await _httpClient
          .get(
            uri,
            headers: accessToken == null
                ? null
                : {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw ApiException(0, 'The request timed out. Please try again.');
    } catch (error) {
      throw ApiException(
        0,
        'Unable to connect to the server. Please try again.',
      );
    }

    return _decode(response);
  }

  /// Like [get], but for endpoints whose success response is a bare JSON
  /// array (e.g. Django REST Framework's `ListAPIView`) rather than an
  /// object.
  ///
  /// Django REST Framework's list endpoints are paginated by default (see
  /// `DEFAULT_PAGINATION_CLASS`/`PAGE_SIZE` in the backend's settings), so
  /// a "list" response is actually `{"count": ..., "next": ..., "results":
  /// [...]}` rather than a bare JSON array. This follows `next` until
  /// exhausted and returns every item — callers should never see a
  /// silently-truncated list (e.g. a friends list capped at `PAGE_SIZE`).
  Future<List<Map<String, dynamic>>> getList(
    Uri uri, {
    String? accessToken,
  }) async {
    final allItems = <Map<String, dynamic>>[];
    Uri? nextUri = uri;

    while (nextUri != null) {
      final (items, next) = await _getPage(nextUri, accessToken: accessToken);
      allItems.addAll(items);
      nextUri = next;
    }

    return allItems;
  }

  Future<(List<Map<String, dynamic>>, Uri?)> _getPage(
    Uri uri, {
    String? accessToken,
  }) async {
    late final http.Response response;
    try {
      response = await _httpClient
          .get(
            uri,
            headers: accessToken == null
                ? null
                : {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw ApiException(0, 'The request timed out. Please try again.');
    } catch (error) {
      throw ApiException(
        0,
        'Unable to connect to the server. Please try again.',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return (<Map<String, dynamic>>[], null);
      final parsed = jsonDecode(response.body);
      if (parsed is Map<String, dynamic>) {
        final items = (parsed['results'] as List<dynamic>).cast<Map<String, dynamic>>();
        final next = parsed['next'] as String?;
        return (items, next == null ? null : Uri.parse(next));
      }
      final items = (parsed as List<dynamic>).cast<Map<String, dynamic>>();
      return (items, null);
    }

    Map<String, dynamic>? decoded;
    if (response.body.isNotEmpty) {
      try {
        final parsed = jsonDecode(response.body);
        if (parsed is Map<String, dynamic>) decoded = parsed;
      } on FormatException {
        decoded = null;
      }
    }
    final message = decoded != null
        ? _firstErrorMessage(decoded)
        : 'Request failed with status ${response.statusCode}';
    throw ApiException(
      response.statusCode,
      message,
      fieldErrors: decoded,
      code: decoded?['code'] as String?,
    );
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic>? decoded;
    if (response.body.isNotEmpty) {
      try {
        final parsed = jsonDecode(response.body);
        if (parsed is Map<String, dynamic>) {
          decoded = parsed;
        }
      } on FormatException {
        decoded = null;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded ?? const {};
    }

    final message = decoded != null
        ? _firstErrorMessage(decoded)
        : 'Request failed with status ${response.statusCode}';
    throw ApiException(
      response.statusCode,
      message,
      fieldErrors: decoded,
      code: decoded?['code'] as String?,
    );
  }

  /// Picks the first human-readable message out of an error body — skips
  /// `code` (a machine-readable identifier alongside `detail` on some
  /// responses; see [ApiException.code]) explicitly rather than relying
  /// on `detail` happening to be the first key in the body.
  String _firstErrorMessage(Map<String, dynamic> body) {
    for (final entry in body.entries) {
      if (entry.key == 'code') continue;
      final value = entry.value;
      if (value is List && value.isNotEmpty) {
        return value.first.toString();
      }
      if (value is String) {
        return value;
      }
    }
    return 'Something went wrong. Please try again.';
  }

  void dispose() => _httpClient.close();
}
