"""Vote/retract contention workload for one seeded public event song."""
import json
import os
from collections import deque

from locust import HttpUser, between, events, task
from locust.exception import StopUser

accounts = deque()


@events.test_start.add_listener
def prepare(environment, **kwargs):
    with open(os.environ["LOAD_ACCOUNTS_FILE"], encoding="utf-8") as source:
        records = json.load(source)
    required = environment.parsed_options.num_users
    if len(records) < required:
        raise ValueError("Provide at least one account per virtual user")
    accounts.clear()
    accounts.extend(records)


class VotingUser(HttpUser):
    wait_time = between(1, 3)

    def on_start(self):
        if not accounts:
            raise StopUser()
        response = self.client.post("/api/v1/auth/login/", json=accounts.popleft(), timeout=15)
        try:
            token = response.json()["tokens"]["access"]
        except (ValueError, KeyError, TypeError):
            raise StopUser()
        self.client.headers["Authorization"] = f"Bearer {token}"
        self.vote_path = (
            f"/api/v1/events/{os.environ['LOAD_EVENT_ID']}/queue/"
            f"{os.environ['LOAD_EVENT_SONG_ID']}/vote/"
        )

    @task
    def vote_then_retract(self):
        with self.client.post(
            self.vote_path, name="POST /api/v1/events/[id]/queue/[song]/vote/",
            catch_response=True, timeout=15,
        ) as response:
            if response.status_code != 201:
                response.failure(f"Expected vote 201, received {response.status_code}")
                return
        with self.client.delete(
            self.vote_path, name="DELETE /api/v1/events/[id]/queue/[song]/vote/",
            catch_response=True, timeout=15,
        ) as response:
            if response.status_code != 200:
                response.failure(f"Expected retract 200, received {response.status_code}")


@events.quitting.add_listener
def check_thresholds(environment, **kwargs):
    for method, name in (
        ("POST", "POST /api/v1/events/[id]/queue/[song]/vote/"),
        ("DELETE", "DELETE /api/v1/events/[id]/queue/[song]/vote/"),
    ):
        stats = environment.stats.get(name, method)
        if stats.num_requests < 100 or stats.fail_ratio > 0.01 \
                or (stats.get_response_time_percentile(0.95) or 0) > 500:
            environment.process_exit_code = 1
