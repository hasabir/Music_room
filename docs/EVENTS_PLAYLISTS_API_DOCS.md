# Music Room — Events (Track Vote) & Playlists — Complete Behavior Reference

Verified directly against source in `backend/events/`, `backend/playlists/`, and `backend/api/`
as of **2026-08-31**. This supersedes the previous version of this file — it now also covers
guests, collaborators, join, access requests, live playback sync, and track search, none of
which were documented here before. It aims to record **every** behavior and edge case the
code actually implements, including the small ones, not just the happy path.

Base URL (local dev): `http://localhost:8000/api/v1/`

All requests/responses are JSON (except playlist cover-image upload, which is multipart).
Every endpoint below requires authentication unless noted:
```
Authorization: Bearer <access_token>
```
See `AUTH_API_DOCS.md` for login/register/profile endpoints.

---

## Shared concepts that apply to both features

### The song catalog is one shared table

`events.Song` (defined in the events app) is the single catalog used by **both** events and
playlists — `playlists.PlaylistSong.song` is a foreign key straight into `events.Song`.
Fields: `external_id`, `title`, `artist`, `duration_seconds`, `album_art_url`, `preview_url`,
`playback_type` (`preview` | `full`, default `preview`), `created_at`. Catalog ordering is
alphabetical by `title`.

**Reuse rule is now consistent between the two features** (fixed — see `DECISIONS.md`, "Events
brought to parity with Playlists"): both `EventQueueView.post` and `PlaylistSongListView.post`
match/create the catalog `Song` by `external_id` first when the request supplies one, falling
back to case-insensitive `title` + `artist` matching only when `external_id` is blank. This is
specifically so a title/artist that exists on both Deezer and Audius doesn't collapse into one
`Song` row and silently swap a full Audius stream for a Deezer preview (or vice versa), and so
the same track added to an event and to a playlist resolves to the same catalog row either way.

### Track search (feeds both features)

Not part of `events`/`playlists` apps, but is how a client actually discovers songs to add to
either — `backend/api/views.py`, mounted at `/api/v1/tracks/...`:

| Method | Path | Purpose |
|---|---|---|
| GET | `/tracks/search/?q=<query>` | Search by title/artist/etc. |
| GET | `/tracks/trending/` | "Popular now" list, no query needed |
| GET | `/tracks/<external_id>/preview/` | Resolve a fresh, playable URL for one track |

- **Source priority, both search and trending:** Audius full-length streams are returned
  first, then Deezer 30-second previews are appended after. Each result carries
  `playback_type: "full"` (Audius) or `"preview"` (Deezer) plus `external_id`, `title`,
  `artist`, `album_art_url`, `preview_url`, `duration_seconds` — the exact same shape either
  source produces, and the exact shape `AddSongToQueueSerializer` / `AddSongToPlaylistSerializer`
  accept.
- **Audius `external_id`s are prefixed** `audius:<id>` so they can't collide with Deezer's
  plain numeric IDs, and so `TrackPreviewView` can tell which service to resolve against.
- **Audius results are filtered to streamable tracks only** (`is_streamable`/`isStreamable`,
  treating `false`/`"false"`/`0`/`"0"` as not streamable, everything else — including a missing
  field — as streamable).
- **Neither source failing is fatal on its own** — `_fetch_audius_tracks` swallows Audius
  network/JSON errors and just returns `[]`, so Deezer results alone still come back. Deezer
  failing while Audius succeeds returns the Audius-only list. **Both** unreachable →
  `502 {"detail": "Unable to reach the music search service. Please try again."}`.
- **`/tracks/search/`** — blank/missing `q` → `400 {"detail": "Query parameter 'q' is required."}`.
- **`/tracks/<external_id>/preview/`**: Deezer preview CDN URLs are signed and expire, so this
  is meant to be called immediately before playback, not cached long-term.
  - Audius id (has the `audius:` prefix) — the remainder must match `[A-Za-z0-9]+` or
    `400 {"detail": "An Audius track ID is required."}`; on match, returns a computed stream
    URL with **no actual network call to Audius** (it's a deterministic URL shape).
  - Otherwise must be all-decimal (Deezer numeric id) or `400 {"detail": "A Deezer numeric track ID is required."}`.
  - Deezer track has no `preview` field / it's empty → `404 {"detail": "No preview is available for this track."}`.
  - Deezer unreachable → `502`.
- Throttled separately: `track_search` (300/min) and `track_preview` (300/min) — deliberately
  low, since these proxy Deezer and must stay well under Deezer's own rate limits.
- Requires auth like everything else (`401` if not logged in).

### WebSocket auth pattern (identical for both apps)

```
ws://localhost:8000/ws/events/{event_id}/queue/?token={access_token}
ws://localhost:8000/ws/playlists/{playlist_id}/?token={access_token}
```
JWT access token as a **query parameter**, not a header (WebSocket clients can't reliably send
custom headers). `JWTAuthMiddleware` (`events/ws_auth.py`) decodes it into `scope["user"]`;
missing/invalid token → `AnonymousUser`.

- Missing/invalid token → connection closes immediately, code **4001**.
- Token valid but user can't see the event/playlist → closes, code **4003**.
- Both consumers are **push-only, one-directional** (server → client); `receive()` is a no-op
  stub. A client must call the matching `GET` first for initial state, then rely on the socket
  for live updates — connecting doesn't replay current state.
- Every event queue mutation (add song, vote, retract) broadcasts the **entire re-sorted
  queue** to `event_queue_{id}`, alongside the event's current guest list (`"guests": [...]`,
  added for the access-request work below — mirrors how `broadcast_playlist_update` always
  includes the collaborator list). An access-request **approval** also triggers this broadcast
  (denial doesn't — nothing about the guest list changes on a denial). `has_voted` is **not**
  meaningful in the broadcast payload — there's no per-connection user context available
  inside `broadcast_queue_update`, so it's always `False` for every entry regardless of who
  actually voted. Clients must track their own vote state locally, or fall back to
  `GET /queue/` for the accurate per-user view.
- Every playlist mutation (add/remove/move song, invite/remove collaborator,
  approve/deny access request) broadcasts to `playlist_{id}` — and broadcasts **three** things
  together: the playlist object itself, the full ordered song list, **and** the collaborator
  list. Events' broadcast only ever sends the queue, nothing else.

### Concurrency — no version field anywhere

Neither app has an optimistic-concurrency field (no `version`, no ETag). Two different
mechanisms are used instead:
- **Votes:** DB `unique_together` on `(event_song, voter)`. A duplicate vote raises
  `IntegrityError`, caught and turned into `400`. This makes double-voting impossible even
  under two simultaneous requests — no lost-update window.
- **Playlist reordering** (`add_song_to_playlist` / `remove_song_from_playlist` / `move_song`
  in `playlists/services.py`): `select_for_update()` row locks inside `transaction.atomic()`,
  plus a **deferred** `UniqueConstraint(["playlist", "position"])` — deferred specifically
  because a multi-row position shift can momentarily put two rows on the same position
  mid-transaction; deferring the check to commit-time avoids a false constraint violation.
  Concurrent requests on the same playlist serialize (second waits for the first to commit)
  rather than being detected/rejected.
- **Events' queue has no equivalent locking for adds** — `EventSong.objects.get_or_create` is
  the only guard against a duplicate queue entry, backed by the `(event, song)` unique
  constraint, but there's no `select_for_update()` around it the way playlists have.
- `Event.updated_at` / `Playlist.updated_at` (`auto_now`) only bump on a PUT/PATCH to the
  parent object itself — never on queue/song/vote/collaborator sub-object mutations. Not used
  by any endpoint for concurrency detection.

### Activity logging (`log_action`)

Every mutation below writes a row via `authentication.utils.log_action` capturing the acting
user, an action string, request headers (`X-Platform`/`X-Device`/`X-App-Version`), client IP,
and a metadata blob — **except** a few notable gaps:
- **Editing or deleting an event or a playlist is never logged.** `EventDetailView`/
  `PlaylistDetailView`'s `perform_update`/`perform_destroy` call no `log_action` at all — only
  creation (`event.created`, `playlist.created`) is recorded on that model.
- Inviting a guest to an event double-logs: once as `event.guest_invited` (host's feed) and
  once as `event.joined` with `"via": "invited"` (invited user's feed) — so an invited guest's
  activity history shows they "joined" even though they never called the join endpoint.
- Self-joining a public event logs `event.joined` with `"via": "joined"`.
- Retracting a vote, cancelling an access request, and access-request decisions are all logged.
- Playlist collaborator **permission changes** (`PATCH .../collaborators/<id>/`) are **not**
  logged — only invite/remove are.

Full action list: `event.created`, `event.song_added`, `event.vote_cast`, `event.vote_retracted`,
`event.guest_invited`, `event.guest_removed`, `event.guest_accepted`, `event.guest_declined`,
`event.joined` (×2 triggers), `event.access_requested`, `event.access_request_cancelled`,
`event.access_request_decided`, `playlist.created`, `playlist.song_added`,
`playlist.song_removed`, `playlist.song_moved`, `playlist.collaborator_invited`,
`playlist.collaborator_removed`, `playlist.access_requested`,
`playlist.access_request_cancelled`, `playlist.access_request_decided`.

### Throttle rates (`config/settings.py`)

| Scope | Rate | Applies to |
|---|---|---|
| `create_event` | 10000/hour | `POST /events/` |
| `add_song` | 20000/min | `POST /events/<id>/queue/` |
| `vote` | 30000/min | `POST`/`DELETE .../vote/` |
| `event_access_request` | 3000/hour | `POST /events/<id>/access-requests/` |
| `create_playlist` | 10000/hour | `POST /playlists/` |
| `add_playlist_song` | 20000/min | `POST /playlists/<id>/songs/` |
| `move_song` | 60000/min | `POST .../move/` (deliberately high — drag-and-drop reordering fires fast) |
| `playlist_access_request` | 3000/hour | `POST .../access-requests/` |
| `track_search` | 300/min | `/tracks/search/`, `/tracks/trending/` |
| `track_preview` | 300/min | `/tracks/<id>/preview/` |

Guest/collaborator invite-remove and join endpoints have **no dedicated throttle** — they only
inherit the global `user` default (1,000,000/hour, effectively unlimited).

---

# PART 1 — Events (Music Track Vote)

## Concept summary

An **Event** is a party/session where people add songs to a shared queue and vote on them.
Unlike a plain "most votes wins" list, the backend also tracks **what's actually playing right
now**, advances it forward in real time even if nobody has the app open, and never lets a vote
interrupt a song mid-playback — see [Live playback sync](#live-playback-the-current-song-system) below.

- **`Song`** — catalog entry, shared with playlists (see above).
- **`EventSong`** — one song added to one event's queue; this is what gets voted on and what
  carries playback `status` (`queued` / `playing` / `played`).
- **`Vote`** — one user's vote for one `EventSong`. One vote per user per song, DB-enforced.
- **`EventGuest`** — a **"collaborator"**: host-granted invitation; drives private-event
  visibility **and** `invited_only` voting rights. Not limited to private events — a public
  event can also invite guests specifically to hand out `invited_only` voting rights on top of
  public visibility, and that's exactly what an `EventGuest` row on a public event represents.
  Carries an `rsvp_status` (`pending`/`accepted`/`declined`) the invited user sets themselves —
  see the access-requests/guests endpoints below.
- **`EventMembership`** — an **"attendee"**: a user having self-joined a **public** event via
  `POST /join/`. Deliberately kept separate from `EventGuest`: joining a public room must never
  accidentally grant `invited_only` voting permission, and inviting a guest to a private event
  does **not** create an `EventMembership` — that's a deliberate scope boundary (private-event
  guests are collaborators, not recorded as "attendees" the way a public-event self-joiner is),
  not an oversight. See `DECISIONS.md`, "Events terminology: collaborator vs. attendee."

**Voting only unlocks once an event has at least 2 songs in its (unplayed) queue.**

## 1. Data model — every field

`Event`:

| Field | Type | Default | Notes |
|---|---|---|---|
| `host` | FK → user, CASCADE | — | |
| `title` | CharField(100) | — | required |
| `description` | TextField(500) | `""` | optional, blank allowed |
| `cover_preset` | choice | `"party"` | `party`, `night_vibe`, `dj`, `summer_vibe`, `rain`, `coding_vibe`, `after_dark`, `vibes` — purely a client-rendered style key |
| `visibility` | choice | `"public"` | `public` \| `private` |
| `vote_permission` | choice | `"everyone"` | `everyone` \| `invited_only` \| `location_time_restricted` |
| `venue_center_latitude/longitude` | float, nullable | `null` | required together only when `location_time_restricted` |
| `allowed_distance_meters` | PositiveInteger, nullable | `null` | required when `location_time_restricted` |
| `voting_opens_at`/`voting_closes_at` | datetime, nullable | `null` | required when `location_time_restricted` |
| `current_song` | FK → EventSong, **SET_NULL** | `null` | authoritative "on air" pointer — see below |
| `current_song_started_at` | datetime, nullable | `null` | when `current_song` started; position is always derived, never stored |
| `created_at`/`updated_at` | auto | — | |

`current_song` is `SET_NULL` (not `CASCADE`) deliberately: losing the pointer (e.g. the
`EventSong` row it points to gets deleted some other way) must never take the whole event down
— `sync_current_song` just re-picks a leader on the next call.

## 2. Endpoints

### `GET` / `POST /events/`
- `GET`: public events + events you host + events you're an `EventGuest` on. No query params.
- `POST`: creates the event, caller becomes `host`. `400` if `vote_permission` is (or is being
  set to) `location_time_restricted` and any of the 5 location/time fields are missing —
  message: `"These fields are required when vote_permission is 'location_time_restricted': <field names>"`.
  Throttled (`create_event`).

### `GET`/`PUT`/`PATCH`/`DELETE /events/<pk>/`
- `GET`: `403` if not visible (`can_user_see_event`). **Calls `Event.sync_current_song()`
  before serializing** — so opening/rejoining an event always shows the truly-current song,
  not stale data from before you left.
- `PUT`/`PATCH`: host-only, else `403 {"detail": "Only the host can edit this event."}`. The
  `location_time_restricted` required-fields check re-validates against the *incoming* attrs
  falling back to the *existing instance's* current values — so a `PATCH` that only sends
  `{"title": "..."}` on an already-restricted event won't spuriously fail even though the
  location fields aren't in that request body.
- `DELETE`: host-only, else `403 {"detail": "Only the host can delete this event."}`.
  Cascades — deletes the event's entire queue, votes, guest list, and memberships.

### `GET`/`POST /events/<event_id>/queue/`
- `GET`: `403` if not visible. **Excludes `played` songs entirely** (not just sorts them
  last) — a played song simply disappears from this list. Sorted by vote count descending,
  computed in Python (`sorted(...)`), not a DB `ORDER BY`. Calls `sync_current_song()` first,
  so the list you get already reflects any auto-advance that happened purely from time passing.
- `POST` — add a song:
  - `403` if not visible to caller.
  - Body validated by `AddSongToQueueSerializer`: `title`/`artist` required (max 200 each),
    `duration_seconds` optional/nullable, `external_id`/`album_art_url`/`preview_url` optional
    (blank allowed), `playback_type` optional (`preview`/`full`, defaults `preview`).
  - **Song revival — the standout edge case:** if the matched `Song` already has an `EventSong`
    row in this event but its `status == "played"`, that row is **reused**, not duplicated
    (the `(event, song)` unique constraint would block a second row anyway). Its votes are
    wiped, `status` resets to `queued`, `added_by`/`added_at` are refreshed to the re-adder and
    now. The response returns the **same `id`** as the original add, with `vote_count: 0`.
  - If that existing row is still `queued` or `playing` → `400 {"detail": "This song is already in the queue."}`.
  - `sync_current_song()` is called **both before and after** the add: before, so a song whose
    playtime already genuinely elapsed isn't wrongly read as still-`playing` (which would
    block a legitimate revival); after, because adding a song can itself change who's current
    (e.g. it's the first/only song in an empty queue, so it becomes current immediately). The
    `EventSong` instance is `refresh_from_db()`'d before serializing so the response reflects
    that.
  - Broadcasts the updated queue over WebSocket on success.
  - Throttled (`add_song`).

### `POST`/`DELETE /events/<event_id>/queue/<event_song_id>/vote/`
- `POST` — cast a vote. Body is read via `request.data.get("latitude"/"longitude")` — **not**
  run through a DRF serializer, so there's no type coercion/validation beyond whatever the
  JSON parser gave; a malformed type (e.g. a string where a number is expected) is passed
  straight into the haversine math and is **not defensively handled**.
  - Permission check order (`can_user_vote`, all failures return **403**, not 400, despite the
    docstring suggesting otherwise):
    1. Can't see the event → `"You do not have access to this event."`
    2. Fewer than 2 unplayed songs in the queue → `"At least 2 songs must be in the queue before voting can start."`
    3. `everyone` → always allowed from here.
    4. `invited_only` → host or `EventGuest` only, else `"Only invited guests can vote on this event."`
    5. `location_time_restricted`, checked in this exact order:
       - `now < voting_opens_at` → `"Voting has not opened yet for this event."`
       - `now > voting_closes_at` → `"Voting has closed for this event."`
       - missing lat/long → `"Your location is required to vote on this event."`
       - haversine distance from venue center exceeds `allowed_distance_meters` → `"You must be near the event venue to vote."`
  - Duplicate vote → DB `IntegrityError` caught → `400 {"detail": "You have already voted for this song."}`.
  - On success: `sync_current_song()` runs, queue is broadcast, response is
    `{"detail": "Vote recorded.", "vote_count": N}` (**201**).
  - Throttled (`vote`).
- `DELETE` — retract. **Re-checks `can_user_see_event`** (fixed — see `DECISIONS.md`, "Events
  brought to parity with Playlists") before deleting the vote, else
  `403 {"detail": "You do not have access to this event."}` — closes the gap where a user
  whose access was revoked (e.g. removed as a guest on an `invited_only`/private event) after
  voting could still retract that specific vote by hitting this endpoint directly with a known
  `event_song_id`. Deliberately **not** the full `can_user_vote` gate — the 2-songs minimum
  and location/time window are about casting a *new* vote, not removing one that already
  exists and belongs to the caller — so a user who can still see the event can always retract
  their own vote regardless of those other conditions.
  - No vote to retract → `400 {"detail": "You have not voted for this song."}`.
  - Success → `200 {"detail": "Vote retracted.", "vote_count": N}`; also runs
    `sync_current_song()` and broadcasts.

### `GET`/`POST /events/<event_id>/guests/`
- `GET`: visible to host, any invited guest, or anyone if the event is public. Otherwise `403`.
  Each `EventGuest` object now includes `rsvp_status` (`pending`/`accepted`/`declined`).
- `POST` (host-only, else `403 {"detail": "Only the host can invite guests."}`):
  - `user_id == request.user.id` → `400 {"detail": "You cannot invite yourself — you're already the host."}`
  - Bad `user_id` → `404` (`get_object_or_404`).
  - Already invited → `400 {"detail": "This user is already invited."}`
  - Success → `201`, `rsvp_status: "pending"` on the new row. (see activity logging above)
    logs on **both** the host's and the invited user's activity feeds.

### `POST /events/<event_id>/guests/respond/`
Lets the invited user set their **own** RSVP status — never a path-parameterized `user_id`;
always resolved via `request.user`'s own `EventGuest` row for this event, so a host cannot
respond on a guest's behalf.
- Body: `{"response": "accepted" | "declined"}`.
- Not a valid value → `400 {"detail": "Response must be 'accepted' or 'declined'."}`.
- Caller has no `EventGuest` row for this event (including the host, who was never invited to
  their own event) → `404 {"detail": "You have not been invited to this event."}`.
- **Changing an existing response is allowed** — e.g. `accepted` → `declined` later — not just
  a one-time first response. Success is always `200` with the updated `EventGuest` object,
  whether this is the first response or a change.
- Logs `event.guest_accepted` or `event.guest_declined` depending on the outcome.

### `DELETE /events/<event_id>/guests/<user_id>/`
- Host-only, else `403 {"detail": "Only the host can remove guests."}`.
- Not currently invited → `404 {"detail": "This user is not invited to the event."}`.
- Success → `204`. Removing a guest immediately revokes their visibility into a private event
  and their `invited_only` voting rights (checked live each time, nothing cached), and deletes
  their `rsvp_status` along with the row — there's no "removed after declining" history kept.

### `POST /events/<event_id>/join/`
- Self-serve join, **public events only**.
- Host tries to join their own event → `400 {"detail": "You are the host of this event."}`.
- Event is private → `403 {"detail": "This event is private — you must be invited by the host."}`
  (note: joining is blocked by visibility, not by guest status — even an invited guest on a
  private event cannot use this endpoint; the host must invite via `/guests/`, which is the
  only path to access on a private event).
- Already joined → `400 {"detail": "You have already joined this event."}`.
- Creates an `EventMembership`, **not** an `EventGuest` — grants no extra voting permission
  beyond whatever `vote_permission` already gives a public-event viewer. Purely a "this person
  is in the room" record for activity/membership purposes.

### Access requests — `EventAccessRequest`

Lets a non-guest ask the host for access to a **private** event — mirrors Playlists'
`PlaylistAccessRequest` flow field-for-field, added to bring Events to parity (see
`DECISIONS.md`, "Events brought to parity with Playlists"). Approving simply creates an
`EventGuest`, which already grants both private-event visibility and `invited_only` voting
rights — the same coarse, bundled grant `EventGuest` has always meant in this codebase; no new
finer-grained permission was introduced.

**`GET`/`POST /events/<event_id>/access-requests/`**
- `GET`: **host-only**, else `403 {"detail": "Only the host can view access requests."}`.
- `POST` — request access, checked in this order:
  1. Host requesting access to their own event → `400 {"detail": "You already own this event."}`
  2. Caller is already an `EventGuest` → `400 {"detail": "You already have access to this event."}`
  3. **Idempotent on a pending request**: an existing `pending` request for this caller is
     returned as-is with `200` (not a fresh `201`).
  4. Event is **public**, not private → `400 {"detail": "This event is public — join it directly instead of requesting access."}`
     (public events already have self-serve `POST /join/`, so a request-access flow is
     meaningless there — and since this check runs *after* the idempotent-pending check, a
     stale pending request from before a host flipped the event to public still comes back as
     a normal `200`, rather than suddenly erroring).
  5. Otherwise creates a new `pending` request, `201`.
  - Throttled (`event_access_request`).

**`GET`/`DELETE /events/<event_id>/access-requests/mine/`**
- `GET`: caller's most recent request (any status) → `404 {"detail": "No access request found."}` if none exists.
- `DELETE`: cancels only if currently `pending` → `404 {"detail": "No pending access request found."}` otherwise. `204` on success.

**`POST /events/<event_id>/access-requests/<request_id>/decide/`**
- Host-only, else `403 {"detail": "Only the host can decide access requests."}`.
- Body: `{"approve": true|false}`.
- Already decided → `400 {"detail": "This request has already been decided."}` — a request can
  only ever be decided once.
- Approve → `status = "approved"`, `decided_at = now`, and
  `EventGuest.objects.get_or_create(event=event, guest=access_request.requester)` (race-safe).
  Also broadcasts the guest list over the event's WebSocket (see below) — denial does not,
  since nothing about the guest list changes on a denial.
- Deny → `status = "denied"`, `decided_at = now`, no guest created. No cooldown — the same
  user can immediately submit a brand-new request afterward.

### `GET /ws/events/<event_id>/queue/?token=...`
See [WebSocket section](#websocket-auth-pattern-identical-for-both-apps) above.

## Live playback: the "current song" system

This is the largest piece of behavior not covered by either previous version of this doc.
Full design rationale lives in `DECISIONS.md` ("Event playback: Option B"); summarized here.

**The backend, not any client, is authoritative for what's currently playing and how far into
it the room is** — every phone independently streams and plays audio locally (there's no
shared "host speaker" device or audio-relay layer), but they all sync to the same backend
state rather than deciding locally.

- `Event.current_song` (FK) + `Event.current_song_started_at` (timestamp) are the only
  persisted playback state. **Position is never stored** — it's always derived as
  `now() - current_song_started_at`, clamped to the song's playable duration, computed fresh on
  every read (`EventSerializer.get_current_position_seconds`). This avoids needing a
  background ticking worker (there is no Celery worker configured in this project) and can't
  drift the way a periodically-saved value could.
- `Event.sync_current_song()` is the **single place** that decides what's current, called on:
  every `GET /events/<id>/`, every `GET .../queue/`, and after every queue-mutating action
  (add song, vote, vote-retract). It:
  1. If nothing is current, picks the highest-voted not-yet-played song as leader (ties broken
     by earliest `added_at` — i.e. whichever was queued first).
  2. If something is current, checks whether its `effective_duration_seconds` has genuinely
     elapsed by wall-clock time since it started.
  3. If elapsed, marks it `played` (which also removes it from `GET .../queue/`, per the
     exclusion noted above), and repeats from step 1 — using the point in time the *previous*
     song's window actually ran out as the next song's start time, not "now". This is what lets
     it **catch up across multiple fully-elapsed songs in one call** if the event was unwatched
     for a long stretch, rather than only ever advancing one song per request.
  4. Stops as soon as a song is genuinely still mid-playback, or the queue runs dry.
- **A vote never interrupts a song that's already playing**, no matter how the vote order
  shifts underneath it. Votes only ever decide who leads *once* the current song's time is up
  — this is what lets everyone vote freely mid-song without fear of yanking the track out from
  under the room.
- **Duration semantics differ by `playback_type`** (`Song.effective_duration_seconds`):
  - `preview` (Deezer): **always** exactly `PREVIEW_CLIP_SECONDS` = 30s, regardless of what
    `duration_seconds` metadata says — that field describes the real commercial track, not the
    ~30s clip actually sitting at `preview_url`. (An earlier version tried honoring the real
    metadata duration for previews and it was wrong — every listener's player would sit on a
    naturally-finished clip while the backend kept waiting on time that had nothing left to
    play.)
  - `full` (Audius): uses its real `duration_seconds` as-is; if unknown (`None`), the song
    **never auto-advances** — it just plays indefinitely as far as the backend is concerned,
    since there's nothing to time it against.
  - `playback_type` defaults to `preview` when omitted from the add-song payload.
- **Client responsibilities** (all non-authoritative, per `DECISIONS.md`): on
  entering/rejoining an event, fetch `GET /events/<id>/` and start local playback at the
  reported `current_song`/`current_position_seconds` — never resume a locally-cached "last
  known track". Leaving the screen only stops local audio/polling for that device, it mutates
  nothing server-side. A song finishing locally triggers an immediate refetch (latency
  optimization) rather than any "mark played" request — there is no such endpoint; the backend
  already knows independently from elapsed time.
- **Sync transport for this specific feature is REST polling, not the WebSocket** — the
  `EventQueueConsumer` WebSocket exists and is used for queue *updates* (add/vote/retract), but
  the playback-position feature was deliberately kept on the event screen's existing polling
  loop rather than wired to it; noted in `DECISIONS.md` as a reasonable, currently-unclaimed
  follow-up.

`EventSerializer` exposes this as:
```json
{
  "current_song": { /* full EventSongSerializer object, or null if queue is empty */ },
  "current_position_seconds": 12.4 /* or null if current_song is null */
}
```

---

# PART 2 — Playlists (Music Playlist Editor)

## Concept summary

A **Playlist** is a collaborative, ordered list of songs. Unlike events, there's no voting or
playback state — just ordering, and a considerably more granular permission model than events
has: per-collaborator booleans for adding songs, reordering, and managing other collaborators,
plus a self-serve **access request** flow for non-collaborators to ask the owner for in.

- **`PlaylistSong`** — one song at one position; positions are gapless integers (0, 1, 2, ...).
- The same `Song` **cannot** appear twice in one playlist (DB constraint).
- Reordering/removing/adding all run inside `select_for_update()`-locked transactions.

## 1. Data model — every field

`Playlist`:

| Field | Type | Default | Notes |
|---|---|---|---|
| `owner` | FK → user, CASCADE | — | |
| `title` | CharField(100) | — | required |
| `description` | TextField(500) | `""` | optional |
| `visibility` | choice | `"public"` | `public` \| `private` |
| `edit_permission` | choice | `"everyone"` | `everyone` \| `invited_only` \| **`owner_only`** — see caveat below |
| `cover_image` | ImageField, nullable | `null` | uploaded photo; write-only in the API (`cover_image_url` is the read side) |
| `cover_preset` | choice, blank-ok | `""` | `sunset`, `neon`, `forest`, `ocean`, `midnight` |
| `created_at`/`updated_at` | auto | — | |

**Cover mutual exclusivity** (`PlaylistSerializer.validate`): a playlist shows at most one
cover. Sending `cover_image` in a request clears `cover_preset` to `""`; sending `cover_preset`
clears `cover_image` to `null`. Whichever was sent in *this* request wins over whatever was set
before — you cannot update both in the same request in a way that keeps both.

**`edit_permission: "owner_only"` is not actually enforced by the song-level endpoints** — a
real, non-obvious gap. `Playlist.EDIT_PERMISSION_CHOICES` includes it and the standalone
`can_user_edit_playlist()` function does special-case it (returns `False` for anyone but the
owner), but **that function is dead code — nothing in `views.py`, `views_collaborators.py`, or
anywhere else imports or calls it.** The functions actually used to gate adding/reordering
songs (`can_user_add_songs`, `can_user_reorder_songs`) only branch on
`edit_permission == "everyone"` vs. falling through to per-collaborator booleans — they never
check for `"owner_only"` specifically. So in practice, setting `edit_permission` to
`"owner_only"` behaves identically to `"invited_only"`: any collaborator with
`can_add_songs`/`can_reorder_songs` set `True` (the default when invited) can still add/reorder
songs, even though the field's own label says "Only the owner can edit."

`PlaylistCollaborator`:

| Field | Default | Notes |
|---|---|---|
| `can_add_songs` | `True` | governs both **adding** (`PlaylistSongListView.post`) and, per `PlaylistSongDeleteView`'s implementation, **removing** songs too — there is no separate "can remove" flag; removal reuses `can_user_add_songs` |
| `can_reorder_songs` | `True` | governs `.../move/` |
| `can_manage_collaborators` | `False` | governs inviting/removing *other* collaborators (`can_user_manage_collaborators`) |

Every newly-invited collaborator defaults to full add/reorder rights but no collaborator
management rights, unless the owner subsequently tunes them via the `PATCH` endpoint below.

`PlaylistAccessRequest`: `status` one of `pending`/`approved`/`denied`, `requested_at`
(auto), `decided_at` (set only on decision). No cooldown after a `denied` decision — the same
user can immediately submit a new request.

## 2. Endpoints

### `GET`/`POST /playlists/`
- `GET`: public playlists + playlists you own + playlists you're a `PlaylistCollaborator` on.
- `POST`: caller becomes `owner`. Throttled (`create_playlist`).

### `GET`/`PUT`/`PATCH`/`DELETE /playlists/<pk>/`
- `GET`: `403` if not visible.
- `PUT`/`PATCH`: **owner-only**, else `403 {"detail": "Only the owner can edit this playlist."}`
  — note this is stricter than song-level edits, which a collaborator can do; only the owner
  can ever change the playlist's own settings (title, visibility, permissions, cover).
  Broadcasts the update over WebSocket on success.
- `DELETE`: owner-only, else `403 {"detail": "Only the owner can delete this playlist."}`.
  Cascades to songs, collaborators, and access requests.

### `GET`/`POST /playlists/<playlist_id>/songs/`
- `GET`: DB-ordered by `position` ascending (unlike events' queue, which sorts in Python by
  votes) — `Meta.ordering = ["position"]` does the work. `403` if not visible.
- `POST` — add to the end (`position = current count`):
  - Permission: `can_user_add_songs` — owner or `edit_permission == "everyone"` always pass;
    otherwise requires a `PlaylistCollaborator` row with `can_add_songs=True`, else
    `403 {"detail": "The playlist owner has not allowed you to add songs."}` (or
    `"You do not have access to this playlist."` if not even visible).
  - Song matching: **`external_id`-aware** — see the [reuse-rule discrepancy](#the-song-catalog-is-one-shared-table) noted above.
  - Duplicate check is an **explicit `.exists()` query in the view**, separate from (and
    checked before) the DB's `unique_song_per_playlist` constraint → `400 {"detail": "This song is already in the playlist."}`.
  - Throttled (`add_playlist_song`).

### `DELETE /playlists/<playlist_id>/songs/<playlist_song_id>/`
- Permission: reuses **`can_user_add_songs`** (see collaborator-flags note above) — so a
  collaborator granted add-rights can also remove any song, not just their own.
- Not found in this playlist → `404 {"detail": "Song not found in this playlist."}`.
- On success: `remove_song_from_playlist` runs inside `select_for_update()`, deletes the row,
  then shifts every song after it back one position in a single `UPDATE ... position = position - 1`
  — positions are never left with gaps. `204`.

### `POST /playlists/<playlist_id>/songs/<playlist_song_id>/move/`
- Permission: `can_user_reorder_songs` (independent flag from add/remove).
- `new_position` (required, `min_value=0`) is **silently clamped** to
  `[0, song_count - 1]` — an out-of-range value (e.g. `999` in a 2-song playlist) is not
  rejected, just clamped to the max valid slot.
- If `new_position` resolves to the song's current position → no-op, still returns `200` with
  the unchanged object.
- Otherwise shifts everything strictly between the old and new position by exactly one slot
  (direction-dependent — up vs. down the list) inside `select_for_update()`, so a burst of
  concurrent moves from different users can't corrupt ordering or collide on a position.
  Throttled (`move_song`, deliberately generous for drag-and-drop).

### `GET`/`POST /playlists/<playlist_id>/collaborators/`
- `GET`: visible to owner, any collaborator, or anyone if the playlist is public.
- `POST`: gated by **`can_user_manage_collaborators`** — owner, **or** a collaborator with
  `can_manage_collaborators=True` (not owner-only, unlike playlist-level edits above).
  - Inviting yourself → `400 {"detail": "You cannot invite yourself — you're already the owner."}`
    (message is owner-phrased even though a delegated collaborator, not just the owner, can
    trigger this path).
  - Already invited → `400 {"detail": "This user is already invited."}`.
  - Bad `user_id` → `404`.
  - Broadcasts on success.

### `DELETE`/`PATCH /playlists/<playlist_id>/collaborators/<user_id>/`
- `DELETE`: same `can_user_manage_collaborators` gate as invite. Not invited → `404`.
- `PATCH` — **tune one collaborator's granular permissions**
  (`can_add_songs`/`can_reorder_songs`/`can_manage_collaborators`, all required booleans via
  `CollaboratorPermissionsSerializer`): **owner-only**, checked directly against
  `playlist.owner_id`, **not** `can_user_manage_collaborators` — a genuine asymmetry: a
  collaborator who's been delegated `can_manage_collaborators=True` can invite and remove other
  collaborators outright, but **cannot** adjust anyone's permission flags; only the actual
  owner can. `403 {"detail": "Only the owner can change collaborator permissions."}` for anyone
  else. Target collaborator not found → `404` (unhandled `get_object_or_404`, not a custom
  message like the other endpoints). Broadcasts on success.

### Access requests — `PlaylistAccessRequest` (not previously documented at all)

Lets a non-collaborator ask the owner for in — to view a private playlist or to gain
`invited_only` edit rights. Approving simply creates a `PlaylistCollaborator`, which already
grants both of those depending on the playlist's settings.

**`GET`/`POST /playlists/<playlist_id>/access-requests/`**
- `GET`: **owner-only**, else `403 {"detail": "Only the owner can view access requests."}` —
  unlike the guest/collaborator list endpoints, this one is not visible to anyone else at all.
- `POST` — request access:
  - Owner requesting access to their own playlist → `400 {"detail": "You already own this playlist."}`.
  - Already a collaborator → `400 {"detail": "You already have access to this playlist."}`.
  - **Idempotent on a pending request**: if the caller already has a `pending` request for this
    playlist, it's returned as-is with `200` (not a fresh `201`) rather than erroring or
    creating a duplicate.
  - Otherwise creates a new `pending` request, `201`.
  - Throttled (`playlist_access_request`).

**`GET`/`DELETE /playlists/<playlist_id>/access-requests/mine/`**
- `GET`: the caller's **most recent** request regardless of status (pending/approved/denied) —
  `404 {"detail": "No access request found."}` if none exists at all.
- `DELETE`: cancels only if there's a currently **pending** one —
  `404 {"detail": "No pending access request found."}` otherwise (this message differs subtly
  from the `GET`'s 404 message above — one says "no access request", the other says "no
  *pending* access request"). Approved/denied requests can't be "cancelled" this way — they're
  a permanent decision record. `204` on success.

**`POST /playlists/<playlist_id>/access-requests/<request_id>/decide/`**
- Owner-only, else `403 {"detail": "Only the owner can decide access requests."}`.
- Body: `{"approve": true|false}`.
- Already decided (not `pending`) → `400 {"detail": "This request has already been decided."}`
  — a request can only ever be decided once; there's no "undo" or re-decide path.
- Approve → `status = "approved"`, `decided_at = now`, and
  `PlaylistCollaborator.objects.get_or_create(...)` — the `get_or_create` means approving is
  safe even if the requester somehow became a collaborator through another path in the
  meantime (e.g. a race with a direct invite); it won't error or create a duplicate row.
- Deny → `status = "denied"`, `decided_at = now`, no collaborator created. As noted above,
  nothing stops the same user from immediately submitting a brand-new request afterward.
- Broadcasts the playlist update (collaborator list changes) on approval.

### `GET /ws/playlists/<playlist_id>/?token=...`
See [WebSocket section](#websocket-auth-pattern-identical-for-both-apps) above — note the
broader broadcast payload (playlist + songs + collaborators together) compared to events.

---

## Status codes cheat sheet (Events + Playlists)

| Code | Meaning |
|---|---|
| 200 | OK (list, get, vote retract, move, PATCH collaborator perms, access-request decide/mine) |
| 201 | Created (event/playlist/song/vote/guest/collaborator/membership/access-request created) |
| 204 | No Content (delete succeeded) |
| 400 | Validation error — bad input, duplicate, already voted, <2 songs, already decided, self-invite |
| 401 | Not authenticated |
| 403 | Authenticated, but not allowed (visibility/permission rules) |
| 404 | Resource not found, or not-currently-invited/no-pending-request |
| 502 | Track search/preview — both upstream music APIs unreachable |

---

## Design patterns used throughout

- **Visibility** (`public`/`private`) controls who can even *see* an event/playlist.
- **Permission** (`vote_permission` / `edit_permission` / per-collaborator booleans) controls
  who can *act* on it, layered on top of visibility.
- **Database-level constraints** prevent double-voting and duplicate songs — not just
  application logic, so it holds even under simultaneous requests.
- **Plain-function permission checks** (`events/permissions.py`, `playlists/permissions.py`)
  rather than DRF permission classes — each returns `(allowed, reason)` so the view can surface
  a specific message, at the cost of every view having to remember to call the right one (see
  the `owner_only`/dead-function gap below).
- **WebSocket auth** uses JWT via query parameter, since WebSocket clients can't send custom
  headers the way REST clients can.
- **Real-time updates are push-only** — always call the matching `GET` first for initial state.
- **Playback state is derived, never stored** (events only) — position is computed from a
  timestamp on every read, not incrementally updated by a background job.

---

## Known gaps / things that exist but aren't wired up

- `EventSong.status` has no manual-transition endpoint — the only thing that ever moves a song
  through `queued → playing → played` is `Event.sync_current_song()`, driven purely by elapsed
  time and vote ranking. There is no "host manually skips/marks played" action.
- `EventGuest.rsvp_status` (added for RSVP support) has no list-filtering endpoint yet — there's
  no `GET /events/<id>/guests/?status=accepted`-style query, and `GET .../guests/` still
  returns every guest regardless of status. The host also can't yet remove a guest *based on*
  their RSVP status (e.g. "remove everyone who declined") — removal is still just
  `DELETE .../guests/<user_id>/` by id, unchanged. Both are deliberately deferred to later work
  that builds on this field, not an oversight.
- `can_user_edit_playlist()` in `playlists/permissions.py` is unused dead code; `owner_only`
  edit permission is a defined choice with no enforcement in the actual song endpoints — see
  the Playlists data-model section above.
- No test suite for the `api` app's track-search endpoints existed before recent work; it now
  has coverage (`backend/api/tests.py`) alongside `events/tests.py` and `playlists/tests.py`
  (previously this doc said "no automated tests" — that's no longer true).
- No endpoint to remove yourself from an event (`EventMembership`) or a playlist once
  joined/invited — only the host/owner can remove a guest/collaborator; there's no self-service
  "leave".
