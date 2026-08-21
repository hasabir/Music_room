import '../core/api/api_client.dart';
import '../core/auth/token_storage.dart';
import 'auth_api.dart';

/// Abstraction over the app's authentication status.
///
/// This lets navigation code (e.g. the splash screen) decide between the
/// Welcome flow and the Home screen without knowing how authentication is
/// actually determined.
abstract class AuthState {
  Future<bool> isAuthenticated();
}

/// [AuthState] backed by the tokens persisted in [TokenStorage].
///
/// A locally-stored access token isn't enough on its own — it may be
/// stale (the account was deleted, the token was revoked, etc.), so this
/// confirms the session against the backend's `/user/me/` endpoint before
/// treating the user as authenticated. If the backend rejects the token
/// (401/403/404), the stale tokens are cleared so the user lands on the
/// Welcome screen instead of a broken Home screen. A network failure
/// (backend unreachable) can't confirm or deny the session, so it falls
/// back to trusting the locally-stored token rather than logging the
/// user out just because they're offline.
class SessionAuthState implements AuthState {
  SessionAuthState({TokenStorage? tokenStorage, AuthApi? authApi})
    : _tokenStorage = tokenStorage ?? TokenStorage(),
      _authApi = authApi ?? AuthApi(tokenStorage: tokenStorage);

  final TokenStorage _tokenStorage;
  final AuthApi _authApi;

  @override
  Future<bool> isAuthenticated() async {
    if (!await _tokenStorage.hasSession()) return false;

    try {
      await _authApi.getCurrentUser();
      return true;
    } on SessionExpiredException {
      // getCurrentUser() already tried refreshing the access token and
      // cleared storage; the refresh token itself is gone/expired.
      return false;
    } on ApiException catch (error) {
      final isRejectedByBackend =
          error.statusCode == 403 || error.statusCode == 404;
      if (isRejectedByBackend) {
        await _tokenStorage.clear();
        return false;
      }
      return true;
    }
  }
}
