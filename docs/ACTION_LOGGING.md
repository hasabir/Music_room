# Action logging

Every `/api/` HTTP request generates an `api.request` row in `ActionLog`,
including reads, validation failures, denied requests, and unmatched routes.
Browser OPTIONS preflights are excluded. Existing domain events such as
`event.vote_cast` remain separate entries for the activity feed.

The shared Flutter HTTP transport sends these headers on every request,
including anonymous authentication requests, pagination, and multipart uploads:

| Header | Value |
| --- | --- |
| `X-Platform` | Android, iOS, Web, or desktop OS |
| `X-Device` | Manufacturer/model on Android; hardware model on iOS; browser/OS on web |
| `X-App-Version` | Installed package version and build number, e.g. `1.0.0+1` |

`device_info_plus` and `package_info_plus` read this information once per app
session. Values are bounded to the database field lengths. If platform metadata
cannot be read, the affected value is explicitly `Unknown`; normal requests
continue. Existing clients that omit the headers retain blank fields.
Rebuild/restart the app after installing the new native plugins.

## Local interactions

`POST /api/v1/user/actions/` accepts JSON containing one `action`:

```json
{"action": "playback.pause"}
```

Allowed values: `interaction`, `navigation`, `playback.play`, `playback.pause`,
`playback.resume`, `playback.stop`, `playback.seek`.
Success returns `204` with no body; invalid actions return `400`; the per-user
(anonymous: per-IP) limit is 120 requests/minute, returning `429` when exceeded.
JWT authentication is optional so welcome/login interactions can be recorded.
The backend derives the user from authentication, never from client input.
These records have a `client.` prefix and represent client-reported actions,
not authoritative proof that playback or a business operation succeeded.

Flutter records completed pointer interactions, Enter/Space activation,
navigation pushes/pops/replacements, and player commands. Interaction records
are deliberately generic; they do not capture text, coordinates or widget values.
The HTTP request audit covers the server-side result of business operations.

Local telemetry is best effort: failures do not interrupt the UI, at most 20
sends may be pending, and events are not queued/retried offline or after login.
This avoids replaying one user's events as a later user. No offline logging or
synchronization guarantee is provided.

## Stored data and access

Request audit metadata contains only method, resolved route template, HTTP
status and elapsed milliseconds. No request/response bodies, query strings,
authorization tokens, passwords, uploaded files, or raw unmatched paths are
stored. Device identifiers, serial numbers and owner-assigned device names
are not collected. Metadata headers are client-reported, not trusted identity.

Admins can read `GET /api/v1/user/logs/`, including each record's `metadata`.
Request and client audit records do not enter other users' profile activity feeds.
An audit database failure is reported to server error logs without replacing
an already-completed API result with an error. No database migration is needed.

## Checks

```sh
docker compose exec -T backend python manage.py test user.test_action_logging --noinput
cd mobile
flutter test test/client_metadata_test.dart
```
