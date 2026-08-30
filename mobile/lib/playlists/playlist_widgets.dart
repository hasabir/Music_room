import 'package:flutter/material.dart';

import '../core/api/api_config.dart';
import 'playlist_models.dart';

class PlaylistBadgeColors {
  const PlaylistBadgeColors._();

  static const visibilityPublic = Color(0xFF2FD9F4);
  static const visibilityPrivate = Color(0xFF908FA0);
  static const editEveryone = Color(0xFF6C6FF0);
  static const editInvitedOnly = Color(0xFFE05FA8);
  static const editOwnerOnly = Color(0xFF908FA0);
}

/// A small pill showing a playlist's `visibility` ([playlistVisibilityPublic]
/// / [playlistVisibilityPrivate]), styled like the visibility/friends
/// badges on the Profile screen (`lib/profile/personal_profile.dart`).
class VisibilityBadge extends StatelessWidget {
  const VisibilityBadge({super.key, required this.visibility});

  final String visibility;

  @override
  Widget build(BuildContext context) {
    final isPublic = visibility == playlistVisibilityPublic;
    return _Badge(
      label: isPublic ? 'Public' : 'Private',
      icon: isPublic ? Icons.public_rounded : Icons.lock_rounded,
      color: isPublic ? PlaylistBadgeColors.visibilityPublic : PlaylistBadgeColors.visibilityPrivate,
    );
  }
}

/// A small pill showing a playlist's `edit_permission`
/// ([playlistEditPermissionEveryone] / [playlistEditPermissionInvitedOnly]
/// / [playlistEditPermissionOwnerOnly]).
class EditPermissionBadge extends StatelessWidget {
  const EditPermissionBadge({super.key, required this.editPermission});

  final String editPermission;

  @override
  Widget build(BuildContext context) {
    switch (editPermission) {
      case playlistEditPermissionEveryone:
        return const _Badge(label: 'Open Edit', icon: Icons.edit_rounded, color: PlaylistBadgeColors.editEveryone);
      case playlistEditPermissionOwnerOnly:
        return const _Badge(
          label: 'Only Me',
          icon: Icons.lock_person_rounded,
          color: PlaylistBadgeColors.editOwnerOnly,
        );
      default:
        return const _Badge(
          label: 'Invite Only',
          icon: Icons.group_rounded,
          color: PlaylistBadgeColors.editInvitedOnly,
        );
    }
  }
}

/// A playlist's cover, wherever it's shown: an uploaded image if
/// [Playlist.coverImageUrl] is set, the chosen [PlaylistCoverPreset]
/// gradient if [Playlist.coverPreset] is set, or a generated gradient +
/// icon as a last resort (matches the look every playlist had before
/// covers existed).
class PlaylistCoverThumb extends StatelessWidget {
  const PlaylistCoverThumb({super.key, required this.playlist, required this.size, required this.radius});

  final Playlist playlist;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final imageUrl = ApiConfig.resolveMediaUrl(playlist.coverImageUrl);
    final preset = PlaylistCoverPreset.byId(playlist.coverPreset);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: imageUrl != null
            ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _PresetOrFallback(preset: preset, size: size),
              )
            : _PresetOrFallback(preset: preset, size: size),
      ),
    );
  }
}

class _PresetOrFallback extends StatelessWidget {
  const _PresetOrFallback({required this.preset, required this.size});

  final PlaylistCoverPreset? preset;
  final double size;

  static const _fallbackColors = [Color(0xFF8083FF), Color(0xFF494BD6)];

  @override
  Widget build(BuildContext context) {
    if (preset != null) {
      return Image.asset(preset!.assetPath, fit: BoxFit.cover, width: size, height: size);
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: _fallbackColors),
      ),
      child: Center(child: Icon(Icons.graphic_eq_rounded, color: Colors.white, size: size * 0.45)),
    );
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
