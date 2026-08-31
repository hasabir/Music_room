import 'package:flutter/material.dart';

/// Allowed values for `Event.visibility`
/// (`backend/events/models.py`: `Event.VISIBILITY_CHOICES`).
const String eventVisibilityPublic = 'public';
const String eventVisibilityPrivate = 'private';

/// Allowed values for `Event.vote_permission` — who's allowed to vote at
/// all (`backend/events/models.py`: `Event.VOTE_PERMISSION_CHOICES`).
/// Independent of [Event.timeRestrictionEnabled] /
/// [Event.locationRestrictionEnabled] below — either permission level can
/// be combined with either restriction, both, or neither (e.g.
/// "everyone can vote, but only 4-6pm", or "invited only, must be at the
/// venue, 4-6pm"). There used to be a third value here,
/// `location_time_restricted`, that bundled a time window and a location
/// check together as one inseparable option with no `invited_only` guest
/// gate at all — see DECISIONS.md, "Event voting restrictions: split
/// location_time_restricted into two composable booleans".
const String eventVotePermissionEveryone = 'everyone';
const String eventVotePermissionInvitedOnly = 'invited_only';

/// Allowed values for `Event.status` — the event's own lifecycle phase,
/// distinct from [eventVotePermissionEveryone]/[eventVotePermissionInvitedOnly]
/// (who can vote) and the restriction toggles (when/where).
///
/// [eventStatusLive]/[eventStatusClosed]/[eventStatusCanceled] are
/// host-only to change, via `PATCH /events/<id>/` — see
/// `EventSettingsScreen`:
/// - [eventStatusLive] (default) — open as normal.
/// - [eventStatusClosed] — still fully viewable/joinable/votable, but
///   [event_api.dart]'s `addToQueue` will 403: no new track suggestions.
/// - [eventStatusCanceled] — nobody but the host can access the event at
///   all anymore, even someone who'd already joined or been invited
///   before the cancellation (`can_user_see_event` in
///   `backend/events/permissions.py`).
///
/// The other three are the opposite: fully automatic, never sent by this
/// client, never selectable in `EventSettingsScreen` — the backend's
/// `Event.sync_activity_status()` sets them on its own, purely based on
/// how long the event has gone without a new track suggestion, and drops
/// straight back to [eventStatusLive] the instant one is added. They
/// behave exactly like [eventStatusLive] everywhere — voting, joining,
/// and suggesting tracks all stay fully open — this is a display-only
/// label, never a restriction: [eventStatusGhostTown] 👻, then
/// [eventStatusRipAttendance], then [eventStatusPartyOfNobody].
const String eventStatusLive = 'live';
const String eventStatusClosed = 'closed';
const String eventStatusCanceled = 'canceled';
const String eventStatusGhostTown = 'ghost_town';
const String eventStatusRipAttendance = 'rip_attendance';
const String eventStatusPartyOfNobody = 'party_of_nobody';

/// True for any of the three automatic inactivity statuses above — i.e.
/// "this event is still fully live/functional, just labeled as quiet."
/// Never true for [eventStatusClosed]/[eventStatusCanceled], which
/// actually do restrict something.
bool eventStatusIsAutoInactive(String status) => switch (status) {
  eventStatusGhostTown || eventStatusRipAttendance || eventStatusPartyOfNobody => true,
  _ => false,
};

/// One of the built-in event cover looks, saved as `Event.cover_preset`
/// (`backend/events/models.py`: `Event.COVER_PRESET_CHOICES`). Mirrors
/// `PlaylistCoverPreset` in `lib/playlists/playlist_models.dart` — events
/// don't support an uploaded custom cover, only these bundled presets.
class EventCoverPreset {
  const EventCoverPreset._(this.id, this.label, this.assetPath, this.glowColor);

  final String id;
  final String label;
  final String assetPath;
  final Color glowColor;

  static const party = EventCoverPreset._(
    'party',
    'Party',
    'assets/images/event_covers/party.jpg',
    Color(0xFFFF7A59),
  );
  static const nightVibe = EventCoverPreset._(
    'night_vibe',
    'Night vibe',
    'assets/images/event_covers/night_vibe.jpg',
    Color(0xFF818CF8),
  );
  static const dj = EventCoverPreset._(
    'dj',
    'DJ',
    'assets/images/event_covers/dj.jpg',
    Color(0xFF2FD9F4),
  );
  static const summerVibe = EventCoverPreset._(
    'summer_vibe',
    'Summer',
    'assets/images/event_covers/summer_vibe.jpg',
    Color(0xFFFBBF24),
  );
  static const rain = EventCoverPreset._(
    'rain',
    'Rain',
    'assets/images/event_covers/rain.jpg',
    Color(0xFF38BDF8),
  );
  static const codingVibe = EventCoverPreset._(
    'coding_vibe',
    'Coding',
    'assets/images/event_covers/coding_vibe.jpg',
    Color(0xFF34D399),
  );
  static const afterDark = EventCoverPreset._(
    'after_dark',
    'After dark',
    'assets/images/event_covers/pexels-baskincreativeco.jpg',
    Color(0xFFA78BFA),
  );
  static const vibes = EventCoverPreset._(
    'vibes',
    'Vibes',
    'assets/images/event_covers/image.jpg',
    Color(0xFFF472B6),
  );

  /// All 8 presets, in the order they're offered when creating an event.
  static const all = [party, nightVibe, dj, summerVibe, rain, codingVibe, afterDark, vibes];

  static EventCoverPreset? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}

/// Allowed values for `EventSong.status`
/// (`backend/events/models.py`: `EventSong.STATUS_CHOICES`). The backend
/// alone drives every transition, via `Event.sync_current_song` — see
/// DECISIONS.md. A song starts [eventSongStatusQueued]; the highest-voted
/// song becomes [eventSongStatusPlaying]; once its playable duration has
/// genuinely elapsed by wall-clock time it becomes [eventSongStatusPlayed]
/// and the backend excludes it from `listQueue` for good. A song that
/// gets outvoted mid-play goes back to [eventSongStatusQueued] rather
/// than [eventSongStatusPlayed] — it can win the lead again later. The
/// client never sets any of this itself; it only ever displays
/// [Event.currentSong].
const String eventSongStatusQueued = 'queued';
const String eventSongStatusPlaying = 'playing';
const String eventSongStatusPlayed = 'played';

/// Allowed values for `Song.playback_type`
/// (`backend/events/models.py`: `Song.PLAYBACK_TYPE_CHOICES`). Determines
/// how long the backend treats a song as playing for — see
/// `Song.effective_duration_seconds` on the backend model.
const String songPlaybackTypePreview = 'preview';
const String songPlaybackTypeFull = 'full';

/// Mirrors `Song.PREVIEW_CLIP_SECONDS` on the backend
/// (`backend/events/models.py`) — how long a Deezer [songPlaybackTypePreview]
/// clip's *actual audio* runs for. The backend may treat such a song as
/// authoritatively "current" for much longer than this (its real,
/// full-length `duration_seconds` — see DECISIONS.md), but the file behind
/// `previewUrl` never contains more than this many seconds of sound, no
/// matter what. `EventDetailScreen` uses this to keep local playback
/// looping within the clip's real bounds — seeking or waiting past it
/// would just be silence.
const int songPreviewClipSeconds = 30;

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
    required this.status,
    required this.votePermission,
    required this.timeRestrictionEnabled,
    required this.locationRestrictionEnabled,
    required this.venueCenterLatitude,
    required this.venueCenterLongitude,
    required this.allowedDistanceMeters,
    required this.votingOpensAt,
    required this.votingClosesAt,
    required this.songCount,
    required this.votingIsOpen,
    required this.currentSong,
    required this.currentPositionSeconds,
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
    status: json['status'] as String? ?? eventStatusLive,
    votePermission:
        json['vote_permission'] as String? ?? eventVotePermissionEveryone,
    timeRestrictionEnabled: json['time_restriction_enabled'] as bool? ?? false,
    locationRestrictionEnabled:
        json['location_restriction_enabled'] as bool? ?? false,
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
    currentSong: json['current_song'] == null
        ? null
        : EventSong.fromJson(json['current_song'] as Map<String, dynamic>),
    currentPositionSeconds: (json['current_position_seconds'] as num?)
        ?.toDouble(),
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

  /// One of [eventStatusLive] / [eventStatusClosed] / [eventStatusCanceled]
  /// — the event's own lifecycle phase. Host-only to change (see
  /// [eventStatusLive]'s doc comment for what each value means).
  final String status;

  /// One of [eventVotePermissionEveryone] / [eventVotePermissionInvitedOnly]
  /// — who's allowed to vote at all. Independent of the two restriction
  /// toggles below.
  final String votePermission;

  /// Gates [votingOpensAt]/[votingClosesAt] — when `true`, voting is only
  /// allowed inside that window, regardless of [votePermission] or
  /// [locationRestrictionEnabled]. Required together with both of those
  /// fields when enabled (`EventSerializer.validate()`).
  final bool timeRestrictionEnabled;

  /// Gates [venueCenterLatitude]/[venueCenterLongitude]/
  /// [allowedDistanceMeters] — when `true`, voting is only allowed within
  /// range of the venue, regardless of [votePermission] or
  /// [timeRestrictionEnabled]. Required together with all three of those
  /// fields when enabled.
  final bool locationRestrictionEnabled;

  /// Only meaningful/required when [locationRestrictionEnabled] is `true`.
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

  /// The backend's authoritative "on air" song right now — see
  /// DECISIONS.md. `null` once every song has been played, or the queue
  /// is empty. This, not any local computation, is what the client
  /// displays and plays; it's recomputed fresh (and can change) on every
  /// fetch of this event, since the backend advances it purely by
  /// wall-clock time regardless of whether anyone's connected.
  final EventSong? currentSong;

  /// How far into [currentSong] playback is right now, in seconds,
  /// derived by the backend from its own stored start timestamp — never
  /// from anything a client reports. `null` iff [currentSong] is `null`.
  /// A newly joining or rejoining client should start local playback at
  /// this position, not from 0, to land wherever everyone else already
  /// is.
  final double? currentPositionSeconds;

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
    required this.albumArtUrl,
    required this.previewUrl,
    required this.playbackType,
  });

  factory Song.fromJson(Map<String, dynamic> json) => Song(
    id: json['id'] as int,
    externalId: json['external_id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    artist: json['artist'] as String? ?? '',
    durationSeconds: json['duration_seconds'] as int?,
    albumArtUrl: json['album_art_url'] as String? ?? '',
    previewUrl: json['preview_url'] as String? ?? '',
    playbackType: json['playback_type'] as String? ?? songPlaybackTypePreview,
  );

  final int id;
  final String externalId;
  final String title;
  final String artist;
  final int? durationSeconds;

  /// Cover art pulled from Deezer/Audius at add-time (blank for songs
  /// added manually, or added before this field existed).
  final String albumArtUrl;

  /// 30-second Deezer preview or full Audius stream, resolved at add-time.
  /// Blank for songs added manually. Prefer re-resolving via
  /// `PlaylistApi.resolvePreviewUrl(externalId)` at play-time when
  /// [externalId] is non-empty — this stored value can go stale.
  final String previewUrl;

  /// One of [songPlaybackTypePreview] / [songPlaybackTypeFull]. Purely
  /// informational on the client — it's what the backend uses to decide
  /// how long this song counts as "playing" for (see DECISIONS.md); the
  /// client never computes that itself.
  final String playbackType;
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
    required this.guestUsername,
    required this.guestDisplayName,
    required this.invitedAt,
  });

  factory EventGuest.fromJson(Map<String, dynamic> json) => EventGuest(
    id: json['id'] as int,
    event: json['event'] as int,
    guest: json['guest'] as int,
    guestEmail: json['guest_email'] as String? ?? '',
    guestUsername: json['guest_username'] as String? ?? '',
    guestDisplayName: json['guest_display_name'] as String? ?? '',
    invitedAt: DateTime.parse(json['invited_at'] as String),
  );

  final int id;
  final int event;

  /// The invited user's id.
  final int guest;
  final String guestEmail;
  final String guestUsername;
  final String guestDisplayName;
  final DateTime invitedAt;
}

/// One person who has self-joined an event, as returned by
/// `GET /api/v1/events/<event_id>/attendees/` (`EventMembershipSerializer`)
/// — distinct from [EventGuest], which is who's been *invited*.
class EventMembership {
  const EventMembership({
    required this.id,
    required this.event,
    required this.member,
    required this.memberEmail,
    required this.memberUsername,
    required this.memberDisplayName,
    required this.joinedAt,
  });

  factory EventMembership.fromJson(Map<String, dynamic> json) => EventMembership(
    id: json['id'] as int,
    event: json['event'] as int,
    member: json['member'] as int,
    memberEmail: json['member_email'] as String? ?? '',
    memberUsername: json['member_username'] as String? ?? '',
    memberDisplayName: json['member_display_name'] as String? ?? '',
    joinedAt: DateTime.parse(json['joined_at'] as String),
  );

  final int id;
  final int event;

  /// The joined user's id.
  final int member;
  final String memberEmail;
  final String memberUsername;
  final String memberDisplayName;
  final DateTime joinedAt;
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
