import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central place to configure how the app talks to the Music Room backend.
///
/// Points at the dev machine's LAN IP so a physical device on the same
/// Wi-Fi network can reach the backend running via `docker compose` on
/// port 8000. This IP is assigned by DHCP and can change — if requests
/// start failing, re-check it with `hostname -I` (or `ip addr`) on the
/// machine running the backend and update `API_BASE_URL` in `.env`.
class ApiConfig {
  const ApiConfig._();

  static String get baseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'http://10.116.112.13:8000';

  static String get googleWebClientId => dotenv.env['GOOGLE_CLIENT_ID'] ?? '';

  static const String registerEndpoint = '/api/v1/auth/register/';
  static const String loginEndpoint = '/api/v1/auth/login/';
  static const String meEndpoint = '/api/v1/user/me/';
  static const String verifyEmailEndpoint = '/api/v1/auth/verify-email/';
  static const String resendVerificationEndpoint =
      '/api/v1/auth/resend-verification/';
  static const String logoutEndpoint = '/api/v1/auth/logout/';
  static const String googleLoginEndpoint = '/api/v1/auth/google/';
  static const String googleLinkEndpoint = '/api/v1/auth/google/link/';
  static const String tokenRefreshEndpoint = '/api/v1/auth/token/refresh/';
  static const String passwordResetRequestEndpoint =
      '/api/v1/auth/password-reset/';
  static const String passwordResetVerifyCodeEndpoint =
      '/api/v1/auth/password-reset/verify-code/';
  static const String passwordResetConfirmEndpoint =
      '/api/v1/auth/password-reset/set-new-password/';
  static const String myProfileEndpoint = '/api/v1/profile/me/';
  static const String friendsEndpoint = '/api/v1/profile/friends/';

  static Uri registerUri() => Uri.parse('$baseUrl$registerEndpoint');
  static Uri loginUri() => Uri.parse('$baseUrl$loginEndpoint');
  static Uri meUri() => Uri.parse('$baseUrl$meEndpoint');
  static Uri verifyEmailUri() => Uri.parse('$baseUrl$verifyEmailEndpoint');
  static Uri resendVerificationUri() =>
      Uri.parse('$baseUrl$resendVerificationEndpoint');
  static Uri tokenRefreshUri() => Uri.parse('$baseUrl$tokenRefreshEndpoint');
  static Uri logoutUri() => Uri.parse('$baseUrl$logoutEndpoint');
  static Uri googleLoginUri() => Uri.parse('$baseUrl$googleLoginEndpoint');
  static Uri googleLinkUri() => Uri.parse('$baseUrl$googleLinkEndpoint');
  static Uri passwordResetRequestUri() =>
      Uri.parse('$baseUrl$passwordResetRequestEndpoint');
  static Uri passwordResetVerifyCodeUri() =>
      Uri.parse('$baseUrl$passwordResetVerifyCodeEndpoint');
  static Uri passwordResetConfirmUri() =>
      Uri.parse('$baseUrl$passwordResetConfirmEndpoint');
  static Uri myProfileUri() => Uri.parse('$baseUrl$myProfileEndpoint');
  static Uri friendsUri() => Uri.parse('$baseUrl$friendsEndpoint');
}
