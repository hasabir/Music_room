# Events & Playlists API Reference

Generated from backend source (`backend/events/`, `backend/playlists/`) as of 2026-08-30. This is a read-only reference of exact request/response shapes — not documentation of intent, just what the code does.

All endpoints require `IsAuthenticated` (a valid auth token) unless noted. Base prefix: `/api/v1/` (from `backend/config/urls.py` → `backend/api/urls.py`).

---

## Table of contents — Events

| Method | Path | View |
|---|---|---|
| GET, POST | `/api/v1/events/` | `EventListCreateView` |
| GET, PUT, PATCH, DELETE | `/api/v1/events/<pk>/` | `EventDetailView` |
| GET, POST | `/api/v1/events/<event_id>/queue/` | `EventQueueView` |
| POST, DELETE | `/api/v1/events/<event_id>/queue/<event_song_id>/vote/` | `VoteView` |
| GET, POST | `/api/v1/events/<event_id>/guests/` | `EventGuestListView` |
| DELETE | `/api/v1/events/<event_id>/guests/<user_id>/` | `EventGuestRemoveView` |
| POST | `/api/v1/events/<event_id>/join/` | `EventJoinView` |

## Table of contents — Playlists

| Method | Path | View |
|---|---|---|
| GET, POST | `/api/v1/playlists/` | `PlaylistListCreateView` |
| GET, PUT, PATCH, DELETE | `/api/v1/playlists/<pk>/` | `PlaylistDetailView` |
| GET, POST | `/api/v1/playlists/<playlist_id>/songs/` | `PlaylistSongListView` |
| DELETE | `/api/v1/playlists/<playlist_id>/songs/<playlist_song_id>/` | `PlaylistSongDeleteView` |
| POST | `/api/v1/playlists/<playlist_id>/songs/<playlist_song_id>/move/` | `PlaylistSongMoveView` |
| GET, POST | `/api/v1/playlists/<playlist_id>/collaborators/` | `PlaylistCollaboratorListView` |
| DELETE | `/api/v1/playlists/<playlist_id>/collaborators/<user_id>/` | `PlaylistCollaboratorRemoveView` |

---

## Events

### Visibility & vote permission — exact fields and values

`Event` model fields (`backend/events/models.py`):

- **`visibility`** (`CharField`, max_length=10, default `"public"`) — allowed values:
  - `"public"` — anyone can find and join
  - `"private"` — invite only
- **`vote_permission`** (`CharField`, max_length=30, default `"everyone"`) — allowed values:
  - `"everyone"` — any user who can see the event can vote
  - `"invited_only"` — only the host and invited guests (`EventGuest` rows) can vote
  - `"location_time_restricted"` — only people at the venue, during the time window, can vote
- **`cover_preset`** (`CharField`, max_length=20, default `"party"`) — the bundled visual chosen for the event. Allowed values: `"party"`, `"night_vibe"`, `"dj"`, `"summer_vibe"`, `"rain"`, `"coding_vibe"`, `"after_dark"`, `"vibes"`.

**Location+time-boxed license is represented as flat fields directly on `Event`** — not a separate model. These fields are `null=True, blank=True` and are only meaningful/required when `vote_permission == "location_time_restricted"`:

| Field | Type | Notes |
|---|---|---|
| `venue_center_latitude` | float | center of allowed voting radius |
| `venue_center_longitude` | float | center of allowed voting radius |
| `allowed_distance_meters` | positive integer | max distance from center, in meters (haversine, straight-line) |
| `voting_opens_at` | datetime (ISO 8601) | voting window start |
| `voting_closes_at` | datetime (ISO 8601) | voting window end |

`EventSerializer.validate()` enforces that when `vote_permission` is set (or already is) `"location_time_restricted"`, all five of the above fields must be non-null (on the incoming payload or the existing instance for PATCH) — otherwise a 400 with `{"detail": "These fields are required when vote_permission is 'location_time_restricted': <missing field names>"}`.

At vote time (`VoteView.post`), the request body must additionally carry `latitude`/`longitude` (see below) — those are per-request, not stored on the model.

### `GET /api/v1/events/`

List all public events, plus private events the caller hosts or is invited to (`EventGuest`).

- Query params: none.
- Response: `200`, array of Event objects (see shape below).

### `POST /api/v1/events/`

Creates an event; caller becomes host.

**Request body** (`EventSerializer`, writable fields):

```json
{
  "title": "string, max 100 chars, required",
  "cover_preset": "one of the bundled event-cover preset ids, optional, default \"party\"",
  "visibility": "\"public\" | \"private\", optional, default \"public\"",
  "vote_permission": "\"everyone\" | \"invited_only\" | \"location_time_restricted\", optional, default \"everyone\"",
  "venue_center_latitude": "float, optional (required if vote_permission=location_time_restricted)",
  "venue_center_longitude": "float, optional (required if vote_permission=location_time_restricted)",
  "allowed_distance_meters": "positive integer, optional (required if vote_permission=location_time_restricted)",
  "voting_opens_at": "ISO 8601 datetime, optional (required if vote_permission=location_time_restricted)",
  "voting_closes_at": "ISO 8601 datetime, optional (required if vote_permission=location_time_restricted)"
}
```

**Response `201`** — full Event object:

```json
{
  "id": 1,
  "host": "user@example.com",
  "title": "string",
  "cover_preset": "party",
  "visibility": "public",
  "vote_permission": "everyone",
  "venue_center_latitude": null,
  "venue_center_longitude": null,
  "allowed_distance_meters": null,
  "voting_opens_at": null,
  "voting_closes_at": null,
  "song_count": 0,
  "voting_is_open": false,
  "created_at": "2026-08-30T12:00:00Z",
  "updated_at": "2026-08-30T12:00:00Z"
}
```

Field notes:
- `host` — `StringRelatedField`, read-only. Renders as `str(user)` (see `user` app for `__str__`, typically the email).
- `song_count` — read-only computed property, `event.queue.count()`.
- `voting_is_open` — read-only computed property, `True` iff `song_count >= 2`. This is *only* the "enough songs" gate; it does **not** account for `vote_permission` rules (location/time/invite) — those are checked separately per-request in `can_user_vote`.
- `created_at` / `updated_at` — auto-managed timestamps (`auto_now_add` / `auto_now`). `updated_at` is the only per-event mutation marker; there is no separate `version` field (see "Concurrency" section below).

Throttle: `CreateEventRateThrottle` (scope `create_event`).

### `GET /api/v1/events/<pk>/`

Returns one Event object (same shape as above). 403 if caller can't see it (`can_user_see_event`: public, or host, or invited guest).

### `PUT` / `PATCH /api/v1/events/<pk>/`

Host-only (403 otherwise: `"Only the host can edit this event."`). Same request/response shape as create. `PATCH` allows partial fields; the `location_time_restricted` required-fields validation still applies, checked against incoming attrs falling back to the existing instance's current values.

### `DELETE /api/v1/events/<pk>/`

Host-only (403 otherwise: `"Only the host can delete this event."`). Response `204`, no body. Cascades to delete the event's entire queue/votes.

### `GET /api/v1/events/<event_id>/queue/`

Lists the event's song queue, **sorted by vote count descending** (computed in Python via `sorted(..., key=lambda es: es.vote_count, reverse=True)`, not a DB-level order).

- 403 if caller can't see the event: `{"detail": "You do not have access to this event."}`
- Response `200`: array of EventSong objects (shape below).

### `POST /api/v1/events/<event_id>/queue/`

Adds a song to the event's queue. Reuses an existing catalog `Song` (case-insensitive title+artist match) or creates one.

**Request body** (`AddSongToQueueSerializer`):

```json
{
  "title": "string, max 200 chars, required",
  "artist": "string, max 200 chars, required",
  "duration_seconds": "integer, optional, nullable",
  "external_id": "string, max 100 chars, optional, blank allowed"
}
```

**Response `201`** — EventSong object:

```json
{
  "id": 1,
  "event": 1,
  "song": {
    "id": 1,
    "external_id": "",
    "title": "string",
    "artist": "string",
    "duration_seconds": null
  },
  "added_by_email": "user@example.com",
  "status": "queued",
  "vote_count": 0,
  "has_voted": false,
  "added_at": "2026-08-30T12:00:00Z"
}
```

Field notes on `EventSong` (queue entry):
- `id` — the `EventSong` row id (this is the id used in the vote/move-type URLs, i.e. `event_song_id`).
- `event` — event id (PK, `PrimaryKeyRelatedField` via ModelSerializer default).
- `song` — nested read-only `SongSerializer`: `{id, external_id, title, artist, duration_seconds}`.
- `added_by_email` — email of the user who added the song (`SET_NULL` on user delete, so can be absent).
- `status` — one of `"queued"`, `"playing"`, `"played"` (`EventSong.STATUS_CHOICES`). Note: **no endpoint in this codebase currently transitions `status`** — it's set via admin/other logic outside events/views.py, defaults to `"queued"`.
- `vote_count` — read-only computed property, `self.votes.count()`.
- `has_voted` — `SerializerMethodField`, `True` if the *requesting* user has an existing `Vote` on this `EventSong`; `False` for anonymous/unauthenticated context.
- `added_at` — `auto_now_add` timestamp. **This is the only ordering/concurrency-relevant timestamp on a queue entry** — there is no `updated_at` or `version` field on `EventSong`.

Errors:
- `403` if caller can't see the event.
- `400` `{"detail": "This song is already in the queue."}` if an `EventSong` for that `(event, song)` pair already exists (enforced by `unique_together` on the model, checked via `get_or_create`).

Throttle: `AddSongRateThrottle` (scope `add_song`).

### `POST /api/v1/events/<event_id>/queue/<event_song_id>/vote/`

Casts a vote for a song.

**Request body** — optional, only meaningful when the event's `vote_permission == "location_time_restricted"`:

```json
{
  "latitude": "number, required only for location_time_restricted events",
  "longitude": "number, required only for location_time_restricted events"
}
```
Read via `request.data.get("latitude")` / `.get("longitude")` (not a DRF serializer — no type coercion/validation beyond what JSON parsing gives; passed straight into the haversine distance function).

Permission logic (`can_user_vote` in `backend/events/permissions.py`), evaluated in order:
1. Caller must be able to see the event (`can_user_see_event`) → else `403 {"detail": "You do not have access to this event."}`
2. `event.voting_is_open` must be true (≥2 songs in queue) → else `403 {"detail": "At least 2 songs must be in the queue before voting can start."}`
3. If `vote_permission == "everyone"` → allowed.
4. If `vote_permission == "invited_only"` → allowed iff host or in `EventGuest` list, else `403 {"detail": "Only invited guests can vote on this event."}`
5. If `vote_permission == "location_time_restricted"`:
   - `now < voting_opens_at` → `403 {"detail": "Voting has not opened yet for this event."}`
   - `now > voting_closes_at` → `403 {"detail": "Voting has closed for this event."}`
   - missing `latitude`/`longitude` in request → `403 {"detail": "Your location is required to vote on this event."}`
   - haversine distance from `(venue_center_latitude, venue_center_longitude)` to `(latitude, longitude)` > `allowed_distance_meters` → `403 {"detail": "You must be near the event venue to vote."}`
   - else allowed.

Note: all `can_user_vote` failures return **403**, not the `400` implied by the `extend_schema` docstring in the view — the docstring is aspirational/slightly stale relative to the actual status codes.

**Response `201`** on success:
```json
{"detail": "Vote recorded.", "vote_count": 3}
```

**Response `400`** if already voted (unique constraint `(event_song, voter)` violated → `IntegrityError` caught):
```json
{"detail": "You have already voted for this song."}
```

Throttle: `VoteRateThrottle` (scope `vote`).

### `DELETE /api/v1/events/<event_id>/queue/<event_song_id>/vote/`

Retracts the caller's own vote on that song, if any.

**Response `200`**:
```json
{"detail": "Vote retracted.", "vote_count": 2}
```

**Response `400`** if no vote existed to retract:
```json
{"detail": "You have not voted for this song."}
```

No request body. No explicit permission gate beyond `IsAuthenticated` (does not re-check `can_user_see_event`/`can_user_vote`).

### `GET /api/v1/events/<event_id>/guests/`

Lists an event's guest list (`EventGuest` rows). Visible to host, invited guests, or if the event is public.

**Response `200`** — array:
```json
[
  {
    "id": 1,
    "event": 1,
    "guest": 5,
    "guest_email": "guest@example.com",
    "invited_at": "2026-08-30T12:00:00Z"
  }
]
```
`403 {"detail": "You do not have access to this event."}` otherwise.

### `POST /api/v1/events/<event_id>/guests/`

Host-only. Invites a user (grants `invited_only` voting rights / private-event visibility).

**Request body** (`InviteGuestSerializer`):
```json
{"user_id": "integer, required"}
```

**Response `201`** — EventGuest object (same shape as list item above).

Errors:
- `403 {"detail": "Only the host can invite guests."}` — non-host caller.
- `400 {"detail": "You cannot invite yourself — you're already the host."}` — `user_id == request.user.id`.
- `404` — `user_id` doesn't resolve to a `User` (`get_object_or_404`).
- `400 {"detail": "This user is already invited."}` — duplicate `EventGuest`.

### `DELETE /api/v1/events/<event_id>/guests/<user_id>/`

Host-only. Removes a guest by their user id (path param, not body).

**Response `204`**, no body.

Errors:
- `403 {"detail": "Only the host can remove guests."}`
- `404 {"detail": "This user is not invited to the event."}`

### `POST /api/v1/events/<event_id>/join/`

Self-serve join for a **public** event. Creates an `EventMembership` row — explicitly separate from `EventGuest` (does not grant `invited_only` voting rights).

No request body.

**Response `201`** — EventMembership object:
```json
{
  "id": 1,
  "event": 1,
  "member": 7,
  "joined_at": "2026-08-30T12:00:00Z"
}
```

Errors:
- `400 {"detail": "You are the host of this event."}` — host tries to join own event.
- `403 {"detail": "This event is private — you must be invited by the host."}` — private event.
- `400 {"detail": "You have already joined this event."}` — duplicate membership.

---

## Playlists

### Visibility & edit permission — exact fields and values

`Playlist` model fields (`backend/playlists/models.py`):

- **`visibility`** (`CharField`, max_length=10, default `"public"`) — allowed values:
  - `"public"` — anyone can view
  - `"private"` — invite only
- **`edit_permission`** (`CharField`, max_length=20, default `"everyone"`) — allowed values:
  - `"everyone"` — everyone *with view access* can edit (i.e. owner, or anyone if `visibility=public`, or invited collaborators if private)
  - `"invited_only"` — only the owner and invited collaborators (`PlaylistCollaborator` rows) can edit

There is no location/time-boxed license concept on playlists (that's events-only). Edit permission is a plain open-vs-invited-only toggle, evaluated by `can_user_edit_playlist`:
1. Caller must first pass `can_user_see_playlist` (public, or owner, or `PlaylistCollaborator`), else `"You do not have access to this playlist."`
2. Owner → always allowed.
3. `edit_permission == "everyone"` → allowed.
4. `edit_permission == "invited_only"` → allowed iff caller is a `PlaylistCollaborator`, else `"Only invited collaborators can edit this playlist."`

### `GET /api/v1/playlists/`

Lists public playlists, plus private ones the caller owns or collaborates on. No query params.

### `POST /api/v1/playlists/`

Creates a playlist; caller becomes owner.

**Request body** (`PlaylistSerializer`, writable fields):
```json
{
  "title": "string, max 100 chars, required",
  "visibility": "\"public\" | \"private\", optional, default \"public\"",
  "edit_permission": "\"everyone\" | \"invited_only\", optional, default \"everyone\""
}
```

**Response `201`** — full Playlist object:
```json
{
  "id": 1,
  "owner": "user@example.com",
  "title": "string",
  "visibility": "public",
  "edit_permission": "everyone",
  "song_count": 0,
  "created_at": "2026-08-30T12:00:00Z",
  "updated_at": "2026-08-30T12:00:00Z"
}
```
- `owner` — `StringRelatedField`, read-only.
- `song_count` — read-only computed property, `self.songs.count()`.
- `updated_at` — `auto_now`, bumps on any playlist-level field save. **Note:** this does *not* bump when songs are added/removed/moved (those are `PlaylistSong` mutations, not `Playlist` saves) — see "Concurrency" below.

Throttle: `CreatePlaylistRateThrottle` (scope `create_playlist`).

### `GET /api/v1/playlists/<pk>/`

Returns one Playlist object. `403 {"detail": "You do not have access to this playlist."}` if not visible.

### `PUT` / `PATCH /api/v1/playlists/<pk>/`

Owner-only (`403 {"detail": "Only the owner can edit this playlist."}` otherwise). Same shape as create.

### `DELETE /api/v1/playlists/<pk>/`

Owner-only (`403 {"detail": "Only the owner can delete this playlist."}`). `204`, no body.

### `GET /api/v1/playlists/<playlist_id>/songs/`

Lists all songs in the playlist, **DB-ordered by `position` ascending** (`Meta.ordering = ["position"]` on `PlaylistSong`, unlike the events queue which sorts in Python by votes).

`403 {"detail": "You do not have access to this playlist."}` if not visible.

**Response `200`** — array of PlaylistSong objects (shape below).

### `POST /api/v1/playlists/<playlist_id>/songs/`

Adds a song to the end of the playlist (position = current count). Reuses existing catalog `Song` by case-insensitive title+artist match.

**Request body** (`AddSongToPlaylistSerializer`) — identical shape to events:
```json
{
  "title": "string, max 200 chars, required",
  "artist": "string, max 200 chars, required",
  "duration_seconds": "integer, optional, nullable",
  "external_id": "string, max 100 chars, optional, blank allowed"
}
```

**Response `201`** — PlaylistSong object:
```json
{
  "id": 1,
  "playlist": 1,
  "song": 4,
  "song_title": "string",
  "song_artist": "string",
  "position": 0,
  "added_by_email": "user@example.com",
  "added_at": "2026-08-30T12:00:00Z"
}
```

Field notes — **this is a different shape from the events queue entry**:
- `song` here is the raw `song` id (PK, from `ModelSerializer` default field), **not** a nested object — contrast with `EventSongSerializer.song`, which nests the full `SongSerializer`. Song title/artist are instead flattened onto the parent as `song_title`/`song_artist` (`source="song.title"` / `source="song.artist"`).
- `position` — zero-based integer, unique per playlist (DB constraint `unique_position_per_playlist`, deferred).
- No `vote_count` / `has_voted` / `status` fields — playlists don't have voting or play-status, only ordering.
- `added_by_email`, `added_at` — same semantics as events.
- No `updated_at` or `version` field on `PlaylistSong` at all — only `added_at` (immutable, set once).

Errors:
- `403` — `can_user_edit_playlist` failure reason (see permission logic above), e.g. `{"detail": "Only invited collaborators can edit this playlist."}`.
- `400 {"detail": "This song is already in the playlist."}` — checked explicitly in the view before calling the service (via `PlaylistSong.objects.filter(...).exists()`), separate from the `unique_song_per_playlist` DB constraint.

Throttle: `AddPlaylistSongRateThrottle` (scope `add_playlist_song`).

### `DELETE /api/v1/playlists/<playlist_id>/songs/<playlist_song_id>/`

Removes a song from the playlist; all songs after it shift `position` down by 1 (closes the gap), done inside a `select_for_update()` transaction (`remove_song_from_playlist` in `services.py`).

No request body. `204` on success, no body.

Errors:
- `403` — edit-permission failure reason.
- `404 {"detail": "Song not found in this playlist."}`

### `POST /api/v1/playlists/<playlist_id>/songs/<playlist_song_id>/move/`

Reorders one song to `new_position`; songs in between shift by 1 to make room. Runs inside `select_for_update()` row locks (`move_song` in `services.py`) — this is the app's concurrency-safety mechanism for reordering (pessimistic locking, not optimistic version checks — see below).

**Request body** (`MoveSongSerializer`):
```json
{"new_position": "integer, required, min_value=0"}
```
`new_position` is clamped server-side to `[0, current_song_count - 1]` — out-of-range values are silently clamped, not rejected.

**Response `200`** — the updated PlaylistSong object (same shape as the add-song response above), reflecting its new `position`. If `new_position` resolves to the song's current position, the song object is returned unchanged (no-op, still `200`).

Errors:
- `403` — edit-permission failure reason.
- `404 {"detail": "Song not found in this playlist."}`

Throttle: `MoveSongRateThrottle` (scope `move_song`).

### `GET /api/v1/playlists/<playlist_id>/collaborators/`

Lists a playlist's collaborators (`PlaylistCollaborator` rows). Visible to owner, collaborators, or if playlist is public.

**Response `200`** — array:
```json
[
  {
    "id": 1,
    "playlist": 1,
    "collaborator": 5,
    "collaborator_email": "collab@example.com",
    "invited_at": "2026-08-30T12:00:00Z"
  }
]
```
`403 {"detail": "You do not have access to this playlist."}` otherwise.

### `POST /api/v1/playlists/<playlist_id>/collaborators/`

Owner-only. Invites a user as collaborator (grants view on private playlists / edit rights when `edit_permission=invited_only`).

**Request body** (`InviteCollaboratorSerializer`):
```json
{"user_id": "integer, required"}
```

**Response `201`** — PlaylistCollaborator object (same shape as list item above).

Errors:
- `403 {"detail": "Only the owner can invite collaborators."}`
- `400 {"detail": "You cannot invite yourself — you're already the owner."}`
- `404` — bad `user_id`.
- `400 {"detail": "This user is already invited."}`

### `DELETE /api/v1/playlists/<playlist_id>/collaborators/<user_id>/`

Owner-only. `204` on success.

Errors:
- `403 {"detail": "Only the owner can remove collaborators."}`
- `404 {"detail": "This user is not invited to the playlist."}`

---

## Concurrency / versioning fields — summary

There is **no optimistic-concurrency field** (no `version` integer, no ETag, no `If-Match`) anywhere in either app. Concurrency is handled two different ways depending on the object:

- **Votes** (events): protected by a DB `unique_together` constraint on `(event_song, voter)`. A duplicate vote raises `IntegrityError`, caught and turned into `400 {"detail": "You have already voted for this song."}`. No lost-update window for double-voting.
- **Playlist reordering** (`add_song_to_playlist`, `remove_song_from_playlist`, `move_song` in `backend/playlists/services.py`): protected by `select_for_update()` row locks inside `transaction.atomic()` blocks, plus a DB-level `UniqueConstraint(["playlist", "position"], deferrable=Deferrable.DEFERRED)`. Concurrent move/add/remove requests on the same playlist serialize against each other (the second waits for the first transaction to commit) rather than being detected/rejected via a version field.
- Timestamp fields that exist but are **not** used for concurrency control by any endpoint:
  - `Event.updated_at` / `Playlist.updated_at` — `auto_now`, bump on any parent-object save (PUT/PATCH), not on queue/song sub-object mutations.
  - `EventSong.added_at`, `PlaylistSong.added_at`, `EventGuest.invited_at`, `PlaylistCollaborator.invited_at`, `EventMembership.joined_at`, `Vote.created_at` — all `auto_now_add`, immutable "created" timestamps only.
- Frontend implication: if a client needs to detect "did this queue/playlist change under me," it must diff `song_count`/`vote_count`/`position` values from a fresh GET, or rely on the WebSocket broadcast (`broadcast_queue_update` / `broadcast_playlist_update`, sent via Django Channels — see `backend/events/consumers.py` / `backend/playlists/consumers.py`) rather than any HTTP version field.
