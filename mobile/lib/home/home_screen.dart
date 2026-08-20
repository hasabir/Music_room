import 'package:flutter/material.dart';

import '../auth/auth_api.dart';
import '../auth/welcome_screen.dart';
import '../core/api/api_client.dart';
import '../core/auth/token_storage.dart';

/// Placeholder Home Screen shown to already-authenticated users.
///
/// Intentionally blank — the real Music Room home experience (track
/// voting, control delegation, etc.) will be built out separately.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _authApi = AuthApi();
  final _tokenStorage = TokenStorage();

  @override
  void initState() {
    super.initState();
    _printCurrentUserId();
  }

  Future<void> _printCurrentUserId() async {
    try {
      final user = await _authApi.getCurrentUser();
      debugPrint('Current user id: ${user.id}');
    } on ApiException catch (error) {
      debugPrint('Could not fetch current user: ${error.message}');

      final isRejectedByBackend =
          error.statusCode == 401 ||
          error.statusCode == 403 ||
          error.statusCode == 404;
      if (isRejectedByBackend) {
        await _tokenStorage.clear();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0E0E15),
      body: SizedBox.expand(
        child: Center(
          child: Text(
            'Welcome to home page',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }
}
