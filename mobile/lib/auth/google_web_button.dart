/// A `Widget buildGoogleWebButton()` that renders Google's own GIS
/// Sign-In button on web, and nothing on every other platform.
///
/// Split out via conditional export (rather than an inline `if (kIsWeb)`
/// inside one file) because `google_web_button_web.dart` imports
/// `package:google_sign_in_web/web_only.dart`, which only compiles for a
/// web target — importing it unconditionally would break mobile/desktop
/// builds. `dart.library.js_interop` is only available when compiling to
/// JS/Wasm, so it's a reliable "is this a web build" compile-time check.
library;

export 'google_web_button_stub.dart'
    if (dart.library.js_interop) 'google_web_button_web.dart';
