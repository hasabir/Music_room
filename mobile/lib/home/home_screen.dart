import 'package:flutter/material.dart';

/// Placeholder Home Screen shown to already-authenticated users.
///
/// Intentionally blank — the real Music Room home experience (track
/// voting, control delegation, etc.) will be built out separately.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0E0E15),
      body: SizedBox.expand(),
    );
  }
}
