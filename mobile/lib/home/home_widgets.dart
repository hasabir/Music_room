import 'package:flutter/material.dart';

import '../track_vote/event_models.dart';
import '../track_vote/event_widgets.dart';

/// Shared palette for the Home screen — mirrors the dark, high-contrast
/// scheme every other screen defines locally (`_EventColors` in
/// `events_landing_screen.dart`, `_ProfileColors` in `personal_profile.dart`),
/// kept public here since both `home_screen.dart` and this file need it.
class HomeColors {
  const HomeColors._();

  static const background = Color(0xFF0E0E15);
  static const card = Color(0xFF17161F);
  static const cardBorder = Color(0xFF2A2935);
  static const skeleton = Color(0xFF1D1C28);
  static const headline = Color(0xFFC0C1FF);
  static const body = Color(0xFFE4E1EB);
  static const muted = Color(0xFF908FA0);
  static const tertiary = Color(0xFF2FD9F4);
  static const gradientStart = Color(0xFF8083FF);
  static const gradientEnd = Color(0xFF494BD6);
}

/// A section title ("Your Events", "Discover", ...) with generous spacing
/// around it, so sections read as clearly separated blocks rather than one
/// dense uniform list.
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: HomeColors.body,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: const TextStyle(fontSize: 13, color: HomeColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

const double yourEventCardWidth = 172;
const double yourEventCardHeight = 224;

String _eventCoverAsset(String preset) =>
    EventCoverPreset.byId(preset)?.assetPath ?? EventCoverPreset.party.assetPath;

/// Straight-line distance, already formatted for display (e.g. "650 m
/// away" / "3.2 km away") — meters below 1km read oddly as "0.6 km".
String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m away';
  return '${(meters / 1000).toStringAsFixed(1)} km away';
}

const _monthAbbrev = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatUpcoming(DateTime value) {
  final local = value.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '${_monthAbbrev[local.month - 1]} ${local.day} · $hour12:$minute $period';
}

/// The small corner badge on a [YourEventCard] — reuses the same
/// live/closed/canceled/ghost-town status language as the Vote tab's cards
/// ([EventOverlayStatusBadge]/[LiveBadge] in `event_widgets.dart`) so it
/// stays consistent with what those labels already mean elsewhere in the
/// app, and falls back to a compact "opens on [date]" pill when the event has
/// a real future `votingOpensAt` and none of those apply. Returns `null`
/// when there's nothing worth badging (a live event with no restriction
/// and voting not yet open — nothing more specific to say).
Widget? eventCornerBadge(Event event) {
  switch (event.status) {
    case eventStatusClosed:
      return const EventOverlayStatusBadge(
        label: 'CLOSED',
        color: EventBadgeColors.statusClosed,
      );
    case eventStatusCanceled:
      return const EventOverlayStatusBadge(
        label: '⦸ CANCELED',
        color: EventBadgeColors.statusCanceled,
      );
    case eventStatusGhostTown:
      return const EventOverlayStatusBadge(
        label: 'GHOST TOWN 👻',
        color: EventBadgeColors.statusGhostTown,
      );
    case eventStatusRipAttendance:
      return const EventOverlayStatusBadge(
        label: 'RIP ATTENDANCE',
        color: EventBadgeColors.statusRipAttendance,
      );
    case eventStatusPartyOfNobody:
      return const EventOverlayStatusBadge(
        label: 'PARTY OF NOBODY',
        color: EventBadgeColors.statusPartyOfNobody,
      );
  }

  if (event.votingIsOpen) return const LiveBadge();

  final opensAt = event.votingOpensAt;
  if (event.timeRestrictionEnabled &&
      opensAt != null &&
      opensAt.isAfter(DateTime.now())) {
    return EventOverlayStatusBadge(
      label: _formatUpcoming(opensAt),
      color: HomeColors.tertiary,
    );
  }

  return null;
}

/// A large poster-style card for the "Your Events" row — full-bleed cover
/// image with the title (and badge) overlaid directly on it, the bolder
/// "large cover-image card" treatment this screen favors over the
/// image-on-top/text-below layout the Vote tab's cards use.
class YourEventCard extends StatelessWidget {
  const YourEventCard({super.key, required this.event, required this.onTap});

  final Event event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final badge = eventCornerBadge(event);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: yourEventCardWidth,
        height: yourEventCardHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: HomeColors.cardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              _eventCoverAsset(event.coverPreset),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const _CoverGradientFallback(),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xE6000000)],
                    stops: [0.4, 1.0],
                  ),
                ),
              ),
            ),
            if (badge != null) Positioned(top: 12, left: 12, child: badge),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      height: 1.15,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hosted by ${event.host}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFD8D6E6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverGradientFallback extends StatelessWidget {
  const _CoverGradientFallback();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [HomeColors.gradientStart, HomeColors.gradientEnd],
      ),
    ),
    child: Center(
      child: Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 48),
    ),
  );
}

/// A horizontal row card for the "Discover" list — cover thumbnail, title,
/// visibility/license/restriction tags, and an optional distance line (only
/// shown when both the event has real venue coordinates and the device's
/// position was resolved — see `home_screen.dart`).
class DiscoverEventTile extends StatelessWidget {
  const DiscoverEventTile({
    super.key,
    required this.event,
    required this.distanceLabel,
    required this.onTap,
  });

  final Event event;
  final String? distanceLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: HomeColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: HomeColors.cardBorder),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EventCoverThumb(coverPreset: event.coverPreset, size: 68, radius: 16),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: HomeColors.body,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      EventVisibilityBadge(visibility: event.visibility),
                      EventLicenseBadge(votePermission: event.votePermission),
                      if (event.timeRestrictionEnabled)
                        const EventTimeRestrictionBadge(),
                      if (event.locationRestrictionEnabled)
                        const EventLocationRestrictionBadge(),
                    ],
                  ),
                  if (distanceLabel != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.near_me_rounded,
                          size: 13,
                          color: HomeColors.muted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          distanceLabel!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: HomeColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact card for the "Pending Invitations" section — event identity
/// plus inline Accept/Decline actions (swapped for a spinner while
/// [isBusy], so a slow response can't be double-tapped).
class PendingInviteCard extends StatelessWidget {
  const PendingInviteCard({
    super.key,
    required this.event,
    required this.isBusy,
    required this.onAccept,
    required this.onDecline,
  });

  final Event event;
  final bool isBusy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: HomeColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HomeColors.cardBorder),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          EventCoverThumb(coverPreset: event.coverPreset, size: 52, radius: 14),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: HomeColors.body,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Hosted by ${event.host}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: HomeColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (isBusy)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: HomeColors.tertiary,
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PillIconButton(
                  icon: Icons.close_rounded,
                  color: HomeColors.muted,
                  onTap: onDecline,
                ),
                const SizedBox(width: 8),
                _PillIconButton(
                  icon: Icons.check_rounded,
                  color: HomeColors.tertiary,
                  filled: true,
                  onTap: onAccept,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PillIconButton extends StatelessWidget {
  const _PillIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? color.withValues(alpha: 0.18) : Colors.transparent,
          border: Border.all(color: filled ? color : HomeColors.cardBorder),
        ),
        child: Icon(icon, size: 17, color: color),
      ),
    );
  }
}

/// A friendly empty-state panel — icon, message, and an optional gradient
/// CTA — used for both "no events at all" (Your Events) and "nothing
/// public nearby" (Discover), never a blank/empty-looking box.
class HomeEmptyPanel extends StatelessWidget {
  const HomeEmptyPanel({
    super.key,
    required this.icon,
    required this.message,
    this.ctaLabel,
    this.onCta,
  });

  final IconData icon;
  final String message;
  final String? ctaLabel;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      width: double.infinity,
      decoration: BoxDecoration(
        color: HomeColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HomeColors.cardBorder),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: HomeColors.muted),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: HomeColors.body, fontSize: 14),
          ),
          if (ctaLabel != null) ...[
            const SizedBox(height: 16),
            _GradientPillButton(label: ctaLabel!, onTap: onCta!),
          ],
        ],
      ),
    );
  }
}

class _GradientPillButton extends StatelessWidget {
  const _GradientPillButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [HomeColors.gradientStart, HomeColors.gradientEnd],
        ),
      ),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Sora',
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

/// A skeleton placeholder for the "Your Events" horizontal row, shown while
/// its data is loading instead of a blank gap or a page-wide spinner.
class YourEventsSkeletonRow extends StatelessWidget {
  const YourEventsSkeletonRow({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: yourEventCardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: 3,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (_, _) => Container(
          width: yourEventCardWidth,
          decoration: BoxDecoration(
            color: HomeColors.skeleton,
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
    );
  }
}

/// A skeleton placeholder for the "Discover" vertical list — see
/// [YourEventsSkeletonRow].
class DiscoverSkeletonList extends StatelessWidget {
  const DiscoverSkeletonList({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == 2 ? 0 : 14),
              child: Container(
                height: 92,
                decoration: BoxDecoration(
                  color: HomeColors.skeleton,
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A skeleton placeholder for the header's greeting + avatar, shown while
/// the profile is still loading.
class HomeHeaderSkeleton extends StatelessWidget {
  const HomeHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 22,
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: HomeColors.skeleton,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: HomeColors.skeleton,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

/// Page-level error state (failed to load anything at all) — retry button,
/// mirrors `_ErrorState` in `events_landing_screen.dart`.
class HomeErrorPanel extends StatelessWidget {
  const HomeErrorPanel({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: HomeColors.muted, size: 40),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: HomeColors.body),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: HomeColors.tertiary,
                side: const BorderSide(color: HomeColors.tertiary),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
