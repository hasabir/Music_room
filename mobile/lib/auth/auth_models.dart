/// The authenticated user, as returned by the backend's `UserSerializer`
/// (see `authentication/views.py` / `user/serializers.py`).
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.isEmailVerified,
    required this.registrationMethod,
    required this.hasGoogleLinked,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as int,
    email: json['email'] as String,
    firstName: json['first_name'] as String? ?? '',
    lastName: json['last_name'] as String? ?? '',
    isEmailVerified: json['is_email_verified'] as bool? ?? false,
    registrationMethod: json['registration_method'] as String? ?? 'email',
    hasGoogleLinked: json['has_google_linked'] as bool? ?? false,
  );

  final int id;
  final String email;
  final String firstName;
  final String lastName;
  final bool isEmailVerified;

  /// Either `'email'` or `'google'` (see backend's `User.REGISTRATION_CHOICES`).
  final String registrationMethod;

  /// Whether a Google account has been linked (in addition to, or as, the
  /// sign-in method) — see `authentication.GoogleLinkView`.
  final bool hasGoogleLinked;
}

/// Result of a successful login call.
class LoginResult {
  const LoginResult({required this.user});

  final AuthUser user;
}

/// The 6-digit verification code, as returned by the backend's
/// `dev_verification` response field.
///
/// The backend only includes this when running with `EMAIL_DEV_MODE` on
/// (see `authentication/views.py`), as a way to exercise the verification
/// flow without a real mail server. It carries the exact same code the
/// backend would otherwise deliver by email, so prefilling
/// [AuthApi.verifyEmail]'s input with it performs real backend
/// verification — nothing about it is faked. Outside dev mode this is
/// never present, and the user must type the code from their inbox.
class VerificationCodeInfo {
  const VerificationCodeInfo({required this.code, required this.expiresAt});

  factory VerificationCodeInfo.fromJson(Map<String, dynamic> json) =>
      VerificationCodeInfo(
        code: json['code'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );

  final String code;
  final DateTime expiresAt;
}

/// Result of a successful registration call.
class RegisterResult {
  const RegisterResult({required this.email, this.devVerification});

  final String email;

  /// Non-null only when the backend is running in dev-email mode.
  final VerificationCodeInfo? devVerification;
}
