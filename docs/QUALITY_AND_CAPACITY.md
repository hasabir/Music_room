# V.7 Ramp-up and IV.8 quality

## Scope and current evidence

The three functional services are interpreted here as profiles/users, events, and
playlists. They share one Django application, PostgreSQL and Redis; they are not
three independently deployed servers. Confirm this mapping against the evaluation
rubric. The checked-in workload measures authenticated HTTP reads across all three.
It does not establish capacity for voting, writes, WebSocket fan-out, audio playback,
external music search or geocoding. Those need separate workload measurements before
claiming a maximum for the complete product.

**Maximum supported users: not yet measured.** No thousands-of-users claim follows
from choosing a low-end server. The current Compose backend uses `runserver` and
`DEBUG=1`; measurements there are development baselines only.

## Reproducible load experiment

Use a disposable staging database populated with representative profiles, public
and private events, memberships, playlists and songs. Record counts and visibility
mix. Provision distinct verified test accounts through the application's normal
setup process. Save a JSON array of `{"email":"...","password":"..."}` objects
in `tests/load/accounts.json` (ignored by Git). Never use real user credentials.
Use at least as many distinct accounts as the highest virtual-user level.

For this local-computer evaluation, start the isolated load stack with
`docker compose -p music-room-load -f docker-compose.load.yml up -d --build`.
It uses a separate PostgreSQL volume, Daphne with `DEBUG=0`, and fixed CPU/RAM
limits. The API is available through Nginx at `http://127.0.0.1:18082`. This can
run alongside the development stack because its project, volume, network and host
port are separate. Record exact dependency versions and do not change resource
limits between test levels.

From the repository root on the local test machine:

```sh
python3 -m venv tests/load/.venv
tests/load/.venv/bin/pip install -r tests/load/requirements.txt
mkdir -p tests/load/results
export LOAD_ACCOUNTS_FILE="$PWD/tests/load/accounts.json"
tests/load/.venv/bin/locust -f tests/load/locustfile.py --headless \
  --host http://127.0.0.1:18082 --users 10 --spawn-rate 2 \
  --run-time 10m --stop-timeout 15 --csv tests/load/results/users-10 \
  --csv-full-history --html tests/load/results/users-10.html
```

Use a single Locust process: account allocation in this script is not distributed.
Each user logs in once, then chooses profile/event/playlist reads at weights 1:2:2,
with 1–3 seconds of think time after each request. Concurrent sessions are different
from simultaneous in-flight requests; report measured requests/second too.
See [Locust task semantics](https://docs.locust.io/en/stable/writing-a-locustfile.html)
and [headless execution](https://docs.locust.io/en/stable/running-without-web-ui.html).

Repeat at 10, 25, 50, 100, 250, 500 and 1000 users, stopping at saturation. Allow
recovery between runs. Adjust spawn rate so ramp-up finishes within one minute;
run time includes ramp-up. Use history CSV to evaluate the remaining steady window,
not just the aggregate report. Repeat each candidate level three times and soak the
highest passing level for 30 minutes. Retest around the failure boundary.

Proposed acceptance criteria, to agree before testing: each service has p95 <=500 ms,
error rate <=1%, at least 100 samples, stable memory and no persistent queue growth.
The script additionally fails on any HTTP failure or user exception, including login
failures; this is deliberately stricter than the proposed error budget. A passing
exit code is only a preliminary check: inspect the steady-state window, achieved
user count and server metrics. Include 429s as failures; do not silently disable
throttling. Record cold-cache and warm-cache results separately.

While running, capture timestamped `docker stats`, host CPU/memory, disk latency,
PostgreSQL connections/locks and Redis memory/latency. Also monitor the generator;
a saturated generator cannot establish server capacity. Preserve raw CSV, HTML,
logs, git revision, exact command and dependency versions with each report.

## Measurement report (fill from the actual deployment)

| Characteristic | Measured/configured value |
| --- | --- |
| Date, commit, scenario and data counts | 2026-09-11; commit `b132d33` plus uncommitted benchmark changes; 1,000 users, 100 events, 100 playlists, 200 songs |
| Cloud provider/instance or on-premise hardware | On-premise local laptop; server and load generator share the host |
| CPU model, cores/vCPUs and architecture | Intel Core i7-13620H; 10 physical cores, 16 logical CPUs; x86_64 |
| RAM, swap and container CPU/RAM limits | 15 GiB RAM, 39 GiB swap; backend 4 CPUs/4 GiB, PostgreSQL 2 CPUs/2 GiB, Redis 0.5 CPU/512 MiB, Nginx 0.5 CPU/256 MiB |
| OS/kernel, disk type and capacity | Ubuntu Linux, kernel 6.8.0-139-generic; 476.9 GB WD PC SN740 NVMe SSD |
| Network bandwidth, generator location and RTT | Loopback/local Docker network; bandwidth and RTT measurement pending |
| ASGI processes, PostgreSQL/Redis versions and limits | One Daphne 4.2.3 process; PostgreSQL 15.19 (2 CPUs/2 GiB); Redis 7.4.11 (0.5 CPU/512 MiB) |
| Generator CPU/RAM and Locust version | Same local host; Locust 2.46.5 on Python 3.12.9 |

Use `lscpu`, `free -h`, `uname -a`, `lsblk` on the server and generator; host totals
alone do not describe a resource-limited container. Get cloud instance allocation
from deployment records. Do not publish secrets from environment files or full
container inspections.

| Users | Achieved RPS | Profile p95 | Event p95 | Playlist p95 | Errors | CPU/RAM peak | Pass |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 10 (initial 2-minute smoke) | 3.81 | 390 ms* | 2,000 ms | 1,000 ms | 0 | Backend 62%, 81 MiB; DB 29%, 48 MiB (one sample) | Fail |
| 10 (first query optimization, 3 minutes) | 2.78 | 290 ms* | 6,400 ms | 820 ms | 0 | Backend 16%, 83 MiB; DB 196%, 201 MiB (one sample) | Fail |
| 10 (prefetch optimization, 3 minutes) | 4.69 | 110 ms | 180 ms | 210 ms | 0 | Resource sample pending | Pass |
| 25 (3 minutes) | 11.58 | 170 ms | 240 ms | 310 ms | 0 | Backend 45%, 97 MiB; DB 100%, 124 MiB (one sample) | Pass |
| 35 (boundary run 1, 3 minutes) | 15.98 | 310 ms | 400 ms | 470 ms | 0 | Resource sample pending | Pass |
| 35 (boundary run 2, 3 minutes) | 15.99 | 330 ms | 440 ms | 530 ms | 0 | Resource sample pending | Fail |
| 40 (boundary, 3 minutes) | 17.90 | 470 ms | 590 ms | 860 ms | 0 | Resource sample pending | Fail |
| 50 (3 minutes) | 20.05 | 730 ms | 1,100 ms | 1,400 ms | 0 | Backend 117%, 122 MiB; DB 207%, 196 MiB (one sample) | Fail |
| 30 (repeat 1, 3 minutes) | 13.85 | 230 ms | 300 ms | 410 ms | 0 | Resource sample pending | Pass |
| 30 (repeat 2, 3 minutes) | 13.83 | 220 ms | 300 ms | 370 ms | 0 | Resource sample pending | Pass |
| 30 (repeat 3, 3 minutes) | 13.94 | 230 ms | 310 ms | 400 ms | 0 | Resource sample pending | Pass |

`*` The profile service had fewer than the required 100 samples in both smoke runs.
The second run revealed a regressed PostgreSQL query plan and is retained as honest
experimental evidence; aggregate count joins were removed afterward. The replacement
prefetch implementation passed 37 focused response tests and the third 10-user run.

Report the highest repeatedly passing steady level as the **tested read capacity**,
and the first failing level as a bound. If no level fails, report “at least N tested”,
not a maximum. Reserve operational headroom (for example 30%, explicitly a policy)
when setting the advertised capacity. Never extrapolate linearly from a laptop or
Raspberry Pi to a cloud instance.

The authenticated vote/retract workload is `tests/load/locustfile_write.py`; set
`LOAD_EVENT_ID` and `LOAD_EVENT_SONG_ID` to the shared seeded target. After it exits,
verify that no votes remain for that target. `tests/load/websocket_probe.py` opens
authenticated persistent subscribers, triggers one vote broadcast, and reports
delivery latency and missed messages. Measure third-party-dependent routes
separately with controlled stubs, then validate provider quotas independently.

The critical two-client collaboration check is automated by
`tests/load/two_client_smoke.py`. It upgrades two synthetic accounts through the mock
subscription API, then exercises event creation, joining, voting, WebSocket delivery,
disconnect/reconnect, playlist creation/joining/reordering, persistence, and cleanup:

```sh
tests/load/.venv/bin/python tests/load/two_client_smoke.py \
  --accounts tests/load/accounts.json
```

### Write-contention, WebSocket, and two-client results (first validated run)

Date/commit: 2026-09-11, on top of commit `b132d33` plus the uncommitted benchmark
and seed-script changes. Same on-premise hardware as the read report above.

Running the write and WebSocket scripts for the first time surfaced a real defect
in `seed_load_test_data.py`, not a capacity result: the shared event that all 1,000
synthetic users are supposed to join for these two scripts (`shared_event`, the
deterministic write/WebSocket target) had only 1 member instead of 999. The
`EventMembership` bulk_create that was supposed to add the other 998 produced zero
rows — reproducing the same seeding logic against freshly-queried objects inserted
them correctly, which points at stale/aliased in-memory `User`/`Event` objects
carried across the earlier bulk_create calls in that one large transaction as the
likely cause. `seed_load_test_data.py` now compares by `user.id`/`shared_event.host_id`
instead of by object equality and raises `CommandError` if the resulting member count
doesn't match `len(users) - 1`, so a future silent under-seed fails the command
instead of quietly producing an unusable load target. The live load database's
membership was backfilled directly (999 members confirmed) to unblock this run.

| Script | Config | Result |
| --- | --- | --- |
| `locustfile_write.py` (vote/retract) | 10 users, 3 min, single shared song | 1,700 requests (845 vote + 845 retract), 0 failures, vote p95 120 ms, retract p95 93 ms — passes the script's own gate (>=100 samples, <=1% errors, p95<=500 ms) |
| `websocket_probe.py` | 10 subscribers, 1 triggered vote | 10/10 delivered, 0 missed, 69 ms median latency |
| `two_client_smoke.py` | 2 accounts, full flow | `create_join_vote_reorder_reconnect: passed` |

This is one short run at one concurrency level (10 users), not the repeated,
escalating-level protocol the read benchmark above went through — it demonstrates
the harness now works end-to-end and gives a first real data point, not a write or
WebSocket capacity bound. Escalating this to the same 10/25/50/... levels, three
repeats, and a 30-minute soak (as done for reads) is still open before any
write/WebSocket capacity claim can be made.

## IV.8 Team workflow and layer-specific quality

Use short iterations with a prioritised issue backlog. Each issue should state user
value, acceptance criteria, owner and a small deliverable. Review progress together,
demo working slices and use retrospectives to change the next iteration. Record
tradeoffs and changed decisions in `DECISIONS.md`, including evidence and consequences.
These are team practices to follow, not claims that meetings already happened.

| Layer | Existing checks / required evidence |
| --- | --- |
| Models and database | Django model tests, real PostgreSQL constraints and event/playlist concurrency tests |
| Authentication and permissions | Authentication, user, profile and access-control tests; reject unauthorised actions |
| HTTP API and integrations | API serializer/endpoint tests, mocked external services, GPS-location regression tests |
| Realtime | Event socket authentication/authorization/delivery regression tests plus the WebSocket load probe |
| Flutter | Existing responsive, metadata, cover-selection and checkout widget/unit tests; static analysis |
| End-to-end | Record a manual two-client create/join/vote/reorder/reconnect scenario before release |
| Deployment and performance | Repeatable staging benchmark above, hardware report and raw result artifacts |

`.github/workflows/quality.yml` runs backend checks, migration drift detection and
all installed application test suites against PostgreSQL/Redis, plus Flutter analysis
and tests on pushes and pull requests. Coverage is retained as an artifact. Configure
branch protection in GitHub to require both jobs and peer review. CI is not proof of
agility: retain issue history, reviewed PRs, demos and decision revisions as evidence.

For each bug, add a focused regression test in the affected layer before fixing it.
A change is done when acceptance criteria pass, relevant tests and CI pass, a peer
reviews it, and API/decision documentation is updated. Run load tests on controlled
staging hardware before releases or performance-sensitive changes; shared CI runners
are suitable for smoke checks, not defensible production capacity numbers.

## Local validation of this addition

Flutter: 198 tests passed. Load-script Python syntax and workflow YAML parsing
passed; these checks do not constitute a load run or a successful hosted CI run.
Backend: the initial 328-test run had four failures caused by list assertions against
paginated responses. Those assertions were updated; all 11 tests in the affected
notification and playlist-collaborator classes passed on rerun. The entire suite
was not rerun after these assertion-only changes. Hosted CI remains to be executed.
