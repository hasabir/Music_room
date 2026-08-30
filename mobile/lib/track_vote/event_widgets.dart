import 'package:flutter/material.dart';

import 'event_models.dart';

/// Colors for the small pill badges below — mirrors
/// `lib/playlists/playlist_widgets.dart`'s `PlaylistBadgeColors` (same
/// public/private visibility concept, reused independently here since
/// events and playlists are separate features).
class EventBadgeColors {
  const EventBadgeColors._();

  static const visibilityPublic = Color(0xFF2FD9F4);
  static const visibilityPrivate = Color(0xFF908FA0);
  static const licenseEveryone = Color(0xFF6C6FF0);
  static const licenseInvitedOnly = Color(0xFFE05FA8);
  static const licenseLocationTimeRestricted = Color(0xFFFBBF24);
}

/// A small pill showing an event's `visibility`
/// ([eventVisibilityPublic] / [eventVisibilityPrivate]).
class EventVisibilityBadge extends StatelessWidget {
  const EventVisibilityBadge({super.key, required this.visibility});

  final String visibility;

  @override
  Widget build(BuildContext context) {
    final isPublic = visibility == eventVisibilityPublic;
    return _Badge(
      label: isPublic ? 'Public' : 'Private',
      icon: isPublic ? Icons.public_rounded : Icons.lock_rounded,
      color: isPublic ? EventBadgeColors.visibilityPublic : EventBadgeColors.visibilityPrivate,
    );
  }
}

/// A small pill showing an event's `vote_permission` ("license"):
/// [eventVotePermissionEveryone] / [eventVotePermissionInvitedOnly] /
/// [eventVotePermissionLocationTimeRestricted].
class EventLicenseBadge extends StatelessWidget {
  const EventLicenseBadge({super.key, required this.votePermission});

  final String votePermission;

  @override
  Widget build(BuildContext context) {
    switch (votePermission) {
      case eventVotePermissionInvitedOnly:
        return const _Badge(
          label: 'Invite only',
          icon: Icons.mail_rounded,
          color: EventBadgeColors.licenseInvitedOnly,
        );
      case eventVotePermissionLocationTimeRestricted:
        return const _Badge(
          label: 'Time & place restricted',
          icon: Icons.schedule_rounded,
          color: EventBadgeColors.licenseLocationTimeRestricted,
        );
      case eventVotePermissionEveryone:
      default:
        return const _Badge(
          label: 'Everyone can vote',
          icon: Icons.how_to_vote_rounded,
          color: EventBadgeColors.licenseEveryone,
        );
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.icon, required this.color});

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

/// Renders an event's cover — its [EventCoverPreset], or a gradient
/// fallback if `event.coverPreset` doesn't match a known preset (or the
/// asset fails to load). Mirrors `PlaylistCoverThumb` in
/// `lib/playlists/playlist_widgets.dart`, minus the uploaded-image case —
/// events only support bundled presets.
class EventCoverThumb extends StatelessWidget {
  const EventCoverThumb({super.key, required this.coverPreset, required this.size, required this.radius});

  final String coverPreset;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final preset = EventCoverPreset.byId(coverPreset);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: preset == null
            ? _EventCoverFallback(size: size)
            : Image.asset(
                preset.assetPath,
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorBuilder: (_, _, _) => _EventCoverFallback(size: size),
              ),
      ),
    );
  }
}

class _EventCoverFallback extends StatelessWidget {
  const _EventCoverFallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8083FF), Color(0xFF494BD6)],
        ),
      ),
      child: Center(child: Icon(Icons.graphic_eq_rounded, color: Colors.white, size: size * 0.4)),
    );
  }
}

/// A small pulsing red "LIVE" pill, shown on an event card when
/// `event.votingIsOpen` is true (see [Event.votingIsOpen]).
class LiveBadge extends StatefulWidget {
  const LiveBadge({super.key});

  static const color = Color(0xFFF87171);

  @override
  State<LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<LiveBadge> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: LiveBadge.color, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween(begin: 0.35, end: 1.0).animate(_controller),
            child: const _Dot(),
          ),
          const SizedBox(width: 6),
          const Text(
            'LIVE',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.4),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
    );
  }
}
