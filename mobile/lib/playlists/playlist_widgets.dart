import 'package:flutter/material.dart';

import 'playlist_models.dart';

class PlaylistBadgeColors {
  const PlaylistBadgeColors._();

  static const visibilityPublic = Color(0xFF2FD9F4);
  static const visibilityPrivate = Color(0xFF908FA0);
  static const editEveryone = Color(0xFF6C6FF0);
  static const editInvitedOnly = Color(0xFFE05FA8);
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
/// ([playlistEditPermissionEveryone] / [playlistEditPermissionInvitedOnly]).
class EditPermissionBadge extends StatelessWidget {
  const EditPermissionBadge({super.key, required this.editPermission});

  final String editPermission;

  @override
  Widget build(BuildContext context) {
    final isOpen = editPermission == playlistEditPermissionEveryone;
    return _Badge(
      label: isOpen ? 'Open Edit' : 'Invite Only',
      icon: isOpen ? Icons.edit_rounded : Icons.group_rounded,
      color: isOpen ? PlaylistBadgeColors.editEveryone : PlaylistBadgeColors.editInvitedOnly,
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
