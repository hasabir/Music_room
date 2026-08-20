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
  ///
  /// The backend does not log the user in on registration — it requires
  /// email verification first (see [verifyEmail]).
  Future<RegisterResult> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    final response = await _apiClient.post(
      ApiConfig.registerUri(),
      body: {
        'email': email,
        'password': password,
        'first_name': firstName,
        'last_name': lastName,
      },
    );

    return RegisterResult(
      email: email,
      devVerification: _devVerificationFrom(response),
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

  /// Fetches the currently-authenticated user using the stored access
  /// token. Throws [ApiException] if there's no stored session or the
  /// backend rejects the token.
  Future<AuthUser> getCurrentUser() async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null) {
      throw ApiException(401, 'Not logged in.');
    }

    final response = await _apiClient.get(
      ApiConfig.meUri(),
      accessToken: accessToken,
    );
    return AuthUser.fromJson(response);
  }

  /// Confirms an account's email using the uid/token pair from the
  /// verification link the backend emailed the user (or, in dev-email
  /// mode, from [RegisterResult.devVerification] /
  /// [resendVerificationEmail]'s return value).
  ///
  /// Throws [ApiException] if the uid/token pair is invalid, already used,
  /// or expired — the backend does not distinguish between those cases.
  Future<void> verifyEmail({required String uid, required String token}) {
    return _apiClient.post(
      ApiConfig.verifyEmailUri(),
      body: {'uid': uid, 'token': token},
    );
  }

  /// Requests a new verification email for an unverified account.
  ///
  /// The backend always responds with 200 regardless of whether the email
  /// is registered or already verified, to avoid leaking account
  /// existence — so this never throws for that reason. It still throws
  /// [ApiException] for network failures or rate limiting.
  Future<DevVerificationInfo?> resendVerificationEmail({
    required String email,
  }) async {
    final response = await _apiClient.post(
      ApiConfig.resendVerificationUri(),
      body: {'email': email},
    );
    return _devVerificationFrom(response);
  }

  DevVerificationInfo? _devVerificationFrom(Map<String, dynamic> response) {
    final json = response['dev_verification'] as Map<String, dynamic>?;
    return json == null ? null : DevVerificationInfo.fromJson(json);
  }
}
