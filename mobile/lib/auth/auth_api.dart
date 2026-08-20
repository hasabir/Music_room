import '../core/api/api_client.dart';
import '../core/api/api_config.dart';

/// Talks to the backend's authentication endpoints.
class AuthApi {
  AuthApi({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

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
}
