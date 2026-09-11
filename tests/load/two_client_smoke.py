"""Two authenticated clients exercise the critical collaborative API flow."""
import argparse
import json
import time
from urllib.parse import quote

import requests
import websocket


def expect(response, status):
    if response.status_code != status:
        raise RuntimeError(f"{response.request.method} {response.url}: {response.status_code} {response.text}")
    return response.json() if response.content else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:18082")
    parser.add_argument("--accounts", required=True)
    args = parser.parse_args()
    with open(args.accounts, encoding="utf-8") as source:
        accounts = json.load(source)[:2]

    sessions = []
    tokens = []
    for account in accounts:
        session = requests.Session()
        login = expect(session.post(f"{args.base_url}/api/v1/auth/login/", json=account, timeout=15), 200)
        token = login["tokens"]["access"]
        session.headers["Authorization"] = f"Bearer {token}"
        expect(session.post(
            f"{args.base_url}/api/v1/user/subscription/", json={"tier": "premium"}, timeout=15
        ), 200)
        sessions.append(session)
        tokens.append(token)

    host, guest = sessions
    suffix = int(time.time())
    event = expect(host.post(f"{args.base_url}/api/v1/events/", json={
        "title": f"Two-client smoke {suffix}", "visibility": "public", "max_participants": 10,
    }, timeout=15), 201)
    event_id = event["id"]
    expect(guest.post(f"{args.base_url}/api/v1/events/{event_id}/join/", timeout=15), 201)
    event_songs = []
    for index in range(2):
        event_songs.append(expect(host.post(
            f"{args.base_url}/api/v1/events/{event_id}/queue/",
            json={"title": f"E2E Song {suffix}-{index}", "artist": "Synthetic"}, timeout=15,
        ), 201))

    ws_base = args.base_url.replace("http://", "ws://").replace("https://", "wss://")
    ws_url = f"{ws_base}/ws/events/{event_id}/queue/?token={quote(tokens[1])}"
    socket = websocket.create_connection(ws_url, timeout=5, http_proxy_host=None)
    try:
        vote_path = f"{args.base_url}/api/v1/events/{event_id}/queue/{event_songs[0]['id']}/vote/"
        expect(guest.post(vote_path, json={}, timeout=15), 201)
        first_broadcast = json.loads(socket.recv())
        if first_broadcast["event_id"] != event_id:
            raise RuntimeError("Guest received the wrong event broadcast")
    finally:
        socket.close()

    # Prove a disconnected client can reconnect and continue receiving updates.
    socket = websocket.create_connection(ws_url, timeout=5, http_proxy_host=None)
    try:
        vote_path = f"{args.base_url}/api/v1/events/{event_id}/queue/{event_songs[1]['id']}/vote/"
        expect(host.post(vote_path, json={}, timeout=15), 201)
        reconnect_broadcast = json.loads(socket.recv())
        if reconnect_broadcast["event_id"] != event_id:
            raise RuntimeError("Reconnected guest received the wrong event broadcast")
    finally:
        socket.close()

    playlist = expect(host.post(f"{args.base_url}/api/v1/playlists/", json={
        "title": f"Two-client playlist {suffix}", "visibility": "public", "edit_permission": "everyone",
    }, timeout=15), 201)
    playlist_id = playlist["id"]
    expect(guest.post(f"{args.base_url}/api/v1/playlists/{playlist_id}/join/", timeout=15), 201)
    playlist_songs = []
    for index in range(2):
        playlist_songs.append(expect(host.post(
            f"{args.base_url}/api/v1/playlists/{playlist_id}/songs/",
            json={
                "title": f"Playlist E2E Song {suffix}-{index}",
                "artist": "Synthetic",
                "external_id": f"e2e-{suffix}-{index}",
            }, timeout=15,
        ), 201))
    expect(guest.post(
        f"{args.base_url}/api/v1/playlists/{playlist_id}/songs/{playlist_songs[1]['id']}/move/",
        json={"new_position": 0}, timeout=15,
    ), 200)
    reordered = expect(guest.get(
        f"{args.base_url}/api/v1/playlists/{playlist_id}/songs/", timeout=15
    ), 200)
    if reordered[0]["id"] != playlist_songs[1]["id"]:
        raise RuntimeError("Playlist reorder was not persisted")

    expect(host.delete(f"{args.base_url}/api/v1/playlists/{playlist_id}/", timeout=15), 204)
    expect(host.delete(f"{args.base_url}/api/v1/events/{event_id}/", timeout=15), 204)
    print(json.dumps({
        "event_id": event_id,
        "playlist_id": playlist_id,
        "create_join_vote_reorder_reconnect": "passed",
    }))


if __name__ == "__main__":
    main()
