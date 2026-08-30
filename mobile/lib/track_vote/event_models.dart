/// Allowed values for `Event.visibility`
/// (`backend/events/models.py`: `Event.VISIBILITY_CHOICES`).
const String eventVisibilityPublic = 'public';
const String eventVisibilityPrivate = 'private';

/// Allowed values for `Event.vote_permission`
/// (`backend/events/models.py`: `Event.VOTE_PERMISSION_CHOICES`).
const String eventVotePermissionEveryone = 'everyone';
const String eventVotePermissionInvitedOnly = 'invited_only';
const String eventVotePermissionLocationTimeRestricted =
    'location_time_restricted';

/// Allowed values for `EventSong.status`
/// (`backend/events/models.py`: `EventSong.STATUS_CHOICES`). No endpoint
/// currently transitions this — it's set outside `events/views.py`.
const String eventSongStatusQueued = 'queued';
const String eventSongStatusPlaying = 'playing';
const String eventSongStatusPlayed = 'played';

/// A music-vote event, as returned by `GET/POST /api/v1/events/` and
/// `GET/PUT/PATCH /api/v1/events/<id>/` (`EventSerializer`).
class Event {
  const Event({
    required this.id,
    required this.host,
    required this.title,
    required this.description,
    required this.coverPreset,
    required this.visibility,
    required this.votePermission,
    required this.venueCenterLatitude,
    required this.venueCenterLongitude,
    required this.allowedDistanceMeters,
    required this.votingOpensAt,
    required this.votingClosesAt,
    required this.songCount,
    required this.votingIsOpen,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Event.fromJson(Map<String, dynamic> json) => Event(
    id: json['id'] as int,
    host: json['host'] as String? ?? '',
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    coverPreset: json['cover_preset'] as String? ?? 'party',
    visibility: json['visibility'] as String? ?? eventVisibilityPublic,
    votePermission:
        json['vote_permission'] as String? ?? eventVotePermissionEveryone,
    venueCenterLatitude: (json['venue_center_latitude'] as num?)?.toDouble(),
    venueCenterLongitude: (json['venue_center_longitude'] as num?)?.toDouble(),
    allowedDistanceMeters: json['allowed_distance_meters'] as int?,
    votingOpensAt: json['voting_opens_at'] == null
        ? null
        : DateTime.parse(json['voting_opens_at'] as String),
    votingClosesAt: json['voting_closes_at'] == null
        ? null
        : DateTime.parse(json['voting_closes_at'] as String),
    songCount: json['song_count'] as int? ?? 0,
    votingIsOpen: json['voting_is_open'] as bool? ?? false,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  final int id;

  /// Rendered as `str(user)` by the backend's `StringRelatedField` —
  /// typically the host's email.
  final String host;
  final String title;
  final String description;
  final String coverPreset;

  /// One of [eventVisibilityPublic] / [eventVisibilityPrivate].
  final String visibility;

  /// One of [eventVotePermissionEveryone] / [eventVotePermissionInvitedOnly]
  /// / [eventVotePermissionLocationTimeRestricted].
  final String votePermission;

  /// Only meaningful/required when [votePermission] is
  /// [eventVotePermissionLocationTimeRestricted].
  final double? venueCenterLatitude;
  final double? venueCenterLongitude;
  final int? allowedDistanceMeters;
  final DateTime? votingOpensAt;
  final DateTime? votingClosesAt;

  final int songCount;

  /// Read-only computed property: `true` iff `songCount >= 2`. This is
  /// only the "enough songs queued" gate — it does *not* account for
  /// [votePermission] rules (invite/location/time), which are checked
  /// per-request by the vote endpoint (see [VoteNotPermittedException]).
  final bool votingIsOpen;

  final DateTime createdAt;
  final DateTime updatedAt;
}

/// A catalog song nested inside an [EventSong]
/// (`backend/events/serializers.py`: `SongSerializer`).
///
/// Unlike a playlist entry (which flattens `song_title`/`song_artist` onto
/// the parent), the events queue nests the full song object.
class Song {
  const Song({
    required this.id,
    required this.externalId,
    required this.title,
    required this.artist,
    required this.durationSeconds,
  });

  factory Song.fromJson(Map<String, dynamic> json) => Song(
    id: json['id'] as int,
    externalId: json['external_id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    artist: json['artist'] as String? ?? '',
    durationSeconds: json['duration_seconds'] as int?,
  );

  final int id;
  final String externalId;
  final String title;
  final String artist;
  final int? durationSeconds;
}

/// One song at one position in an event's queue, as returned by
/// `GET/POST /api/v1/events/<event_id>/queue/` (`EventSongSerializer`).
///
/// This is the `event_song_id` used in the vote URL.
class EventSong {
  const EventSong({
    required this.id,
    required this.event,
    required this.song,
    required this.addedByEmail,
    required this.status,
    required this.voteCount,
    required this.hasVoted,
    required this.addedAt,
  });

  factory EventSong.fromJson(Map<String, dynamic> json) => EventSong(
    id: json['id'] as int,
    event: json['event'] as int,
    song: Song.fromJson(json['song'] as Map<String, dynamic>),
    addedByEmail: json['added_by_email'] as String?,
    status: json['status'] as String? ?? eventSongStatusQueued,
    voteCount: json['vote_count'] as int? ?? 0,
    hasVoted: json['has_voted'] as bool? ?? false,
    addedAt: DateTime.parse(json['added_at'] as String),
  );

  final int id;
  final int event;
  final Song song;

  /// Null if the user who added this song has since been deleted
  /// (`added_by` is `SET_NULL` on the backend).
  final String? addedByEmail;

  /// One of [eventSongStatusQueued] / [eventSongStatusPlaying] /
  /// [eventSongStatusPlayed].
  final String status;

  final int voteCount;

  /// Whether the signed-in user has already voted for this song.
  final bool hasVoted;
  final DateTime addedAt;
}

/// One person invited to an event, as returned by
/// `GET/POST /api/v1/events/<event_id>/guests/`
/// (`EventGuestSerializer`).
class EventGuest {
  const EventGuest({
    required this.id,
    required this.event,
    required this.guest,
    required this.guestEmail,
    required this.invitedAt,
  });

  factory EventGuest.fromJson(Map<String, dynamic> json) => EventGuest(
    id: json['id'] as int,
    event: json['event'] as int,
    guest: json['guest'] as int,
    guestEmail: json['guest_email'] as String? ?? '',
    invitedAt: DateTime.parse(json['invited_at'] as String),
  );

  final int id;
  final int event;

  /// The invited user's id.
  final int guest;
  final String guestEmail;
  final DateTime invitedAt;
}

/// Response shape shared by both `POST` (cast) and `DELETE` (retract) on
/// `/api/v1/events/<event_id>/queue/<event_song_id>/vote/`.
class VoteResult {
  const VoteResult({required this.detail, required this.voteCount});

  factory VoteResult.fromJson(Map<String, dynamic> json) => VoteResult(
    detail: json['detail'] as String? ?? '',
    voteCount: json['vote_count'] as int? ?? 0,
  );

  final String detail;
  final int voteCount;
}
