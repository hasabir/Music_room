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
