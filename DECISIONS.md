# Architecture decisions

## Event playback: Option B — every client plays locally, synced to a shared backend clock

**Decision:** each user's phone independently streams and plays the current song's audio
(via the local `audioplayers` SDK); no single device acts as "the speaker." The backend
is authoritative for *what* is current and *how far into it* the event is — every client
just displays and plays that, never decides it locally.

**Why this fits, not Option A:** Option A (one designated device produces sound, others
are silent viewers/voters) would require an actual audio-broadcast/relay layer — nothing
in this codebase does that. `audioplayers` is a local-URL player, not a streaming/casting
SDK, and there is no "host device," no delegated-controller concept, and no infrastructure
to pipe one phone's audio output to others. Building that would be a new subsystem, not a
fit for what's here. Option B is also *already* the shape of the existing implementation —
every `EventDetailScreen` independently resolves a preview URL and calls
`PlaybackController.play()` — this work formalizes it rather than replacing it.

**What "synced" means in practice:** the backend persists `Event.current_song` (FK) and
`Event.current_song_started_at` (timestamp). Playback *position* is never stored directly —
it's derived as `now - current_song_started_at` (clamped to the song's playable length)
every time it's read. This avoids needing a ticking background job (this project has no
Celery worker configured, despite the dependency being listed) to keep a stored position
field up to date, and it can't drift the way a periodically-saved position could.

**Backend-authoritative advancement:** `Event.sync_current_song()` is the single place that
decides what's current. It's called on every read (`GET /events/<id>/`, `GET .../queue/`)
and after every mutation (vote, retract, add song). It:
- Advances past any song whose *actual* playable duration has elapsed by wall-clock time —
  even if nobody has had the event open since it started, so a rejoining user always lands
  on the truly-current song, not a stale one from before they left (requirement: the event
  keeps moving forward regardless of who's connected).
- Marks a song `played` (permanently out of the queue) only once its time has genuinely run
  out, then picks whoever leads the vote at that moment as the next current song.
- **Never interrupts a song that's already playing, no matter how votes change while it
  plays.** A vote only ever reorders the queue — who's positioned to lead once the current
  song's time is up — it never cuts off what's already on air. Everyone can vote as freely
  as they want mid-song without worrying a vote will yank the track out from under the room;
  the only thing a vote can do is decide who's next.

**Timing matches what's actually playable, per source — this took two tries to get right.**
`Song.effective_duration_seconds`:
- A `preview` (Deezer) is **always** exactly `PREVIEW_CLIP_SECONDS` (~30s), full stop —
  `duration_seconds` on a `preview` describes the real commercial track, not the clip
  actually sitting at `preview_url`, and that clip never plays for longer than ~30s no
  matter what the metadata says. An earlier version of this let a `preview` stay
  authoritative for its full metadata duration on the theory that a longer song "shouldn't
  be cut short" — that was wrong: it just meant every listener's local player sat on a
  naturally-finished clip for however much of the fake remaining duration was left, unable
  to actually play anything. `EventDetailScreen._onLocalPlaybackFinished` /
  `_localStartPosition` still loop and clip-wrap defensively (see below) for the rare
  clock-skew case where a client's own local completion lands a beat before the backend's
  exact cutoff, but with this fixed, that's a sub-second safety net now, not the mechanism
  actually keeping the room from going silent — a `preview` genuinely plays for ~30s, then
  the next song, same as before this playback-authority work started.
- A `full` (Audius) stream has no such gap between what's timed and what's playable, so its
  real `duration_seconds` is used as-is (`None` if unknown, meaning it plays indefinitely —
  there's nothing to time it by).

**Defensive clip-wrapping on the client (for edge cases, not the primary mechanism):**
`EventDetailScreen._localStartPosition` wraps a `preview` song's start position into
`0..PREVIEW_CLIP_SECONDS` (`elapsed % songPreviewClipSeconds`) before seeking, and
`_onLocalPlaybackFinished` loops the same clip if a refetch right after local completion
still (very briefly) shows the same song current. In the steady state this almost never
fires — the backend's own ~30s cutoff and the client's local completion land together — but
it guards against a client whose local playback started a moment later than the backend's
timer did (a slow buffer, a slightly-delayed join), where the audio file would otherwise run
out a fraction of a second before the backend agrees it's over.

**Client responsibilities (never authoritative):**
- On entering/rejoining, fetch `GET /events/<id>/` and start playback at the reported
  `current_song` / `current_position_seconds` — never resume a locally-cached "last known
  track" from a previous session.
- On leaving the event screen, stop local audio and stop polling — this only affects what
  *this device* renders; it sends no request that could pause/stop/mutate the event for
  anyone else.
- A song finishing locally triggers an immediate refetch, not a "mark this played" mutation
  — the backend already knows independently, from elapsed time, whether the song is over.
  This is normally just a latency optimization (no waiting out the rest of the poll interval
  before hearing the next song) — see the defensive clip-wrapping note above for the rare
  case where it also needs to loop.

**Sync transport stays polling, not WebSocket, for this feature.** `events/consumers.py`
already has a WebSocket consumer for queue updates, and the playlist screen already uses a
WebSocket-with-polling-fallback pattern — so WebSocket *is* an available pattern in this
codebase — but the event screen has never been wired to it, and adding that wiring is a
separate, larger change than event playback semantics. This work keeps the event screen's
existing `Timer`-based REST polling and makes sure every refetch simply trusts the backend
response as ground truth. Wiring the event screen to its existing WebSocket consumer (like
playlists already do) would be a reasonable, currently-unclaimed follow-up.
