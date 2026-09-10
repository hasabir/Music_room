import 'package:flutter/widgets.dart';

/// Default (non-web) implementation — never actually rendered, since
/// every call site gates this behind `kIsWeb`. See google_web_button.dart.
Widget buildGoogleWebButton() => const SizedBox.shrink();
