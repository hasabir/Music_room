/// Central place to configure how the app talks to the Music Room backend.
///
/// Points at the dev machine's LAN IP so a physical device on the same
/// Wi-Fi network can reach the backend running via `docker compose` on
/// port 8000. This IP is assigned by DHCP and can change — if requests
/// start failing, re-check it with `hostname -I` (or `ip addr`) on the
/// machine running the backend and update this value.
class ApiConfig {
  const ApiConfig._();

  static const String baseUrl = 'http://10.116.112.13:8000';

  static const String registerEndpoint = '/api/v1/auth/register/';
  static const String loginEndpoint = '/api/v1/auth/login/';
  static const String meEndpoint = '/api/v1/user/me/';
  static const String verifyEmailEndpoint = '/api/v1/auth/verify-email/';
  static const String resendVerificationEndpoint =
      '/api/v1/auth/resend-verification/';
  static const String logoutEndpoint = '/api/v1/auth/logout/';
  static const String tokenRefreshEndpoint = '/api/v1/auth/token/refresh/';

  static Uri registerUri() => Uri.parse('$baseUrl$registerEndpoint');
  static Uri loginUri() => Uri.parse('$baseUrl$loginEndpoint');
  static Uri meUri() => Uri.parse('$baseUrl$meEndpoint');
  static Uri verifyEmailUri() => Uri.parse('$baseUrl$verifyEmailEndpoint');
  static Uri resendVerificationUri() =>
      Uri.parse('$baseUrl$resendVerificationEndpoint');
  static Uri tokenRefreshUri() => Uri.parse('$baseUrl$tokenRefreshEndpoint');
  static Uri logoutUri() => Uri.parse('$baseUrl$logoutEndpoint');
}
