import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown when the backend returns a non-2xx response, or the response body
/// can't be parsed as expected.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.fieldErrors});

  final int statusCode;
  final String message;

  /// Field-level validation errors, e.g. `{"email": ["already in use"]}`,
  /// as returned by Django REST Framework serializers.
  final Map<String, dynamic>? fieldErrors;

  @override
  String toString() => 'ApiException($statusCode, $message)';
}

/// Thin wrapper around [http.Client] for JSON APIs.
///
/// Centralizes request/response handling (encoding, status checks, error
/// parsing) so individual features don't each reimplement it.
class ApiClient {
  ApiClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

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
  Future<Map<String, dynamic>> patchMultipartFile(
    Uri uri, {
    required String fieldName,
    required String filePath,
    String? accessToken,
  }) async {
    final request = http.MultipartRequest('PATCH', uri);
    if (accessToken != null) {
      request.headers['Authorization'] = 'Bearer $accessToken';
    }
    request.files.add(await http.MultipartFile.fromPath(fieldName, filePath));

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
    throw ApiException(response.statusCode, message, fieldErrors: decoded);
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
    throw ApiException(response.statusCode, message, fieldErrors: decoded);
  }

  String _firstErrorMessage(Map<String, dynamic> body) {
    for (final value in body.values) {
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
