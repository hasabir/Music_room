import 'package:flutter/material.dart';

import '../core/widgets/app_bottom_nav.dart';
import '../core/widgets/app_tab_navigation.dart';

/// Placeholder Playlist screen, reachable from the bottom nav.
///
/// Intentionally blank — the real playlist experience will be built out
/// separately.
class PlaylistScreen extends StatelessWidget {
  const PlaylistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E15),
      body: const SizedBox.expand(
        child: Center(
          child: Text(
            'Playlist — coming soon',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentTab: AppTab.playlist,
        onTabSelected: (tab) => navigateToTab(context, AppTab.playlist, tab),
      ),
    );
  }
}
