import 'package:flutter/material.dart';

import '../../home/home_screen.dart';
import '../../playlist/playlist_screen.dart';
import '../../profile/personal_profile.dart';
import '../../vote/vote_screen.dart';
import 'app_bottom_nav.dart';

/// Switches to [tab] from any screen hosting [AppBottomNav], replacing the
/// current screen so the back stack doesn't grow with every tab switch.
///
/// Does nothing if [tab] is already the screen currently showing.
void navigateToTab(BuildContext context, AppTab currentTab, AppTab tab) {
  if (tab == currentTab) return;

  final destination = switch (tab) {
    AppTab.home => const HomeScreen(),
    AppTab.vote => const VoteScreen(),
    AppTab.playlist => const PlaylistScreen(),
    AppTab.profile => const PersonalProfileScreen(),
  };

  Navigator.of(
    context,
  ).pushReplacement(MaterialPageRoute(builder: (_) => destination));
}
