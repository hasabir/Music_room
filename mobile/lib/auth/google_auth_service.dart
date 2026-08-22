import 'package:google_sign_in/google_sign_in.dart';
import '../core/api/api_config.dart';

class GoogleAuthCancelled implements Exception {}
class GoogleAuthFailed implements Exception {
  final String message;
  GoogleAuthFailed(this.message);
}

class GoogleAuthService {
  // Module-level instance — created once, reused everywhere.
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: ApiConfig.googleWebClientId,
  );

  /// Runs the Google account picker and returns the ID token
  /// to send to your backend's /auth/google/ endpoint.
  static Future<String> signInAndGetIdToken() async {
    final GoogleSignInAccount? account = await _googleSignIn.signIn();
    if (account == null) {
      throw GoogleAuthCancelled();
    }

    final GoogleSignInAuthentication auth = await account.authentication;
    final String? idToken = auth.idToken;

    if (idToken == null) {
      throw GoogleAuthFailed('No ID token returned by Google.');
    }

    return idToken;
  }

  static Future<void> signOut() => _googleSignIn.signOut();
}