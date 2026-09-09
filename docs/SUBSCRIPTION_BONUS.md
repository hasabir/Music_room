# Bonus: Free vs. Premium Subscription

This documents the mock subscription tier added on top of the existing
app — the model, the three server-side gates it enforces, the
concurrency mechanism that makes the two per-event caps race-safe, and
the design decisions made along the way (four of which were confirmed
with you explicitly before implementation, called out below).

## Scope

- **A `subscription_tier` on `User`** — `free` (default) or `premium` —
  switched via a mock endpoint, `POST /api/v1/user/subscription/`. No
  payment gateway; it's a direct field write plus an audit log entry.
- **Three gates, all enforced server-side**, never trusted from the
  client:
  1. **Playlist Editor:** editing a **public** playlist requires
     Premium, regardless of `editPermission` — even "everyone can edit"
     is overridden. Private playlists are entirely unaffected.
  2. **Track Vote suggestions:** Free accounts may suggest at most 10
     tracks per event (lifetime-cumulative — see below); Premium is
     unlimited. Rejected with `403` + `code: "suggestion_limit_reached"`.
  3. **Track Vote voting:** Free accounts may have at most 20 *distinct*
     tracks voted per event at any one time (live count — see below);
     Premium is unlimited. Rejected with `403` + `code:
     "vote_limit_reached"`.
- **Out of scope, untouched:** the existing `visibility`/`editPermission`
  playlist model, the existing event vote-license rules
  (open/invited-only/time/location), the existing per-song vote
  uniqueness constraint, real payment processing.

## Four decisions confirmed with you before implementing

The brief left these genuinely ambiguous; each was raised as an
explicit question rather than assumed:

1. **The public-playlist gate applies to the owner too — no exemption.**
   A Free-tier owner of their own public, "everyone can edit" playlist
   cannot add/remove/reorder songs on it until they upgrade (or make it
   private).
2. **Suggestion count is lifetime-cumulative per event.** It never
   decreases, even after a suggested song is later removed, played out,
   or revived by someone else. A Free user who suggests 10 songs and
   watches all 10 get played still cannot suggest an 11th in that event.
3. **Vote count is live/current per event — the opposite rule.**
   Retracting a vote frees a slot immediately. A Free user at 20/20 can
   always make room for a new vote by un-voting an old one first.
4. **Event hosts are not exempt from either limit.** Hosting an event
   grants moderation capabilities elsewhere in the app, but not a bigger
   suggestion or vote allowance — the host is just another participant
   for the purposes of these two caps.

## Why suggestions and votes use opposite counting semantics

This asymmetry is deliberate, not an inconsistency:

- **Suggestions need a new, monotonic, stored counter.**
  `EventSong.added_by` can't be reused to derive "how many has this user
  suggested" — reviving a previously-played song (an existing feature)
  reassigns `added_by` to whoever revives it, which would *decrease* the
  original suggester's count the moment their song gets played and later
  revived by someone else. A dedicated counter that only ever increments
  is the only way to make "at most 10, ever, in this event" mean what it
  says.
- **Votes need no stored count at all.** "Distinct tracks voted, right
  now" is already exactly `Vote.objects.filter(voter=user,
  event_song__event=event).count()` — the existing
  `unique_together("event_song", "voter")` constraint already guarantees
  one `Vote` row per distinct song per voter. Retraction
  (`VoteView.delete`) is a plain, pre-existing filter+delete; it needed
  **zero code changes** to "free a slot," because nothing about the vote
  limit is stored anywhere separate from the `Vote` rows themselves.

## Race-safe limit enforcement: `EventParticipation`

Both caps are check-then-act operations under concurrent requests from
the same user, so they need real locking, not just an app-level count
check. New model, `backend/events/models.py`:

```python
class EventParticipation(models.Model):
    event = models.ForeignKey(Event, on_delete=models.CASCADE, related_name="participations")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="event_participations")
    suggestion_count = models.PositiveIntegerField(default=0)
    class Meta:
        unique_together = ("event", "user")
```

`backend/events/services.py`:

```python
def lock_participation(event, user):
    EventParticipation.objects.get_or_create(event=event, user=user)
    return EventParticipation.objects.select_for_update().get(event=event, user=user)
```

This is called as the **first line inside** the `transaction.atomic()`
block each of `EventQueueView.post` (suggestions) and `VoteView.post`
(votes) already opens — it's the *same* `select_for_update()`-inside-
`transaction.atomic()` pattern `playlists/services.py` already uses for
reorder operations, applied at a new anchor point. This is layered **on
top of**, not a replacement for, the existing `Vote` unique-constraint +
`IntegrityError` protection against double-voting the same song — that
mechanism still runs exactly as before, inside the same transaction,
just alongside the new limit check.

**Why lock a per-`(event, user)` row, not the whole `Event`:** locking
`Event` itself would serialize *every* user's suggestions/votes on that
event against each other, which is unnecessary contention — the limit is
per-user, so only one user's own concurrent attempts need to serialize.
Locking the target rows directly (`EventSong`/`Vote`) doesn't work
either: a count-then-insert pattern has no row to lock until after the
insert, which is exactly the phantom-read window a race exploits.
`EventParticipation` exists specifically to be a dedicated, always-
already-present lock anchor for this per-user check, independent of
whatever rows the operation itself is about to create.

`get_or_create()` is safe to call before the `select_for_update()`
line without its own explicit transaction: Django's `get_or_create`
already wraps its internal `create()` call in its own nested
`atomic()` savepoint and retries on `IntegrityError` if two requests
race to create the same row — confirmed against Django's own source,
not assumed.

**Concretely, the race this prevents:** a Free user at 9/10 suggestions
fires two concurrent requests for two different new songs. Both call
`lock_participation`; Postgres grants the row lock to whichever
transaction's `SELECT ... FOR UPDATE` arrives first and blocks the
other until the first commits. The second transaction's lock only
resolves *after* it can see the first transaction's committed
`suggestion_count = 10` — so it deterministically fails the cap check.
Exactly one of the two succeeds, every time, not a matter of scheduling
luck. The same reasoning applies to votes at the 19→20 boundary. This
was verified with a real concurrency test (`backend/events/
test_concurrency.py`, `TransactionTestCase` + `threading.Barrier` +
5 real threads on separate DB connections) hammering each boundary —
exactly 1 of 5 succeeds, asserted against the final DB state, not just
HTTP status codes.

## Playlist editor gate: exact placement and precedence

`backend/playlists/permissions.py` — `can_user_add_songs` and
`can_user_reorder_songs` (the only two permission functions actually
wired into views) each gained one check, placed **immediately after**
the existing visibility/access check and **before** the
owner/`editPermission`/collaborator branches:

```python
if playlist.visibility == "public" and not user.is_premium:
    return False, (
        "Editing a public playlist requires Premium — upgrade your account, "
        "or ask the owner to make this playlist private."
    ), "public_playlist_requires_premium"
```

That ordering is what makes the gate apply regardless of
`editPermission` and with no owner exemption: the owner-always-wins
branch is simply never reached for a public playlist on a Free account,
because the function has already returned `False` above it. A private
playlist never reaches this line at all — its existing behavior under
`editPermission` is provably untouched, since the new check only
triggers on `visibility == "public"`.

## Mobile UI

- **Settings > Subscription** — current tier, what Premium unlocks, a
  "UPGRADE TO PREMIUM" action opens a demo card checkout with cardholder,
  card number (checksum), expiry, and CVC validation. Test details such as
  `4242 4242 4242 4242`, a future `MM/YY`, and `123` are accepted.
  Processing precedes the existing tier API; success appears only after it
  confirms activation. Card details are never sent or persisted, and no
  charge or recurring billing occurs. "DOWNGRADE TO FREE" remains behind
  a confirmation dialog explaining nothing already-suggested/voted is undone.
- **Event detail:** a suggestion-count caption ("`7/10 suggestions
  used`") and a vote-count caption near the queue when the limit
  applies (`null` limit from the API = Premium = no caption). At the
  suggestion cap, the "Suggest a track" button is replaced with an
  upsell button opening Settings > Subscription directly. A queue row is
  only disabled for voting when the user is at the vote cap *and hasn't
  already voted that song* — an already-voted row stays interactive,
  since retracting it is exactly how a Free user frees a slot.
- **Suggest-track screen:** receives the caller's current count/limit,
  shows a banner, and short-circuits locally once at the limit (purely
  to avoid a pointless round trip — the backend still re-checks and is
  the actual source of truth, since the local count can be stale).
- **Playlist detail:** `canEdit` becomes `hasEditPermission &&
  !isPremiumBlocked`. A new banner ("Editing a public playlist requires
  Premium...") appears only for someone who would otherwise be allowed
  to edit (owner, or granted by `editPermission`) but is blocked purely
  by tier — a stranger with no edit permission at all still sees the
  existing invited-only/"ask the owner" banner instead, regardless of
  their tier.
- All error codes (`suggestion_limit_reached`, `vote_limit_reached`,
  `public_playlist_requires_premium`) surface as plain, specific
  snackbar messages via typed exceptions
  (`SuggestionLimitReachedException`, `VoteLimitReachedException`) —
  never a generic "something went wrong."

## What a real payment gateway would replace

Only `SubscriptionSwitchView` (`backend/user/views.py`) — the single
direct `request.user.subscription_tier = new_tier; request.user.save()`
write. Nothing about the three enforcement points (`can_user_add_songs`/
`can_user_reorder_songs`, `EventQueueView.post`, `VoteView.post`) would
change: they all gate on `user.is_premium`, a plain property derived
from `subscription_tier`, with no awareness of *how* that field got set.
A real integration (Stripe/PayPal webhook flipping the tier on payment
success/subscription cancellation) would only ever need to touch that
one write path.

## Testing performed

- Backend: `python manage.py test events api playlists user` — full
  suite green (230 tests), including new `SubscriptionLimitTests`
  (11th suggestion blocked, 21st distinct vote blocked, retraction
  frees a slot, Premium unrestricted on both, host gets no exemption),
  new `PlaylistPremiumGateTests` (Free owner blocked from editing their
  own public playlist, Premium succeeds, Free editing a private
  playlist under identical `editPermission` rules is unaffected), and
  `test_concurrency.py` (exactly 1 of 5 concurrent requests succeeds at
  each boundary, verified at the DB level).
- Manual verification via curl against the running backend: tier switch
  both directions; `/events/<id>/` returns `my_suggestion_count`/
  `my_suggestion_limit`/`my_vote_count`/`my_vote_limit` correctly
  (`null` limits for Premium); 11th suggestion and 21st vote both return
  `403` with the documented `code`.
- `flutter analyze` — clean (only pre-existing, unrelated lints in files
  this feature didn't touch).
- `flutter build web` — succeeds.
