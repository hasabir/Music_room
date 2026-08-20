/// Central place to configure how the app talks to the Music Room backend.
///
/// Points at the dev machine's LAN IP so a physical device on the same
/// Wi-Fi network can reach the backend running via `docker compose` on
/// port 8000. This IP is assigned by DHCP and can change — if requests
/// start failing, re-check it with `hostname -I` (or `ip addr`) on the
/// machine running the backend and update this value.
class ApiConfig {
  const ApiConfig._();

  static const String baseUrl = 'http://10.32.129.163:8000';

  static const String registerEndpoint = '/api/v1/auth/register/';
  static const String loginEndpoint = '/api/v1/auth/login/';

  static Uri registerUri() => Uri.parse('$baseUrl$registerEndpoint');
  static Uri loginUri() => Uri.parse('$baseUrl$loginEndpoint');
}
