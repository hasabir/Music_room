import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../playback/playback_controller.dart';

/// Persists the backend's JWT access/refresh tokens in the platform's
/// secure storage (Android Keystore / iOS Keychain), so a session survives
/// app restarts without ever touching the user's password.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'auth_access_token';
  static const _refreshTokenKey = 'auth_refresh_token';

  /// Writes both tokens one after another rather than via `Future.wait` —
  /// on web, `flutter_secure_storage`'s first-ever write for a given
  /// keychain lazily generates and stores a shared AES-GCM wrapping key
  /// (see its `_getEncryptionKey`); two concurrent writes both racing to
  /// create that key throws a `DOMException: OperationError` from the
  /// loser (observed testing this bonus's login flow — see
  /// docs/WEB_BONUS.md). Both tokens still end up stored correctly either
  /// way, but doing this sequentially avoids the race, and the
  /// performance cost of not parallelizing two tiny writes is negligible.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  /// Overwrites just the access token, leaving the refresh token as-is.
  /// Used after a successful `/token/refresh/` call.
  Future<void> saveAccessToken(String accessToken) =>
      _storage.write(key: _accessTokenKey, value: accessToken);

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  /// Whether a previously-stored session exists. Only checks for the
  /// tokens' presence — it does not verify the access token hasn't
  /// expired, since that requires a network round-trip the splash-screen
  /// check intentionally avoids.
  Future<bool> hasSession() async {
    final accessToken = await readAccessToken();
    return accessToken != null && accessToken.isNotEmpty;
  }

  Future<void> clear() async {
    // Playback belongs to the signed-in session too. Clear it before
    // navigating away so the root-level mini player cannot survive logout.
    try {
      await PlaybackController.instance.stop();
    } catch (_) {
      // A player teardown error must never prevent signing out.
    }
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
    ]);
  }
}
