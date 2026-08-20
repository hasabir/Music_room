import '../core/auth/token_storage.dart';

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
/// A session is considered valid if an access token was saved by a prior
/// successful login (see `AuthApi.login`) and hasn't been cleared since.
class SessionAuthState implements AuthState {
  SessionAuthState({TokenStorage? tokenStorage})
    : _tokenStorage = tokenStorage ?? TokenStorage();

  final TokenStorage _tokenStorage;

  @override
  Future<bool> isAuthenticated() => _tokenStorage.hasSession();
}
