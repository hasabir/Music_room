# IV.8 agility and quality evidence

This file is an evidence index. Link actual issues, pull requests, reviews, demos,
and retrospectives; do not mark an item complete without an artifact.

## Iteration record

| Iteration/date | Goal | Demo or result | Retrospective change |
| --- | --- | --- | --- |
| 2026-09-11 | Establish repeatable local capacity testing | 10-user read p95 reduced from 2,000/1,000 ms for events/playlists to 180/210 ms | Rejected aggregate-count joins after measured regression; used bounded prefetches |
| 2026-09-11 | Run the write-contention/WebSocket/two-client scripts for the first time | Found `seed_load_test_data.py` had silently under-seeded the shared load target (1 member instead of 999); backfilled the live DB and got a clean 0-failure write/WebSocket run | Compare-by-id instead of object equality, plus a hard `CommandError` on member-count mismatch, so a future silent under-seed fails loudly instead of producing an unusable target |

## Review evidence

| Change | Issue | Pull request | Reviewer | CI result |
| --- | --- | --- | --- | --- |
| Capacity workload and list-query optimization | Pending | Pending | Pending | Pending |

## Release evidence checklist

- [ ] Backend CI job passed on the reviewed commit. (Not yet — `.github/workflows/quality.yml` has never run on GitHub; nothing has been pushed.)
- [ ] Flutter CI job passed on the reviewed commit. (Same — untested on hosted CI, though `flutter analyze`/`flutter test` pass locally.)
- [ ] Another team member approved the pull request. (No PR opened yet.)
- [x] Two-client create/join/vote/reorder/reconnect scenario was demonstrated. (`tests/load/two_client_smoke.py`, 2026-09-11: `create_join_vote_reorder_reconnect: passed`.)
- [x] Read, write-contention, and WebSocket capacity reports were attached. (See `docs/QUALITY_AND_CAPACITY.md` — read report plus the first write/WebSocket validation run; escalating write/WebSocket levels is still open.)
- [ ] The decision log and API documentation match the released behavior.

GitHub authentication and another team member are required to complete the pending
review entries. Local test output cannot substitute for an independent review.
