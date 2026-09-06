# Bonus: Multi-Platform Support (Flutter Web)

This documents the web build added on top of the existing Flutter app —
what changed, every plugin/API break found and how it was fixed, the
backend changes it required, and what was deliberately left out.

## Scope

- **Music Track Vote — full read/write on web.** Browse public events,
  access private ones via invite, suggest tracks, vote, see live
  vote-driven reordering, all license rules (open / invited-only /
  time / location) enforced exactly as on mobile.
- **Music Playlist Editor — read-only on web.** View a playlist and its
  current order, including live updates when someone else edits it.
  Add/remove/reorder/collaborator-management/cover upload/create/delete
  are mobile-only.
- **Responsive layout.** A real desktop layout (side nav, multi-column
  lists, two-column detail views) above a 900px-wide breakpoint, not a
  stretched phone screen.
- **Out of scope, untouched:** Music Control Delegation (not
  implemented at all, mandatory or otherwise). Nothing here adds
  write/edit capability to the Playlist Editor on web. No rewrite —
  same widget tree, same state management, same API client layer.

## How to run it

```
cd mobile
flutter run -d chrome --web-port=5000
```

The backend must allow `http://localhost:5000` — already the default in
`backend/.env.example` / `config/settings.py` (see [CORS](#cors) below).
`flutter run -d chrome` without `--web-port` picks a random port every
time, which won't match the CORS allowlist — always pass a fixed port
for local dev, and add it to `CORS_ALLOWED_ORIGINS`/`CSRF_TRUSTED_ORIGINS`
if you use a different one.

`mobile/.env`'s `API_BASE_URL` still needs to point at wherever the
backend actually is — the existing default is a LAN IP for physical
mobile devices, which a browser on the same machine as the backend can't
reach either way you'd want. Point it at `http://localhost:8000` (or
wherever `docker compose` publishes the backend) while working on web,
and back at the LAN IP for a physical-device mobile run. This project
doesn't currently have a way to pick different values per platform (it's
a single `.env` asset baked in at build time) — worth a `--dart-define`
based override if this becomes a recurring annoyance, but out of scope
here.

## Plugins/packages: what broke on web, and the fix

Every one of these was confirmed by actually reading the plugin's web
implementation source and/or running `flutter build web` /
`flutter run -d chrome` and driving the app in a real browser — not
guessed from a compatibility table.

### 1. `http.MultipartFile.fromPath` — hard break, fixed

`package:http`'s `fromPath` resolves to a **stub** on web
(`multipart_file_stub.dart`) that unconditionally throws
`UnsupportedError('MultipartFile is only supported where dart:io is
available.')`. This is what `ApiClient.patchMultipartFile` used for
every image upload (`profile_image`, playlist `cover_image`).

**Fix:** switched to `http.MultipartFile.fromBytes`, which has no
platform split. Callers now read bytes via `XFile.readAsBytes()`
(`image_picker`'s cross-platform way to get file contents — works
identically on native and on web, where `XFile.path` is a `blob:` URL a
real file API can't open anyway) instead of passing a path string.
Touched: `core/api/api_client.dart`, `profile/profile_api.dart`,
`playlists/playlist_api.dart`, and their three call sites
(`edit_profile_screen.dart`, `create_playlist_screen.dart`,
`playlist_detail_screen.dart`). No pros/cons here — `fromBytes` is
strictly better on every platform, so this wasn't a judgment call, just
a bug fix. Profile photo upload is reachable on web and was verified
working end-to-end; the playlist-cover-upload call sites are mobile-only
reachable (see Playlist Editor scope) but had to compile against the new
shared signature regardless.

### 2. `dart:io` `WebSocket` — hard break, fixed (and now shared with mobile)

The Playlist Editor's live-update socket
(`playlist_detail_screen.dart`) used `dart:io`'s `WebSocket.connect`,
which has no web implementation.

**Decision made with you:** rather than skip live updates on web
entirely, added `web_socket_channel` (a real dependency add — flagged
before implementing) and switched to its `WebSocketChannel.connect`,
which is a single cross-platform API (backed by `dart:io` on native,
the browser `WebSocket` on web) — so this is one code path now, not two,
and it fixes the bug for mobile too, not just web. Verified: opened the
read-only web view, edited the same playlist via a plain API call
(simulating a mobile client), and watched the new song appear in the web
tab with no reload.

The backend side of this needed **no changes** — `events/ws_auth.py`
already authenticates the socket via a JWT in the query string
(`?token=...`), not a header, specifically because that's the only thing
a browser's native `WebSocket` API can send (it can't set arbitrary
headers on the handshake). That was already correct for a browser
client before this bonus existed.

### 3. `google_sign_in` — breaks on the *first* web sign-in, disabled on web (your call)

Read `google_sign_in_web`'s source directly
(`gis_client.dart`): on web, the imperative `signIn()` this app calls
routes through Google Identity Services' **token** flow, not the
**credential** (ID token) flow — *unless* a credential was already
cached from a prior silent/One Tap sign-in. On a user's first-ever
"Continue with Google" tap in a browser, the response is explicitly
documented in the plugin's own source as "This synthetic response will
*not* contain an `idToken` field" — and this app's backend call requires
one. So the existing button would have failed for most real users, not
worked with reduced functionality.

Three fixes were possible: (a) a native `renderButton()` widget on web
(frontend-only, but different button styling), (b) keep the custom
button and add a backend endpoint that accepts an OAuth access token
instead of an ID token, (c) disable it on web for now. **You chose (c).**
Email/password still works fully on web; the button is hidden (not
shown-disabled) on the Welcome screen, Login screen, and the "Link
Google Account" card in Settings — "Unlink" stays available since it's a
plain REST call, not the broken SDK flow. Verified via screenshot: no
"OR" divider or Google button renders on either auth screen on web.

### 4. `geocoding` — no web implementation; the part that mattered got a backend fix

The plugin has Android/iOS/macOS platform packages only. Two different
uses, two different outcomes:

- **Reverse geocoding** (GPS coordinates → a human-readable label, used
  by "use my current location" in Edit Profile and Create Event): the
  existing code already wraps every call in try/catch and falls back to
  raw coordinates on any failure, by design. Added an explicit `kIsWeb`
  early-return so this doesn't even attempt the doomed native call — same
  behavior, no wasted round-trip. Low-stakes: a convenience label, never
  blocks the actual feature (event creation still works with the venue's
  raw lat/lng either way).
- **Forward geocoding** (a profile's free-text location → coordinates)
  is not a nicety — it's what resolves *every vote* on a
  location-restricted event. Silently returning `null` here would have
  made that one license rule permanently unvotable from a browser, which
  is a real gap against "full read/write, respect existing license
  rules," not a graceful degradation.

  **You chose the backend proxy option.** Added `GET /api/v1/geocode/`
  (`backend/api/views.py::GeocodeView`, wired in `api/urls.py`, its own
  `GeocodeRateThrottle`/`"geocode": "300/min"` throttle scope) that
  forward-geocodes via the Google Geocoding API using `GOOGLE_API_KEY` —
  an env var that already existed in `settings.py` but was completely
  unused until now. This mirrors the existing pattern of the backend
  proxying Deezer/Audius for track search, rather than introducing a new
  third-party dependency or API shape. `location_label.dart`'s
  `forwardGeocodeCoordinates` now branches on `kIsWeb`: native calls the
  plugin as before, web calls this endpoint. A backend failure now
  surfaces its real, specific message ("no location found for X" vs.
  "the geocoding service is unreachable") instead of collapsing to a
  generic one — both the vote-time and the upfront-restriction-check call
  sites in `event_detail_screen.dart` already had (or now have) a catch
  clause for it.

  **Caveat found while testing:** the endpoint is wired correctly and
  reaches Google fine, but in this dev environment the configured
  `GOOGLE_API_KEY` doesn't have the **Geocoding API** enabled in Google
  Cloud Console, so real requests currently 502 with a clear "unable to
  reach the geocoding service" message rather than crashing — confirmed
  by calling the Google API directly from inside the backend container
  and seeing `REQUEST_DENIED` / `"This API is not activated on your API
  project."`. Enabling that API on the key (a Google Cloud Console
  action, not a code change) is the one remaining step to make
  location-restricted voting fully live on web.

### 5. `flutter_secure_storage` — real web implementation, but a race condition surfaced in testing

This one wasn't a compatibility gap — `flutter_secure_storage_web`
genuinely works on web (see [Token storage](#token-storage-security)
below for what it actually does). But driving a real login through a
headless browser surfaced an intermittent
`RethrownDartError: OperationError` right after sign-in. Reading
`flutter_secure_storage_web`'s source explains why: the *first* write for
a given keychain lazily generates and persists a shared AES-GCM wrapping
key; `TokenStorage.saveTokens` wrote the access and refresh tokens via
`Future.wait([...])`, i.e. concurrently — and two near-simultaneous first
writes both raced to create that same key, with the loser throwing.

**Fix:** `TokenStorage.saveTokens` now awaits the two writes
sequentially instead of via `Future.wait`. Both tokens always ended up
stored correctly either way (the error didn't lose data), but this
removes the race outright, and the cost of not parallelizing two tiny
writes is negligible. Verified: repeated fresh logins with full console
capture, zero `pageerror` events after the fix, previously one every
time.

### 6. `audioplayers_web` — Audius playback broken by a hardcoded `crossOrigin`, fixed server-side

Found live: Audius ("full") tracks failed to play on web with
`PlatformException(WebAudioError, ... MediaError: MEDIA_ELEMENT_ERROR:
Format error (Code: 4))` — a notoriously unhelpful browser error that
gives no hint it's actually a CORS problem. Deezer previews played fine.

Root cause, confirmed directly (not guessed): `audioplayers_web`
unconditionally sets `crossOrigin = "anonymous"` on its underlying
`<audio>` element (`wrapped_player.dart`). Audius's stream URL
(`GET /v1/tracks/<id>/stream`) is a discovery-node URL that 302-redirects
to the actual content-node CDN URL — and that 302 response itself carries
**no CORS headers at all** (only the final response does). A plain
`<audio>` element without `crossOrigin` set doesn't care and follows the
redirect fine; a `crossOrigin`-flagged one fails the *entire* load the
moment any hop in the chain lacks CORS headers, and the browser reports
that failure as a generic "format error" instead of a CORS error. Verified
by instantiating a bare `<audio>` in a real browser against the exact
failing URL: fails with `crossOrigin` set, plays fine without it. Deezer's
preview URLs have no redirect hop, so they were never affected either way.

**Fix:** the backend's `GET /tracks/<id>/preview/` (already the mandatory
app's "resolve immediately before playback" endpoint, used by every
playback call site — event auto-play, playlist preview, search-result
preview — via `resolvePreviewUrl`) now actually follows that redirect for
Audius ids and returns the resolved content-node URL instead of the
unresolved discovery-node one. The resolved URL already sends
`Access-Control-Allow-Origin: *`, so handing the client that instead
sidesteps `audioplayers_web`'s `crossOrigin` requirement entirely — no
client-side or platform-specific code needed, and it's one extra
lightweight hop (the redirect response has no body) on a call that was
already being made fresh before every playback. No pros/cons fork here —
resolving server-side is strictly better than the alternative (patching
around `audioplayers_web`'s own source, which isn't ours to edit, or
adding a second, web-only playback code path) and has no downside on
native, where `crossOrigin` doesn't exist as a concept.

### 7. Plugins that just work on web, unchanged

- **`geolocator`** — has a real web implementation
  (`geolocator_web`, browser Geolocation API). The existing
  best-effort, silent-failure pattern for Home's distance display and
  Create Event's "use current location" needed no changes.
- **`image_picker`** — has a real web implementation
  (`image_picker_for_web`, `<input type=file>`); works for profile/cover
  photo selection, feeding into fix #1 above.
- **`audioplayers`** — has a real web implementation
  (`audioplayers_web`); track previews play in both Track Vote and the
  (read-only) Playlist Editor.
- **`flutter_dotenv`** — pure-Dart asset read, identical on every
  platform.

## CORS

```python
# backend/config/settings.py — before
CORS_ALLOW_ALL_ORIGINS = True
CORS_ALLOW_CREDENTIALS = True
CORS_ALLOWED_ORIGINS = os.getenv('CORS_ALLOWED_ORIGINS', 'http://localhost:3000').split(',')
CSRF_TRUSTED_ORIGINS = ['http://localhost:3000', 'https://localhost:3000']

# backend/config/settings.py — after
CORS_ALLOW_ALL_ORIGINS = False
CORS_ALLOW_CREDENTIALS = True
CORS_ALLOWED_ORIGINS = [o.strip() for o in os.getenv('CORS_ALLOWED_ORIGINS', 'http://localhost:5000').split(',') if o.strip()]
CSRF_TRUSTED_ORIGINS = [o.strip() for o in os.getenv('CSRF_TRUSTED_ORIGINS', 'http://localhost:5000').split(',') if o.strip()]
```

**Why mobile never needed this at all:** CORS is a *browser* mechanism —
the browser withholds a cross-origin response from the page's JS unless
the response carries an `Access-Control-Allow-Origin` header naming that
exact origin. A mobile HTTP client doesn't send an `Origin` header and
doesn't enforce this at all; the concept doesn't apply to it. The Flutter
*web* build, running as JS inside an actual browser, is the first client
this project has ever had that CORS/CSRF governs.

**Why this was a real change and not just "add the port":** the setting
was already `CORS_ALLOW_ALL_ORIGINS = True`, which — combined with
`CORS_ALLOW_CREDENTIALS = True` — makes django-cors-headers *reflect
whatever Origin the request sent* rather than send a literal `*` (which
credentialed requests can't use per spec anyway). That already let the
web client through with zero backend changes. You chose to tighten this
to an explicit allowlist instead of leaving the more permissive default
in place, since a real, known list of origins is what this project
actually needs going forward, not "allow literally anything."

Verified directly with curl against the running backend:
`Origin: http://localhost:5000` gets back
`Access-Control-Allow-Origin: http://localhost:5000` +
`Access-Control-Allow-Credentials: true`; `Origin: http://evil.example.com`
gets back neither header.

`.env`/`.env.example` (both the root one `docker-compose.yml` loads, and
`backend/.env.example` which didn't have these vars documented before)
were updated to include `http://localhost:5000` and to document
`GOOGLE_API_KEY`.

## Token storage security

Confirmed empirically what `flutter_secure_storage_web`'s source implies
by loading the app and reading `localStorage` directly:

```
FlutterSecureStorage.auth_access_token   -> AES-GCM ciphertext (base64)
FlutterSecureStorage.auth_refresh_token  -> AES-GCM ciphertext (base64)
FlutterSecureStorage                     -> the wrapping key itself
```

The tokens *are* encrypted at rest, but the AES-GCM key that decrypts
them lives in the **same `localStorage`** the ciphertext does. Any
JavaScript with access to this origin — most concretely, an XSS payload
— can read both and decrypt everything using the same WebCrypto calls
the app itself makes. That's meaningfully weaker than mobile's
`flutter_secure_storage`, which is backed by the Android Keystore / iOS
Keychain: on mobile, the key material is hardware/OS-isolated and not
retrievable by application code at all, XSS-equivalent or not. Practical
implication: this project's existing CSP/XSS hygiene matters more once a
browser build exists, since a successful injection on web can lift a
live session in a way it structurally cannot on mobile. No code change
was made here — this is a platform ceiling of "secure storage on the
web," not a bug — but the trade-off is worth flagging explicitly since
it's exactly the kind of thing that's invisible until you go looking for
it. `flutter_secure_storage_web` also requires a "secure context"
(HTTPS, or `localhost` for dev) — it throws outright otherwise, which
means this bonus (and any encrypted-token session on web at all) needs
HTTPS in production.

## Responsive breakpoints

**Approach:** `MediaQuery`/`LayoutBuilder`, no new layout package — the
project's existing widgets (`NavigationRail`, `Wrap`, `Row`/`Column`)
already cover everything needed. A grid package would have added a
dependency for something two built-in widgets already do correctly.

- `lib/core/responsive/responsive.dart` is the one new shared piece:
  - `Breakpoints.desktop = 900` / `isDesktopWidth(context)` — a single
    threshold used everywhere, chosen at small-tablet-landscape width so
    a resized browser window crosses it well before a single stretched
    phone column would look wrong.
  - `ResponsiveScaffold` — swaps `AppBottomNav` for a `NavigationRail`
    down the left edge above the breakpoint, same four destinations
    either way. Applied to all four bottom-nav root screens (Home, Track
    Vote, Playlist Editor, Profile) — once the rail exists at all, it has
    to be consistent across every tab, not just the two this bonus's
    required-steps list names explicitly.
  - `ResponsiveCardGrid` — lays event/playlist hero cards out as a
    `Wrap` once more than one column fits, one plain scrolling column
    below that. Deliberately **not** a `GridView`: these cards don't
    share a fixed height (the badge row alone can wrap to one or two
    lines depending on which restrictions an event has), and
    `GridView`'s per-cell `childAspectRatio` would risk overflow the
    moment one card is taller than the rest — confirmed this reasoning by
    checking the card widgets' content rather than assuming it. `Wrap`
    lets each card size to its own content while still flowing into
    rows, at the cost of items in a row not vertically aligning to the
    tallest one — an acceptable trade for cards this variable, and it's
    what Track Vote's event list and the Playlist Editor's list both use.
  - **Bug found and fixed during testing:** the column math originally
    computed how many cards fit *before* subtracting the `ListView`'s own
    horizontal padding, so a width that should fit 3 cards only fit 2 (the
    3rd card's fixed width plus spacing overflowed the padded space it
    actually had to render in). Confirmed via screenshot at 1280px width
    (2 columns with ~390px of dead space on the right), fixed by
    computing `availableWidth = constraints.maxWidth - padding.horizontal`
    up front, reverified with a screenshot showing a clean 3-column grid.
- **Event detail (voting view)** and **Playlist detail (read-only
  view)**: below the breakpoint, unchanged single-column layout. At/above
  it, the existing content is split into an info column (cover, title,
  badges, participants/collaborators, now-playing or play button) fixed
  at 340–380px on the left, and the queue/song list scrolling in the
  remaining width on the right — verified live in the browser at
  1280×900 for both screens.

## What was explicitly left out, and why

- **Music Control Delegation** — not implemented anywhere in this
  project (mandatory or bonus); untouched here, per your instruction.
- **Any write/edit path in the Playlist Editor on web** — add song,
  reorder (drag-and-drop specifically excluded per your brief), remove,
  manage collaborators, edit playlist metadata/cover, create, delete.
  All gated behind `canEdit = hasEditPermission && !kIsWeb` (or an
  equivalent `kIsWeb` check for create/delete, which aren't
  permission-gated at all). A dedicated "Viewing on web" banner replaces
  the permission-based "request access to edit" banner specifically on
  web, since a web viewer isn't missing permission — they're missing a
  mobile device, and the existing banner's copy/CTA would have been
  actively misleading for e.g. an owner or an "everyone can edit"
  playlist.
- **Google Sign-In on web** — deferred; see plugin section above.
  Backend has zero Google-auth changes; this is 100% a client-side
  decision, reversible independently later (either fix in the table
  there).
- **Reverse geocoding on web** ("use my current location" auto-filling a
  readable label) — degrades to raw coordinates, matching the existing
  fallback the mobile app already relies on for the same failure mode.
- **A dev-time way to point web and mobile at different `API_BASE_URL`s
  simultaneously** — both currently read the same `mobile/.env`; you
  switch it manually depending which platform you're actively running.
  Noted above as the one recurring manual step, not fixed here since it's
  unrelated to making the app work on web, just a convenience.

## Testing performed

- `flutter analyze` — clean (only pre-existing, unrelated lints).
- `flutter build web` — succeeds (this is what actually proves
  `dart:io` usage elsewhere in the codebase, e.g. the mobile-only
  playlist create/edit screens, doesn't break the web build: importing
  `dart:io` compiles fine on web via the SDK's shim, it only throws if a
  class like `File`/`WebSocket` is actually instantiated at runtime, and
  those screens are unreachable on web by design).
- Backend: `python manage.py check` clean; existing `events`/`api`/
  `playlists` test suites re-run unmodified. 4 pre-existing failures in
  `events.tests.EventActivityStatusTests` (auto status transitions
  landing on `party_of_nobody` where `live`/`ghost_town`/`rip_attendance`
  were expected) — confirmed unrelated to this bonus by reverting every
  backend file this work touched (`config/settings.py`, `api/views.py`,
  `api/urls.py`, `api/throttles.py`) and re-running: identical 4
  failures on the untouched code. Pre-existing bug, worth a look
  separately, not introduced or masked here.
- End-to-end in a real, headless Chrome (via Playwright, driven by
  coordinates since Flutter web renders to a `<canvas>`/CanvasKit with no
  real DOM text to query) against the actual backend running via
  `docker compose`:
  - Fresh email/password login on web, session persists across a full
    browser restart (localStorage), no console/page errors after the
    `TokenStorage` fix.
  - `NavigationRail` replaces the bottom bar at ≥900px width; bottom bar
    unchanged below it.
  - Track Vote: 3-column card grid on Discover at 1280px; opening an
    event shows the two-column info/queue layout; clicking a song's vote
    control registers the vote and the UI reflects the new count and
    "voted" state immediately.
  - Playlist Editor: read-only view shows the "Viewing on web" banner,
    no drag handles, and a disabled (not hidden) add-song button that
    does nothing when clicked; a song added via a separate API call (as
    a stand-in for a mobile client's edit) appears in the open web tab
    live, via the new cross-platform WebSocket, with no reload.
  - Google Sign-In button confirmed absent on both the Welcome and Login
    screens on web.
  - **Concurrency:** fired 10 truly simultaneous authenticated vote
    requests (same user, same song) at the backend. Exactly one
    succeeded (`201`, `vote_count: 1`); the other nine were rejected with
    `400 "You have already voted for this song."` Verified at the
    database level (`Vote.objects.filter(...).count() == 1`), not just
    from the HTTP responses. This is the same `unique_together`/
    `IntegrityError` mechanism the mandatory backend already used for
    every client — it's pure server-side/DB-level protection with no
    knowledge of what platform originated a request, so a browser tab
    racing another browser tab is provably no different from two mobile
    clients racing each other.
  - CORS verified with curl against the live backend (see above).
