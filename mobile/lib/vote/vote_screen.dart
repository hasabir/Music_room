import 'package:flutter/material.dart';

import '../core/widgets/app_bottom_nav.dart';
import '../core/widgets/app_tab_navigation.dart';

/// Placeholder Vote screen, reachable from the bottom nav.
///
/// Intentionally blank — the real voting experience will be built out
/// separately.
class VoteScreen extends StatelessWidget {
  const VoteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E15),
      body: const SizedBox.expand(
        child: Center(
          child: Text('Vote — coming soon', style: TextStyle(color: Colors.white)),
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentTab: AppTab.vote,
        onTabSelected: (tab) => navigateToTab(context, AppTab.vote, tab),
      ),
    );
  }
}
