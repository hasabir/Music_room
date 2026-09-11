"""Open authenticated subscribers, trigger one vote, and verify broadcast delivery."""
import argparse
import json
import statistics
import time
from urllib.parse import quote

import requests
import websocket


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:18082")
    parser.add_argument("--accounts", required=True)
    parser.add_argument("--event-id", required=True)
    parser.add_argument("--event-song-id", required=True)
    parser.add_argument("--users", type=int, default=10)
    parser.add_argument("--timeout", type=float, default=5)
    args = parser.parse_args()

    with open(args.accounts, encoding="utf-8") as source:
        accounts = json.load(source)[:args.users]
    if len(accounts) < args.users:
        raise SystemExit("Not enough accounts")

    tokens = []
    for account in accounts:
        response = requests.post(f"{args.base_url}/api/v1/auth/login/", json=account, timeout=15)
        response.raise_for_status()
        tokens.append(response.json()["tokens"]["access"])

    ws_base = args.base_url.replace("http://", "ws://").replace("https://", "wss://")
    sockets = []
    try:
        for token in tokens:
            connection = websocket.create_connection(
                f"{ws_base}/ws/events/{args.event_id}/queue/?token={quote(token)}",
                timeout=args.timeout,
                http_proxy_host=None,
            )
            sockets.append(connection)

        vote_url = (
            f"{args.base_url}/api/v1/events/{args.event_id}/queue/"
            f"{args.event_song_id}/vote/"
        )
        headers = {"Authorization": f"Bearer {tokens[0]}"}
        requests.delete(vote_url, headers=headers, timeout=15)
        started = time.perf_counter()
        response = requests.post(vote_url, headers=headers, json={}, timeout=15)
        response.raise_for_status()

        latencies = []
        for connection in sockets:
            payload = json.loads(connection.recv())
            if str(payload.get("event_id")) != str(args.event_id):
                raise RuntimeError("Received a broadcast for the wrong event")
            latencies.append((time.perf_counter() - started) * 1000)

        print(json.dumps({
            "connections": len(sockets),
            "delivered": len(latencies),
            "missed": len(sockets) - len(latencies),
            "median_ms": round(statistics.median(latencies), 2),
            "max_ms": round(max(latencies), 2),
        }))
    finally:
        for connection in sockets:
            connection.close()


if __name__ == "__main__":
    main()
