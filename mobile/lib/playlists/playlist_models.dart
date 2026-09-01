import 'package:flutter/material.dart';

/// Allowed values for `Playlist.visibility`
/// (`backend/playlists/models.py`: `Playlist.VISIBILITY_CHOICES`).
const String playlistVisibilityPublic = 'public';
const String playlistVisibilityPrivate = 'private';

/// Allowed values for `Playlist.edit_permission`
/// (`backend/playlists/models.py`: `Playlist.EDIT_PERMISSION_CHOICES`).
const String playlistEditPermissionEveryone = 'everyone';
const String playlistEditPermissionInvitedOnly = 'invited_only';
const String playlistEditPermissionOwnerOnly = 'owner_only';

/// One of the 5 built-in cover looks, as an alternative to uploading a
/// custom [Playlist.coverImageUrl]. Keys mirror
/// `Playlist.COVER_PRESET_CHOICES` in `backend/playlists/models.py`.
/// [assetPath] points at a real bundled piece of generative art (see
/// `mobile/assets/images/playlist_covers/`) — [glowColor] is only used as
/// a subtle accent (selection glow, loading placeholder), not as a
/// stand-in for the image itself.
class PlaylistCoverPreset {
  const PlaylistCoverPreset._(
    this.id,
    this.label,
    this.assetPath,
    this.glowColor,
  );

  final String id;
  final String label;
  final String assetPath;
  final Color glowColor;

  static const sunset = PlaylistCoverPreset._(
    'sunset',
    'Sunset',
    'assets/images/playlist_covers/sunset.jpg',
    Color(0xFFFF7A59),
  );
  static const neon = PlaylistCoverPreset._(
    'neon',
    'Neon',
    'assets/images/playlist_covers/neon.jpg',
    Color(0xFF2FD9F4),
  );
  static const forest = PlaylistCoverPreset._(
    'forest',
    'Forest',
    'assets/images/playlist_covers/forest.jpg',
    Color(0xFF34D399),
  );
  static const ocean = PlaylistCoverPreset._(
    'ocean',
    'Ocean',
    'assets/images/playlist_covers/ocean.jpg',
    Color(0xFF38BDF8),
  );
  static const midnight = PlaylistCoverPreset._(
    'midnight',
    'Midnight',
    'assets/images/playlist_covers/midnight.jpg',
    Color(0xFF7C3AED),
  );

  /// All 5 presets, in the order they're offered when creating a playlist.
  static const all = [sunset, neon, forest, ocean, midnight];

  static PlaylistCoverPreset? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}

/// A collaborative, ordered list of songs, as returned by
/// `GET/POST /api/v1/playlists/` and `GET/PATCH /api/v1/playlists/<id>/`
/// (`PlaylistSerializer`).
class Playlist {
  const Playlist({
    required this.id,
    required this.owner,
    required this.title,
    required this.description,
    required this.visibility,
    required this.editPermission,
    required this.coverImageUrl,
    required this.coverPreset,
    required this.songCount,
    required this.isCollaborator,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    id: json['id'] as int,
    owner: json['owner'] as String? ?? '',
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    visibility: json['visibility'] as String? ?? playlistVisibilityPublic,
    editPermission:
        json['edit_permission'] as String? ?? playlistEditPermissionEveryone,
    coverImageUrl: json['cover_image_url'] as String?,
    coverPreset: json['cover_preset'] as String?,
    songCount: json['song_count'] as int? ?? 0,
    isCollaborator: json['is_collaborator'] as bool? ?? false,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  final int id;

  /// Rendered as `str(user)` by the backend's `StringRelatedField` —
  /// typically the owner's email.
  final String owner;
  final String title;
  final String description;

  /// One of [playlistVisibilityPublic] / [playlistVisibilityPrivate].
  final String visibility;

  /// One of [playlistEditPermissionEveryone] / [playlistEditPermissionInvitedOnly]
  /// / [playlistEditPermissionOwnerOnly].
  final String editPermission;

  /// Server-relative path to an uploaded cover image (e.g.
  /// `/media/playlists/covers/xyz.jpg`), or `null` if none was uploaded —
  /// resolve with `ApiConfig.resolveMediaUrl` before using in `Image.network`.
  /// Takes priority over [coverPreset] when both are somehow present.
  final String? coverImageUrl;

  /// One of [PlaylistCoverPreset.all]'s ids, or `null`/blank if the owner
  /// picked neither a preset nor uploaded an image (falls back to a
  /// generated look).
  final String? coverPreset;
  final int songCount;

  /// Whether the signed-in user is an invited `PlaylistCollaborator` on
  /// this playlist. Always `false` for the owner. Unlike events, there's
  /// no self-serve "join" for playlists — this only ever comes from an
  /// owner invite or an approved access request.
  final bool isCollaborator;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// One song at one position in a playlist, as returned by
/// `GET/POST /api/v1/playlists/<playlist_id>/songs/` and
/// `POST /api/v1/playlists/<playlist_id>/songs/<id>/move/`
/// (`PlaylistSongSerializer`).
///
/// Unlike an event's queue entry, [song] is a bare catalog-song id — title
/// and artist are flattened onto this object as [songTitle]/[songArtist]
/// instead of being nested.
class PlaylistSong {
  const PlaylistSong({
    required this.id,
    required this.playlist,
    required this.song,
    required this.songExternalId,
    required this.songTitle,
    required this.songArtist,
    required this.songAlbumArtUrl,
    required this.songDurationSeconds,
    required this.songPreviewUrl,
    required this.position,
    required this.addedByUsername,
    required this.addedAt,
  });

  factory PlaylistSong.fromJson(Map<String, dynamic> json) => PlaylistSong(
    id: json['id'] as int,
    playlist: json['playlist'] as int,
    song: json['song'] as int,
    songExternalId: json['song_external_id'] as String? ?? '',
    songTitle: json['song_title'] as String? ?? '',
    songArtist: json['song_artist'] as String? ?? '',
    songAlbumArtUrl: json['song_album_art_url'] as String? ?? '',
    songDurationSeconds: json['song_duration_seconds'] as int?,
    songPreviewUrl: json['song_preview_url'] as String? ?? '',
    position: json['position'] as int,
    addedByUsername: json['added_by_username'] as String?,
    addedAt: DateTime.parse(json['added_at'] as String),
  );

  final int id;
  final int playlist;

  /// Catalog `Song` id (`events.Song`, shared with the events app).
  final int song;
  final String songExternalId;
  final String songTitle;
  final String songArtist;

  /// Cover art pulled from Deezer at add-time (blank for songs added
  /// manually, or added before this field existed).
  final String songAlbumArtUrl;
  final int? songDurationSeconds;

  /// 30-second preview clip. Blank for songs added manually or added
  /// before this field existed.
  final String songPreviewUrl;

  /// Zero-based position within the playlist.
  final int position;

  /// Null if the user who added this song has since been deleted
  /// (`added_by` is `SET_NULL` on the backend).
  final String? addedByUsername;
  final DateTime addedAt;
}

/// One person invited to view/edit a private or invited-only-edit
/// playlist, as returned by `GET/POST /api/v1/playlists/<playlist_id>/collaborators/`
/// (`PlaylistCollaboratorSerializer`).
class PlaylistCollaborator {
  const PlaylistCollaborator({
    required this.id,
    required this.playlist,
    required this.collaborator,
    required this.collaboratorUsername,
    required this.collaboratorDisplayName,
    required this.collaboratorAvatar,
    required this.collaboratorAvatarType,
    required this.invitedAt,
    required this.canAddSongs,
    required this.canReorderSongs,
    required this.canManageCollaborators,
  });

  factory PlaylistCollaborator.fromJson(Map<String, dynamic> json) =>
      PlaylistCollaborator(
        id: json['id'] as int,
        playlist: json['playlist'] as int,
        collaborator: json['collaborator'] as int,
        collaboratorUsername: json['collaborator_username'] as String? ?? '',
        collaboratorDisplayName: json['collaborator_display_name'] as String? ?? '',
        collaboratorAvatar: json['collaborator_avatar'] as String?,
        collaboratorAvatarType:
            json['collaborator_avatar_type'] as String? ?? 'preset',
        invitedAt: DateTime.parse(json['invited_at'] as String),
        canAddSongs: json['can_add_songs'] as bool? ?? true,
        canReorderSongs: json['can_reorder_songs'] as bool? ?? true,
        canManageCollaborators:
            json['can_manage_collaborators'] as bool? ?? false,
      );

  final int id;
  final int playlist;

  /// The invited user's id.
  final int collaborator;
  final String collaboratorUsername;
  final String collaboratorDisplayName;

  /// See `UserProfile.avatar` (`profile_models.dart`) — always present,
  /// avatar is public info.
  final String? collaboratorAvatar;

  /// See `UserProfile.avatarType`.
  final String collaboratorAvatarType;
  final DateTime invitedAt;
  final bool canAddSongs;
  final bool canReorderSongs;
  final bool canManageCollaborators;
}

/// Allowed values for `PlaylistAccessRequest.status`
/// (`backend/playlists/models.py`: `PlaylistAccessRequest.STATUS_CHOICES`).
const String playlistAccessRequestPending = 'pending';
const String playlistAccessRequestApproved = 'approved';
const String playlistAccessRequestDenied = 'denied';

/// A request to become a collaborator on a playlist — either to view a
/// private one, or to edit an invited-only one. As returned by
/// `GET/POST /api/v1/playlists/<playlist_id>/access-requests/`,
/// `GET .../access-requests/mine/`, and
/// `POST .../access-requests/<id>/decide/` (`PlaylistAccessRequestSerializer`).
class PlaylistAccessRequest {
  const PlaylistAccessRequest({
    required this.id,
    required this.playlist,
    required this.requester,
    required this.requesterUsername,
    required this.requesterDisplayName,
    required this.requesterAvatar,
    required this.requesterAvatarType,
    required this.status,
    required this.requestedAt,
    required this.decidedAt,
  });

  factory PlaylistAccessRequest.fromJson(Map<String, dynamic> json) =>
      PlaylistAccessRequest(
        id: json['id'] as int,
        playlist: json['playlist'] as int,
        requester: json['requester'] as int,
        requesterUsername: json['requester_username'] as String? ?? '',
        requesterDisplayName: json['requester_display_name'] as String? ?? '',
        requesterAvatar: json['requester_avatar'] as String?,
        requesterAvatarType: json['requester_avatar_type'] as String? ?? 'preset',
        status: json['status'] as String? ?? playlistAccessRequestPending,
        requestedAt: DateTime.parse(json['requested_at'] as String),
        decidedAt: json['decided_at'] == null
            ? null
            : DateTime.parse(json['decided_at'] as String),
      );

  final int id;
  final int playlist;
  final int requester;
  final String requesterUsername;
  final String requesterDisplayName;

  /// See `UserProfile.avatar` (`profile_models.dart`) — always present,
  /// avatar is public info.
  final String? requesterAvatar;

  /// See `UserProfile.avatarType`.
  final String requesterAvatarType;

  /// One of [playlistAccessRequestPending] / [playlistAccessRequestApproved]
  /// / [playlistAccessRequestDenied].
  final String status;
  final DateTime requestedAt;
  final DateTime? decidedAt;
}

/// One track from `GET /api/v1/tracks/search/?q=...`. Audius results have a
/// legal full stream; Deezer results remain 30-second previews.
class TrackSearchResult {
  const TrackSearchResult({
    required this.externalId,
    required this.title,
    required this.artist,
    required this.albumArtUrl,
    required this.previewUrl,
    required this.durationSeconds,
    required this.playbackType,
  });

  factory TrackSearchResult.fromJson(Map<String, dynamic> json) =>
      TrackSearchResult(
        externalId: json['external_id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        albumArtUrl: json['album_art_url'] as String? ?? '',
        previewUrl: json['preview_url'] as String? ?? '',
        durationSeconds: json['duration_seconds'] as int?,
        playbackType: json['playback_type'] as String? ?? 'preview',
      );

  final String externalId;
  final String title;
  final String artist;
  final String albumArtUrl;

  /// A full Audius stream or a 30-second Deezer preview, depending on
  /// [playbackType].
  final String previewUrl;
  final int? durationSeconds;
  final String playbackType;

  bool get hasFullPlayback => playbackType == 'full';
}
