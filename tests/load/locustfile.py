"""Authenticated read workload; one distinct pre-provisioned account per user."""
import json
import os
from collections import deque

from locust import HttpUser, between, events, task
from locust.exception import StopUser

accounts = deque()


@events.test_start.add_listener
def prepare(environment, **kwargs):
    with open(os.environ['LOAD_ACCOUNTS_FILE'], encoding='utf-8') as source:
        records = json.load(source)
    required = environment.parsed_options.num_users
    if len(records) < required or len({r['email'] for r in records}) != len(records):
        raise ValueError('Provide at least one distinct account per virtual user')
    accounts.clear()
    accounts.extend(records)


class MusicRoomUser(HttpUser):
    wait_time = between(1, 3)

    def on_start(self):
        if not accounts:
            raise StopUser()
        account = accounts.popleft()
        with self.client.post('/api/v1/auth/login/', json=account,
                              catch_response=True, timeout=15) as response:
            try:
                token = response.json()['tokens']['access']
                if response.status_code != 200 or not token:
                    raise ValueError()
            except (ValueError, KeyError, TypeError):
                response.failure('Login did not return an access token')
                raise StopUser()
        self.client.headers['Authorization'] = f'Bearer {token}'

    def read(self, path):
        with self.client.get(path, catch_response=True, timeout=15) as response:
            if response.status_code != 200:
                response.failure(f'Expected 200, received {response.status_code}')
                return
            try:
                if not isinstance(response.json(), (dict, list)):
                    raise ValueError()
            except ValueError:
                response.failure('Expected a JSON object or list')

    @task(1)
    def profile(self):
        self.read('/api/v1/profile/me/')

    @task(2)
    def events_list(self):
        self.read('/api/v1/events/')

    @task(2)
    def playlists(self):
        self.read('/api/v1/playlists/')


@events.quitting.add_listener
def check_thresholds(environment, **kwargs):
    # Check each service separately so a fast service cannot hide a slow one.
    for path in ('/api/v1/profile/me/', '/api/v1/events/', '/api/v1/playlists/'):
        stats = environment.stats.get(path, 'GET')
        if (stats.num_requests < 100 or stats.fail_ratio > 0.01
                or (stats.get_response_time_percentile(0.95) or 0) > 500):
            environment.process_exit_code = 1
    if environment.stats.total.num_failures or environment.runner.exceptions:
        environment.process_exit_code = 1
