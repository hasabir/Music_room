import 'package:flutter/material.dart';

import '../widgets/app_bottom_nav.dart';

/// Single source of truth for where Music Room switches from a
/// phone-shaped single-column layout to a wider desktop-shaped one (side
/// navigation, multi-column lists). Chosen at a small-tablet-landscape
/// width so a resized browser window (the primary reason this exists — see
/// docs/WEB_BONUS.md) crosses it well before it'd be awkward to show a
/// stretched single phone column.
class Breakpoints {
  const Breakpoints._();

  static const double desktop = 900;
}

bool isDesktopWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= Breakpoints.desktop;

/// Wraps a screen's `body` with Music Room's bottom tab bar on narrow
/// (phone) layouts, or a [NavigationRail] down the left edge on wide
/// (desktop/web) layouts — the same four [AppTab] destinations either way,
/// just relocated. Screens keep owning their own `Scaffold` for everything
/// else (app bars, FABs, colors); this only replaces the
/// `bottomNavigationBar` boilerplate every top-level tab screen repeats.
///
/// A plain `NavigationRail` (built into `package:material`, no extra
/// dependency) rather than a custom widget: it already handles selection
/// styling, and matches Material 3's own guidance for this exact
/// phone-bottom-bar / desktop-side-rail split.
class ResponsiveScaffold extends StatelessWidget {
  const ResponsiveScaffold({
    super.key,
    required this.currentTab,
    required this.onTabSelected,
    required this.body,
    this.backgroundColor,
    this.floatingActionButton,
  });

  final AppTab currentTab;
  final ValueChanged<AppTab> onTabSelected;
  final Widget body;
  final Color? backgroundColor;
  final Widget? floatingActionButton;

  static const _items = [
    (tab: AppTab.home, icon: Icons.home_rounded, label: 'Home'),
    (tab: AppTab.vote, icon: Icons.how_to_vote_rounded, label: 'Vote'),
    (tab: AppTab.playlist, icon: Icons.queue_music_rounded, label: 'Playlist'),
    (tab: AppTab.profile, icon: Icons.person_rounded, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    if (!isDesktopWidth(context)) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: body,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: AppBottomNav(
          currentTab: currentTab,
          onTabSelected: onTabSelected,
        ),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      floatingActionButton: floatingActionButton,
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _items.indexWhere((i) => i.tab == currentTab),
            onDestinationSelected: (index) =>
                onTabSelected(_items[index].tab),
            labelType: NavigationRailLabelType.all,
            backgroundColor: const Color(0xFF16151F),
            selectedIconTheme: const IconThemeData(color: Color(0xFFF5F4FF)),
            selectedLabelTextStyle: const TextStyle(
              color: Color(0xFFF5F4FF),
              fontWeight: FontWeight.w700,
            ),
            unselectedIconTheme: const IconThemeData(color: Color(0xFF8F8DA3)),
            unselectedLabelTextStyle: const TextStyle(color: Color(0xFF8F8DA3)),
            destinations: [
              for (final item in _items)
                NavigationRailDestination(
                  icon: Icon(item.icon),
                  label: Text(item.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1, color: Color(0xFF2A2935)),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Lays [children] (cards of varying height) out as a single scrollable
/// column on narrow layouts, or as a multi-column [Wrap] once the
/// available width fits more than one card — the "multi-column lists" half
/// of the desktop breakpoint requirement.
///
/// A [Wrap] rather than a [GridView]: these cards (event/playlist heroes)
/// don't share a fixed height — a [GridView]'s cells do, via
/// `childAspectRatio`, which risks overflow the moment one card's content
/// (badge row wrapping to two lines, a longer description) is taller than
/// the rest. `Wrap` lets every card size to its own content while still
/// flowing into rows, at the cost of items not vertically aligning across
/// a row the way a strict grid would — an acceptable trade for cards this
/// variable.
class ResponsiveCardGrid extends StatelessWidget {
  const ResponsiveCardGrid({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.spacing = 16,
    this.minCardWidth = 360,
    this.maxColumns = 3,
    this.scrollPhysics,
  });

  final List<Widget> children;
  final EdgeInsets padding;
  final double spacing;
  final double minCardWidth;
  final int maxColumns;
  final ScrollPhysics? scrollPhysics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // [padding] is applied to the inner ListView below, not here — the
        // column math has to account for it up front anyway, since a
        // Wrap child's width is fixed once computed and can't shrink to
        // fit the space padding then reclaims, unlike a Row's Expanded.
        final availableWidth = constraints.maxWidth - padding.horizontal;
        final columns = (availableWidth / minCardWidth)
            .floor()
            .clamp(1, maxColumns);

        if (columns <= 1) {
          return ListView.separated(
            padding: padding,
            physics: scrollPhysics,
            itemCount: children.length,
            separatorBuilder: (_, _) => SizedBox(height: spacing),
            itemBuilder: (_, index) => children[index],
          );
        }

        final cardWidth =
            (availableWidth - spacing * (columns - 1)) / columns;
        return ListView(
          padding: padding,
          physics: scrollPhysics,
          children: [
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final child in children)
                  SizedBox(width: cardWidth, child: child),
              ],
            ),
          ],
        );
      },
    );
  }
}
