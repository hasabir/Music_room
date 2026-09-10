import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../core/api/api_config.dart';

class GoogleAuthCancelled implements Exception {}

class GoogleAuthFailed implements Exception {
  final String message;
  GoogleAuthFailed(this.message);
}

class GoogleAuthService {
  // Module-level instance — created once, reused everywhere. The web
  // plugin asserts `serverClientId == null` (it has no server-side
  // exchange step) and instead needs the same OAuth client id as
  // `clientId`, which is also what ends up as the web ID token's `aud`
  // claim — the same one the backend already verifies mobile's
  // `serverClientId`-derived tokens against.
  static final GoogleSignIn _googleSignIn = kIsWeb
      ? GoogleSignIn(clientId: ApiConfig.googleWebClientId)
      : GoogleSignIn(serverClientId: ApiConfig.googleWebClientId);

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

  /// Web only: fires a fresh ID token whenever the rendered "Sign In With
  /// Google" button (`google_web_button.dart`) completes a sign-in.
  ///
  /// [signInAndGetIdToken]'s imperative popup is unreliable on the web —
  /// the GIS JS SDK's OAuth popup flow only returns an access token, not
  /// a signed ID token (see google_sign_in_web's README, "Why is the
  /// idToken missing after signIn?"). The rendered button uses Google's
  /// real "Sign In With Google" credential flow instead, which is the
  /// only web path that reliably includes one — so callers on web should
  /// listen to this instead of awaiting [signInAndGetIdToken].
  static Stream<String> get webIdTokenStream => _googleSignIn
      .onCurrentUserChanged
      .asyncMap(
        (account) async =>
            account == null ? null : (await account.authentication).idToken,
      )
      .where((idToken) => idToken != null)
      .cast<String>();
}
