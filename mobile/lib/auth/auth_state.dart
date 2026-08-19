/// Abstraction over the app's authentication status.
///
/// This lets navigation code (e.g. the splash screen) decide between the
/// Welcome flow and the Home screen without knowing how authentication is
/// actually determined.
abstract class AuthState {
  bool get isAuthenticated;
}

/// Temporary [AuthState] used until a real auth service (backed by the
/// Django backend) is implemented. Defaults to unauthenticated so the
/// Welcome Screen is shown during development.
///
/// Replace this with a real implementation (e.g. one backed by a stored
/// session token) once the auth feature is built.
class TemporaryAuthState implements AuthState {
  const TemporaryAuthState({this.isAuthenticated = false});

  @override
  final bool isAuthenticated;
}
