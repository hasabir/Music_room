# Music Room — Events & Playlists API Documentation

Base URL (local dev): `http://localhost:8000/api/v1/`

All requests/responses are JSON. Every endpoint below requires authentication:
```
Authorization: Bearer <access_token>
```

This doc covers the two real-time collaborative services: **Music Track Vote** (Events) and **Music Playlist Editor** (Playlists). See `AUTH_API_DOCS.md` for login/register/profile endpoints.

---

# PART 1 — Events (Music Track Vote)

## Concept summary

An **Event** is a party/session where people add songs to a shared queue and vote on them. The song with the most votes rises to the top — that's what determines what plays next.

- **`Song`** — a general catalog entry (title, artist). Can be reused across many events/playlists.
- **`EventSong`** — one song, added to one specific event's queue. This is what actually gets voted on.
- **`Vote`** — one user's vote for one `EventSong`. One vote per user per song, enforced at the database level.

**Voting only unlocks once an event has at least 2 songs in its queue.**

---

## 1. List My Events

**`GET /events/`**

Returns public events, plus private events you host or are invited to.

**Response — `200 OK`**
```json
[
  {
    "id": 1,
    "host": "khadija@test.com",
    "title": "Birthday Party",
    "visibility": "public",
    "vote_permission": "everyone",
    "venue_center_latitude": null,
    "venue_center_longitude": null,
    "allowed_distance_meters": null,
    "voting_opens_at": null,
    "voting_closes_at": null,
    "song_count": 2,
    "voting_is_open": true,
    "created_at": "2026-08-10T...",
    "updated_at": "2026-08-10T..."
  }
]
```

---

## 2. Create an Event

**`POST /events/`**

| Field | Type | Required | Notes |
|---|---|---|---|
| title | string | yes | |
| visibility | `public` \| `private` | no | defaults to `public` |
| vote_permission | `everyone` \| `invited_only` \| `location_time_restricted` | no | defaults to `everyone` |
| venue_center_latitude | float | only if `location_time_restricted` | |
| venue_center_longitude | float | only if `location_time_restricted` | |
| allowed_distance_meters | integer | only if `location_time_restricted` | max distance from venue center to vote |
| voting_opens_at | datetime (ISO 8601) | only if `location_time_restricted` | |
| voting_closes_at | datetime (ISO 8601) | only if `location_time_restricted` | |

**Simple example**
```json
{
  "title": "Rooftop Party",
  "visibility": "public",
  "vote_permission": "everyone"
}
```

**Location & time restricted example**
```json
{
  "title": "Rooftop Session",
  "visibility": "private",
  "vote_permission": "location_time_restricted",
  "venue_center_latitude": 33.5731,
  "venue_center_longitude": -7.5898,
  "allowed_distance_meters": 200,
  "voting_opens_at": "2026-08-10T16:00:00Z",
  "voting_closes_at": "2026-08-10T18:00:00Z"
}
```

**Success — `201 Created`** — returns the full event object (same shape as list above). The logged-in user automatically becomes the `host`.

**Errors — `400 Bad Request`** — missing required location/time fields when `vote_permission` is `location_time_restricted`.

---

## 3. Get / Update / Delete an Event

**`GET /events/{id}/`** — full event details. Fails with `403` if you can't see it (private + not host/invited).

**`PUT` / `PATCH /events/{id}/`** — update. **Host only** — other users get `403`.

**`DELETE /events/{id}/`** — deletes the event and its entire queue/votes. **Host only.**

---

## 4. List the Song Queue

**`GET /events/{event_id}/queue/`**

Returns all songs in the event's queue, **sorted by vote count, most-voted first.** This is the ranked "what's coming up" list.

**Response — `200 OK`**
```json
[
  {
    "id": 3,
    "event": 1,
    "song": {
      "id": 2,
      "external_id": "",
      "title": "Flowers",
      "artist": "Miley Cyrus",
      "duration_seconds": null
    },
    "added_by_email": "khadija@test.com",
    "status": "queued",
    "vote_count": 3,
    "has_voted": true,
    "added_at": "2026-08-10T..."
  },
  {
    "id": 1,
    "event": 1,
    "song": { "id": 1, "title": "Blinding Lights", "artist": "The Weeknd", "...": "..." },
    "added_by_email": "khadija@test.com",
    "status": "queued",
    "vote_count": 0,
    "has_voted": false,
    "added_at": "2026-08-10T..."
  }
]
```

`has_voted` is specific to the logged-in user making the request — use it to show a filled/unfilled vote button in the UI.

**Errors — `403 Forbidden`** — no access to this event.

---

## 5. Add a Song to the Queue

**`POST /events/{event_id}/queue/`**

| Field | Type | Required |
|---|---|---|
| title | string | yes |
| artist | string | yes |
| duration_seconds | integer | no |
| external_id | string | no — for future music SDK integration |

```json
{
  "title": "Blinding Lights",
  "artist": "The Weeknd",
  "duration_seconds": 200
}
```

**Success — `201 Created`** — returns the new `EventSong` object (same shape as one item in the queue list above, `vote_count: 0`, `has_voted: false`).

**Behavior notes:**
- If a song with the same title+artist already exists in the catalog (case-insensitive), it's reused — no duplicate `Song` rows.
- If the song is **already in this event's queue**, fails with `400`: `"This song is already in the queue."`

**Errors**
- `403` — no access to this event
- `400` — song already in queue, or missing required fields

---

## 6. Vote for a Song

**`POST /events/{event_id}/queue/{event_song_id}/vote/`**

**Body depends on the event's `vote_permission`:**

- `everyone` / `invited_only` → empty body `{}`
- `location_time_restricted` → must include your current location:
```json
{
  "latitude": 33.5731,
  "longitude": -7.5898
}
```

**Success — `201 Created`**
```json
{ "detail": "Vote recorded.", "vote_count": 1 }
```

**Errors — `400 Bad Request`**
| Situation | Message |
|---|---|
| Fewer than 2 songs in queue | "At least 2 songs must be in the queue before voting can start." |
| Already voted for this song | "You have already voted for this song." |

**Errors — `403 Forbidden`**
| Situation | Message |
|---|---|
| Can't see the event | "You do not have access to this event." |
| `invited_only`, not invited | "Only invited guests can vote on this event." |
| Outside voting time window | "Voting has not opened yet for this event." / "Voting has closed for this event." |
| Missing location for restricted event | "Your location is required to vote on this event." |
| Too far from venue | "You must be near the event venue to vote." |

---

## 7. Retract a Vote

**`DELETE /events/{event_id}/queue/{event_song_id}/vote/`**

**Success — `200 OK`**
```json
{ "detail": "Vote retracted.", "vote_count": 0 }
```

**Errors — `400 Bad Request`** — you haven't voted for this song.

---

## 8. Live Updates — WebSocket

Connect to receive the queue in real time whenever anyone votes or adds a song:

```
ws://localhost:8000/ws/events/{event_id}/queue/?token={access_token}
```

**Auth:** pass your JWT access token as a query parameter (not a header — WebSocket clients can't reliably send custom headers).

**Connection closes immediately with:**
- Code `4001` — missing or invalid token
- Code `4003` — you don't have access to this event

**On any queue change, you receive:**
```json
{
  "event_id": 1,
  "queue": [ /* same shape as GET /queue/, already sorted by votes */ ]
}
```

**Mobile app note:** open this connection when the user opens an event's queue screen, close it when they leave. Use it to update the UI live; fall back to `GET /queue/` on initial screen load (the WebSocket only pushes updates, it doesn't send the current state on connect).

---

# PART 2 — Playlists (Music Playlist Editor)

## Concept summary

A **Playlist** is a collaborative, ordered list of songs — think a shared Spotify playlist, editable live by multiple people.

- **`PlaylistSong`** — one song at one position in one playlist. Positions are always gapless integers (0, 1, 2, 3...).
- The same song **cannot** appear twice in one playlist.
- Reordering/removing is handled with database-level locking so simultaneous edits from different users can't corrupt the order.

---

## 1. List My Playlists

**`GET /playlists/`**

Returns public playlists, plus private playlists you own or are invited to.

**Response — `200 OK`**
```json
[
  {
    "id": 1,
    "owner": "khadija@test.com",
    "title": "Road Trip Mix",
    "visibility": "public",
    "edit_permission": "everyone",
    "song_count": 3,
    "created_at": "2026-08-10T...",
    "updated_at": "2026-08-10T..."
  }
]
```

---

## 2. Create a Playlist

**`POST /playlists/`**

| Field | Type | Required | Notes |
|---|---|---|---|
| title | string | yes | |
| visibility | `public` \| `private` | no | defaults to `public` |
| edit_permission | `everyone` \| `invited_only` | no | defaults to `everyone` |

```json
{
  "title": "Road Trip Mix",
  "visibility": "public",
  "edit_permission": "everyone"
}
```

**Success — `201 Created`** — returns the playlist object. Logged-in user becomes `owner`.

---

## 3. Get / Update / Delete a Playlist

**`GET /playlists/{id}/`** — details. `403` if you can't see it.

**`PUT` / `PATCH /playlists/{id}/`** — update. **Owner only.**

**`DELETE /playlists/{id}/`** — deletes the playlist and all its songs. **Owner only.**

---

## 4. List Songs in a Playlist

**`GET /playlists/{playlist_id}/songs/`**

Returns songs **in order** (by position, ascending — this is the actual playlist order).

**Response — `200 OK`**
```json
[
  {
    "id": 1,
    "playlist": 1,
    "song": 4,
    "song_title": "Blinding Lights",
    "song_artist": "The Weeknd",
    "position": 0,
    "added_by_email": "khadija@test.com",
    "added_at": "2026-08-10T..."
  },
  {
    "id": 2,
    "playlist": 1,
    "song": 5,
    "song_title": "Flowers",
    "song_artist": "Miley Cyrus",
    "position": 1,
    "added_by_email": "khadija@test.com",
    "added_at": "2026-08-10T..."
  }
]
```

---

## 5. Add a Song to a Playlist

**`POST /playlists/{playlist_id}/songs/`**

| Field | Type | Required |
|---|---|---|
| title | string | yes |
| artist | string | yes |
| duration_seconds | integer | no |
| external_id | string | no |

```json
{ "title": "Blinding Lights", "artist": "The Weeknd" }
```

**Success — `201 Created`** — new song added at the **end** of the playlist (highest position). Reuses an existing catalog `Song` if the same title/artist already exists (shared with the Events catalog).

**Errors — `400 Bad Request`** — this song is already in the playlist (duplicates blocked).
**Errors — `403 Forbidden`** — not allowed to edit this playlist.

---

## 6. Remove a Song from a Playlist

**`DELETE /playlists/{playlist_id}/songs/{playlist_song_id}/`**

**Success — `204 No Content`**

**Behavior:** all songs after the removed one automatically shift back by one position — there are never gaps in the numbering.

**Errors**
- `403` — not allowed to edit
- `404` — song not found in this playlist

---

## 7. Move / Reorder a Song

**`POST /playlists/{playlist_id}/songs/{playlist_song_id}/move/`**

| Field | Type | Required |
|---|---|---|
| new_position | integer (≥0) | yes |

```json
{ "new_position": 0 }
```

**Success — `200 OK`** — returns the updated `PlaylistSong`. All songs between the old and new position shift to make room.

**Concurrency note:** this runs inside a database transaction with row locking. If two users try to reorder the same playlist at the exact same moment, the second request automatically waits for the first to finish, then applies cleanly — the order can never end up corrupted or with two songs sharing a position.

**Errors**
- `403` — not allowed to edit
- `404` — song not found in this playlist

---

## 8. Live Updates — WebSocket

```
ws://localhost:8000/ws/playlists/{playlist_id}/?token={access_token}
```

Same auth pattern as Events (token as query param, closes with `4001`/`4003` on auth/permission failure).

**On any playlist change (add, remove, move), you receive:**
```json
{
  "playlist_id": 1,
  "songs": [ /* same shape as GET /songs/, already in correct order */ ]
}
```

---

## Status codes cheat sheet (Events + Playlists)

| Code | Meaning |
|---|---|
| 200 | OK (list, get, vote retract, move) |
| 201 | Created (event/playlist/song/vote created) |
| 204 | No Content (delete succeeded) |
| 400 | Validation error — bad input, duplicate, already voted, <2 songs |
| 401 | Not authenticated |
| 403 | Authenticated, but not allowed (visibility/permission rules) |
| 404 | Resource not found |

---

## Design patterns used throughout

- **Visibility** (`public`/`private`) controls who can even *see* an event/playlist.
- **Permission** (`vote_permission` / `edit_permission`) controls who can *act* on it, layered on top of visibility.
- **Database-level constraints** prevent double-voting and duplicate songs — not just application logic, so it holds even under simultaneous requests.
- **WebSocket auth** uses JWT via query parameter (`?token=`), since WebSocket clients can't send custom headers the way REST clients can.
- **Real-time updates are push-only** — the WebSocket doesn't send current state on connect. Always call the matching `GET` endpoint first to load initial state, then let the WebSocket keep it live.

---

## Not yet built / known follow-ups

- [ ] Event invitations endpoint (inviting specific users to a private event) — model exists (`EventGuest`), REST endpoints not yet built
- [ ] Playlist collaborator invitations endpoint — model exists (`PlaylistCollaborator`), REST endpoints not yet built
- [ ] Music SDK integration for real song search (currently manual title/artist entry only)
- [ ] Automated test suite for these two apps
