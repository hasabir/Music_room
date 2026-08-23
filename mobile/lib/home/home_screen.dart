import 'package:flutter/material.dart';

import '../auth/auth_api.dart';
import '../auth/welcome_screen.dart';
import '../core/api/api_client.dart';
import '../core/auth/token_storage.dart';
import '../core/widgets/app_bottom_nav.dart';
import '../core/widgets/app_tab_navigation.dart';

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
    } on SessionExpiredException {
      // getCurrentUser() already tried refreshing the access token; this
      // means the refresh token itself is gone/expired, so there's no
      // session left to recover.
      await _signOutAndReturnToWelcome();
    } on ApiException catch (error) {
      debugPrint('Could not fetch current user: ${error.message}');

      final isRejectedByBackend =
          error.statusCode == 403 || error.statusCode == 404;
      if (isRejectedByBackend) {
        await _signOutAndReturnToWelcome();
      }
    }
  }

  Future<void> _signOutAndReturnToWelcome() async {
    await _tokenStorage.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  Future<void> _handleLogout() async {
    await _authApi.logout();
    await _signOutAndReturnToWelcome();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E15),
      body: SizedBox.expand(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Welcome to home page',
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _handleLogout,
                child: const Text('Logout'),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentTab: AppTab.home,
        onTabSelected: (tab) => navigateToTab(context, AppTab.home, tab),
      ),
    );
  }
}
