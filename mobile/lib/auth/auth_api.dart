import '../core/api/api_client.dart';
import '../core/api/api_config.dart';
import '../core/auth/token_storage.dart';
import 'auth_models.dart';

/// Talks to the backend's authentication endpoints.
class AuthApi {
  AuthApi({ApiClient? apiClient, TokenStorage? tokenStorage})
    : _apiClient = apiClient ?? ApiClient(),
      _tokenStorage = tokenStorage ?? TokenStorage();

  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;

  /// Registers a new account.
  ///
  /// `confirmPassword` is intentionally not a parameter here — it's a
  /// client-side-only check and must never be sent to the backend.
  Future<void> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) {
    return _apiClient.post(
      ApiConfig.registerUri(),
      body: {
        'email': email,
        'password': password,
        'first_name': firstName,
        'last_name': lastName,
      },
    );
  }

  /// Logs in with an email/password pair.
  ///
  /// On success, persists the returned access/refresh tokens via
  /// [TokenStorage] so the session survives app restarts, then returns
  /// the authenticated user.
  Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.post(
      ApiConfig.loginUri(),
      body: {'email': email, 'password': password},
    );

    final tokens = response['tokens'] as Map<String, dynamic>;
    await _tokenStorage.saveTokens(
      accessToken: tokens['access'] as String,
      refreshToken: tokens['refresh'] as String,
    );

    return LoginResult(
      user: AuthUser.fromJson(response['user'] as Map<String, dynamic>),
    );
  }
}
