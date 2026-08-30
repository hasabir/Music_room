import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../core/api/api_config.dart';
import '../core/auth/token_storage.dart';
import 'auth_models.dart';

/// Thrown when an authenticated request can't be completed because
/// there's no valid session — no stored tokens, or the refresh token
/// itself was rejected as expired/invalid. Callers should clear any
/// remaining local state and route the user back to sign in.
class SessionExpiredException implements Exception {}

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
      devVerification: _devCodeFrom(response, 'dev_verification'),
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

  /// Logs in (or registers, on first sign-in) using a Google ID token
  /// obtained via [GoogleAuthService.signInAndGetIdToken].
  ///
  /// On success, persists the returned access/refresh tokens via
  /// [TokenStorage], same as [login].
  Future<LoginResult> loginWithGoogle({required String idToken}) async {
    final response = await _apiClient.post(
      ApiConfig.googleLoginUri(),
      body: {'id_token': idToken},
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

  /// Links a Google account to the signed-in user, using an ID token
  /// obtained via [GoogleAuthService.signInAndGetIdToken].
  ///
  /// The backend requires the Google account's email to match the
  /// signed-in account's email. Throws [ApiException] if it doesn't
  /// match, or if that Google account is already linked to a different
  /// Music Room account.
  Future<AuthUser> linkGoogleAccount({required String idToken}) async {
    final response = await _authorizedPost(
      ApiConfig.googleLinkUri(),
      body: {'id_token': idToken},
    );
    return AuthUser.fromJson(response['user'] as Map<String, dynamic>);
  }

  /// Fetches the currently-authenticated user using the stored access
  /// token.
  ///
  /// If the access token has expired (a 401), transparently refreshes it
  /// via [refreshAccessToken] and retries once. Throws
  /// [SessionExpiredException] if there's no stored session or the
  /// refresh token itself is invalid/expired — callers should treat that
  /// as "log in again". Any other failure (network, 403, 404, ...)
  /// surfaces as [ApiException].
  Future<AuthUser> getCurrentUser() async {
    final response = await _authorizedGet(ApiConfig.meUri());
    return AuthUser.fromJson(response);
  }

  /// Exchanges the stored refresh token for a new access token via
  /// `/token/refresh/`, persisting it. Returns the new access token.
  ///
  /// Throws [ApiException] if there's no stored refresh token or the
  /// backend rejects it (expired/invalid) — callers driving a
  /// refresh-then-retry flow should treat that as a session that can't be
  /// recovered.
  Future<String> refreshAccessToken() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null) {
      throw ApiException(401, 'Not logged in.');
    }

    final response = await _apiClient.post(
      ApiConfig.tokenRefreshUri(),
      body: {'refresh': refreshToken},
    );

    final newAccessToken = response['access'] as String;
    await _tokenStorage.saveAccessToken(newAccessToken);
    return newAccessToken;
  }

  /// GETs [uri] with the stored access token, transparently refreshing
  /// and retrying once on a 401. Throws [SessionExpiredException] if
  /// there's no session to authenticate with, or the refresh itself
  /// fails — in both cases the stored tokens are cleared first.
  Future<Map<String, dynamic>> _authorizedGet(Uri uri) async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null) {
      throw SessionExpiredException();
    }

    try {
      return await _apiClient.get(uri, accessToken: accessToken);
    } on ApiException catch (error) {
      if (error.statusCode != 401) rethrow;

      final String refreshedToken;
      try {
        refreshedToken = await refreshAccessToken();
      } on ApiException {
        await _tokenStorage.clear();
        throw SessionExpiredException();
      }

      return await _apiClient.get(uri, accessToken: refreshedToken);
    }
  }

  /// POSTs [body] to [uri] with the stored access token, transparently
  /// refreshing and retrying once on a 401. Same session-handling as
  /// [_authorizedGet].
  Future<Map<String, dynamic>> _authorizedPost(
    Uri uri, {
    required Map<String, dynamic> body,
  }) async {
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null) {
      throw SessionExpiredException();
    }

    try {
      return await _apiClient.post(uri, body: body, accessToken: accessToken);
    } on ApiException catch (error) {
      if (error.statusCode != 401) rethrow;

      final String refreshedToken;
      try {
        refreshedToken = await refreshAccessToken();
      } on ApiException {
        await _tokenStorage.clear();
        throw SessionExpiredException();
      }

      return await _apiClient.post(
        uri,
        body: body,
        accessToken: refreshedToken,
      );
    }
  }

  /// Confirms an account's email using the 6-digit code the backend
  /// emailed the user.
  ///
  /// Throws [ApiException] if the code is wrong/already used (the backend
  /// reports "Invalid or already-used code.") or expired (15 minutes
  /// after issuance — the backend reports "This code has expired."). The
  /// message text is the only way to distinguish those two cases, since
  /// the backend uses the same 400 status for both.
  Future<void> verifyEmail({required String email, required String code}) {
    return _apiClient.post(
      ApiConfig.verifyEmailUri(),
      body: {'email': email, 'code': code},
    );
  }

  /// Requests a new verification code for an unverified account.
  ///
  /// Invalidates any previously issued, unused code. The backend always
  /// responds with 200 regardless of whether the email is registered or
  /// already verified, to avoid leaking account existence — so this never
  /// throws for that reason. It still throws [ApiException] for network
  /// failures or rate limiting.
  Future<VerificationCodeInfo?> resendVerificationEmail({
    required String email,
  }) async {
    final response = await _apiClient.post(
      ApiConfig.resendVerificationUri(),
      body: {'email': email},
    );
    return _devCodeFrom(response, 'dev_verification');
  }

  /// Requests a password-reset code for the given email, if an
  /// email/password account with that address exists.
  ///
  /// The backend always responds with 200 regardless of whether the
  /// email is registered, to avoid leaking account existence — so this
  /// never throws for that reason. It still throws [ApiException] for
  /// network failures or rate limiting. Also used to resend the code:
  /// the backend endpoint is the same one, and issuing a new code
  /// invalidates any previous unused one.
  Future<VerificationCodeInfo?> requestPasswordReset({
    required String email,
  }) async {
    final response = await _apiClient.post(
      ApiConfig.passwordResetRequestUri(),
      body: {'email': email},
    );
    return _devCodeFrom(response, 'dev_reset');
  }

  /// Checks whether a password-reset code is valid, via
  /// `POST /password-reset/verify-code/`, without consuming it or
  /// changing the password yet. On success, the backend returns a
  /// short-lived `reset_token` (separate from login JWTs) that
  /// [confirmPasswordReset] uses to actually set the new password —
  /// the code itself isn't needed again after this call.
  ///
  /// Throws [ApiException] if the code is wrong/already used ("Invalid
  /// or already-used code.") or expired ("This code has expired."), same
  /// message text as [verifyEmail]'s equivalent cases.
  Future<String> verifyPasswordResetCode({
    required String email,
    required String code,
  }) async {
    final response = await _apiClient.post(
      ApiConfig.passwordResetVerifyCodeUri(),
      body: {'email': email, 'code': code},
    );
    return response['reset_token'] as String;
  }

  /// Sets a new password using the `reset_token` returned by
  /// [verifyPasswordResetCode].
  ///
  /// Throws [ApiException] if the token is invalid/expired ("Invalid or
  /// already-used reset token." / "This reset session has expired.
  /// Please start over."), or if `newPassword` fails the backend's
  /// password validation rules.
  Future<void> confirmPasswordReset({
    required String resetToken,
    required String newPassword,
  }) {
    return _apiClient.post(
      ApiConfig.passwordResetConfirmUri(),
      body: {'reset_token': resetToken, 'new_password': newPassword},
    );
  }

  /// Changes the signed-in user's password, via
  /// `POST /auth/change-password/` (`ChangePasswordView`) — requires the
  /// current password as proof, unlike the forgot-password email-code
  /// flow ([confirmPasswordReset]).
  ///
  /// Throws [ApiException] (400) if `oldPassword` is wrong ("Current
  /// password is incorrect."), if `newPassword` is the same as the old
  /// one, or if it fails the backend's password validation rules.
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) {
    return _authorizedPost(
      ApiConfig.changePasswordUri(),
      body: {'old_password': oldPassword, 'new_password': newPassword},
    );
  }

  VerificationCodeInfo? _devCodeFrom(
    Map<String, dynamic> response,
    String key,
  ) {
    final json = response[key] as Map<String, dynamic>?;
    return json == null ? null : VerificationCodeInfo.fromJson(json);
  }

  /// Invalidates the refresh token server-side (blacklisting it, per
  /// `LogoutView`), best-effort. Never throws — a failed logout call
  /// shouldn't block the user from leaving; callers still clear the
  /// locally-stored tokens regardless of whether this succeeds.
  Future<void> logout() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null) return;

    final accessToken = await _tokenStorage.readAccessToken();
    try {
      await _apiClient.post(
        ApiConfig.logoutUri(),
        body: {'refresh': refreshToken},
        accessToken: accessToken,
      );
    } on ApiException catch (error) {
      debugPrint('Logout call failed: ${error.message}');
    }
  }
}
