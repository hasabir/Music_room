import '../auth/auth_api.dart';
import '../core/api/api_client.dart';
import '../core/api/api_config.dart';
import '../core/auth/token_storage.dart';
import 'notification_models.dart';

/// Talks to the backend's persisted notification history
/// (`/api/v1/user/notifications/...`) — separate from
/// [RealtimeNotificationService], which only delivers the transient
/// websocket toast and keeps no history of its own.
class NotificationApi {
  NotificationApi({
    ApiClient? apiClient,
    TokenStorage? tokenStorage,
    AuthApi? authApi,
  }) : _apiClient = apiClient ?? ApiClient(),
       _tokenStorage = tokenStorage ?? TokenStorage(),
       _authApi = authApi ?? AuthApi(tokenStorage: tokenStorage);

  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;
  final AuthApi _authApi;

  /// Every notification ever recorded for the signed-in user, newest first.
  Future<List<AppNotification>> listNotifications() async {
    final response = await _authorizedGetList(ApiConfig.notificationsUri());
    return response.map((json) => AppNotification.fromJson(json)).toList();
  }

  Future<void> markRead(int notificationId) async {
    await _authorizedPost(
      ApiConfig.notificationMarkReadUri(notificationId),
      body: const {},
    );
  }

  Future<void> markAllRead() async {
    await _authorizedPost(
      ApiConfig.notificationMarkAllReadUri(),
      body: const {},
    );
  }

  Future<Map<String, dynamic>> _authorizedPost(
    Uri uri, {
    required Map<String, dynamic> body,
  }) async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null) throw SessionExpiredException();

    try {
      return await _apiClient.post(uri, body: body, accessToken: accessToken);
    } on ApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      final refreshedToken = await _refreshOrThrow();
      return await _apiClient.post(
        uri,
        body: body,
        accessToken: refreshedToken,
      );
    }
  }

  Future<List<Map<String, dynamic>>> _authorizedGetList(Uri uri) async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null) throw SessionExpiredException();

    try {
      return await _apiClient.getList(uri, accessToken: accessToken);
    } on ApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      final refreshedToken = await _refreshOrThrow();
      return await _apiClient.getList(uri, accessToken: refreshedToken);
    }
  }

  Future<String> _refreshOrThrow() async {
    try {
      return await _authApi.refreshAccessToken();
    } on ApiException {
      await _tokenStorage.clear();
      throw SessionExpiredException();
    }
  }
}
