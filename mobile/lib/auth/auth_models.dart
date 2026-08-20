/// The authenticated user, as returned by the backend's `UserSerializer`
/// (see `authentication/views.py` / `user/serializers.py`).
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as int,
    email: json['email'] as String,
    firstName: json['first_name'] as String? ?? '',
    lastName: json['last_name'] as String? ?? '',
  );

  final int id;
  final String email;
  final String firstName;
  final String lastName;
}

/// Result of a successful login call.
class LoginResult {
  const LoginResult({required this.user});

  final AuthUser user;
}

/// The uid/token pair for confirming an account's email, as returned by the
/// backend's `dev_verification` response field.
///
/// The backend only includes this when running with `EMAIL_DEV_MODE` on
/// (see `authentication/views.py`), as a way to exercise the verification
/// flow without a real mail server. It carries the exact same uid/token the
/// backend would otherwise deliver via the link in the verification email,
/// so calling [AuthApi.verifyEmail] with it performs real backend
/// verification — nothing about it is faked.
class DevVerificationInfo {
  const DevVerificationInfo({required this.uid, required this.token});

  factory DevVerificationInfo.fromJson(Map<String, dynamic> json) =>
      DevVerificationInfo(
        uid: json['uid'] as String,
        token: json['token'] as String,
      );

  final String uid;
  final String token;
}

/// Result of a successful registration call.
class RegisterResult {
  const RegisterResult({required this.email, this.devVerification});

  final String email;

  /// Non-null only when the backend is running in dev-email mode.
  final DevVerificationInfo? devVerification;
}
