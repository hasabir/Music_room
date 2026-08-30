/// Allowed values for `Playlist.visibility`
/// (`backend/playlists/models.py`: `Playlist.VISIBILITY_CHOICES`).
const String playlistVisibilityPublic = 'public';
const String playlistVisibilityPrivate = 'private';

/// Allowed values for `Playlist.edit_permission`
/// (`backend/playlists/models.py`: `Playlist.EDIT_PERMISSION_CHOICES`).
const String playlistEditPermissionEveryone = 'everyone';
const String playlistEditPermissionInvitedOnly = 'invited_only';

/// A collaborative, ordered list of songs, as returned by
/// `GET/POST /api/v1/playlists/` and `GET/PATCH /api/v1/playlists/<id>/`
/// (`PlaylistSerializer`).
class Playlist {
  const Playlist({
    required this.id,
    required this.owner,
    required this.title,
    required this.visibility,
    required this.editPermission,
    required this.songCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    id: json['id'] as int,
    owner: json['owner'] as String? ?? '',
    title: json['title'] as String? ?? '',
    visibility: json['visibility'] as String? ?? playlistVisibilityPublic,
    editPermission: json['edit_permission'] as String? ?? playlistEditPermissionEveryone,
    songCount: json['song_count'] as int? ?? 0,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  final int id;

  /// Rendered as `str(user)` by the backend's `StringRelatedField` —
  /// typically the owner's email.
  final String owner;
  final String title;

  /// One of [playlistVisibilityPublic] / [playlistVisibilityPrivate].
  final String visibility;

  /// One of [playlistEditPermissionEveryone] / [playlistEditPermissionInvitedOnly].
  final String editPermission;
  final int songCount;
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
    required this.songTitle,
    required this.songArtist,
    required this.position,
    required this.addedByEmail,
    required this.addedAt,
  });

  factory PlaylistSong.fromJson(Map<String, dynamic> json) => PlaylistSong(
    id: json['id'] as int,
    playlist: json['playlist'] as int,
    song: json['song'] as int,
    songTitle: json['song_title'] as String? ?? '',
    songArtist: json['song_artist'] as String? ?? '',
    position: json['position'] as int,
    addedByEmail: json['added_by_email'] as String?,
    addedAt: DateTime.parse(json['added_at'] as String),
  );

  final int id;
  final int playlist;

  /// Catalog `Song` id (`events.Song`, shared with the events app).
  final int song;
  final String songTitle;
  final String songArtist;

  /// Zero-based position within the playlist.
  final int position;

  /// Null if the user who added this song has since been deleted
  /// (`added_by` is `SET_NULL` on the backend).
  final String? addedByEmail;
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
    required this.collaboratorEmail,
    required this.invitedAt,
  });

  factory PlaylistCollaborator.fromJson(Map<String, dynamic> json) => PlaylistCollaborator(
    id: json['id'] as int,
    playlist: json['playlist'] as int,
    collaborator: json['collaborator'] as int,
    collaboratorEmail: json['collaborator_email'] as String? ?? '',
    invitedAt: DateTime.parse(json['invited_at'] as String),
  );

  final int id;
  final int playlist;

  /// The invited user's id.
  final int collaborator;
  final String collaboratorEmail;
  final DateTime invitedAt;
}
