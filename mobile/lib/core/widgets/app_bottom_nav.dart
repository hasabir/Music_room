import 'package:flutter/material.dart';

/// The four top-level destinations reachable from [AppBottomNav].
enum AppTab { home, vote, playlist, profile }

class _NavColors {
  static const background = Color(0xFF16151F);
  static const border = Color(0xFF2A2935);
  static const activePill = Color(0xFF6C6FF0);
  static const activeLabel = Color(0xFFF5F4FF);
  static const inactive = Color(0xFF8F8DA3);
}

/// Music Room's bottom tab bar (Home / Vote / Playlist / Profile).
///
/// Purely presentational: callers own navigation and pass the currently
/// selected tab plus a callback for taps.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentTab,
    required this.onTabSelected,
  });

  final AppTab currentTab;
  final ValueChanged<AppTab> onTabSelected;

  static const _items = [
    (tab: AppTab.home, icon: Icons.home_rounded, label: 'Home'),
    (tab: AppTab.vote, icon: Icons.how_to_vote_rounded, label: 'Vote'),
    (tab: AppTab.playlist, icon: Icons.queue_music_rounded, label: 'Playlist'),
    (tab: AppTab.profile, icon: Icons.person_rounded, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _NavColors.background,
        border: Border(top: BorderSide(color: _NavColors.border)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final item in _items)
                _NavItem(
                  icon: item.icon,
                  label: item.label,
                  isSelected: item.tab == currentTab,
                  onTap: () => onTabSelected(item.tab),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? _NavColors.activeLabel : _NavColors.inactive;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _NavColors.activePill : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
