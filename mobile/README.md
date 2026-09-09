# Mobile Directory

This directory will contain the Flutter mobile application for Music Room.

## Setup

1. Make sure you have Flutter installed: https://flutter.dev/docs/get-started/install

2. Create a new Flutter project:
```bash
flutter create .
```

3. Install dependencies:
```bash
flutter pub get
```

4. Run the app:
```bash
flutter run
```

## Running on web

To share the web app publicly, run `make ngrok` from the repository root.
It starts the backend, builds the web release, and prints the HTTPS URL.
Keep the terminal open; Ctrl+C stops sharing while leaving the backend running.
Flutter, Node.js, Docker, curl, Python 3, and an authenticated ngrok installation
are required. Use `make ngrok NGROK_PORT=5002` if port 5001 is occupied.
The tunnel serves the app, API, media, and WebSockets together. Its browser
configuration contains only the public API URL; the local `.env` is not served.

```bash
flutter run -d chrome --web-port=5000
```

Always pass `--web-port=5000` (or update the backend's `CORS_ALLOWED_ORIGINS`/
`CSRF_TRUSTED_ORIGINS` to match whatever port you pick) — without a fixed
port, Flutter picks a random one each run, which won't be in the backend's
CORS allowlist. See `docs/WEB_BONUS.md` for what's supported on web and what
isn't yet.

## TODO

- [ ] Set up project structure
- [ ] Configure API client
- [ ] Implement authentication screens
- [ ] Create room management UI
- [ ] Build playlist interface
- [ ] Add voting functionality
- [ ] Implement WebSocket connection
- [ ] Add delegation features

- Django Backend: http://localhost:8000
- Django Admin: http://localhost:8082/admin/
- PostgreSQL: localhost:5433 (configured via environment variables)
- Redis: localhost:6380
- Adminer: http://localhost:8080
- Nginx: http://localhost:8082
