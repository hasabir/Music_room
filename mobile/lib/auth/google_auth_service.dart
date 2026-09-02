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
  ///
  /// Signs out of the plugin's own cached session first — otherwise
  /// `signIn()` silently reuses whichever Google account last completed
  /// this flow (anywhere in the app: login or linking) without ever
  /// showing the account picker again. Since linking explicitly allows
  /// any Google account regardless of the signed-in user's email, always
  /// showing the picker is what lets a user actually pick a *different*
  /// one instead of being stuck with whatever was cached.
  static Future<String> signInAndGetIdToken() async {
    await _googleSignIn.signOut();
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