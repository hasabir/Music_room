import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

/// Renders Google's own "Sign In With Google" button (GIS JS SDK) — the
/// web-only reliable way to get a real ID token; see google_web_button.dart
/// and google_auth_service.dart's `webIdTokenStream` for why.
Widget buildGoogleWebButton() => web.renderButton(
  configuration: web.GSIButtonConfiguration(
    theme: web.GSIButtonTheme.filledBlack,
    size: web.GSIButtonSize.large,
    text: web.GSIButtonText.continueWith,
    shape: web.GSIButtonShape.pill,
    minimumWidth: 300,
  ),
);
