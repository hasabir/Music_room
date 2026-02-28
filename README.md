# Music Room

A collaborative music room application where users can vote on songs, manage playlists, and delegate control.

## Project Structure

```
music-room/
├── backend/          # Django REST API with Channels (WebSocket)
├── mobile/           # Flutter mobile application
├── docker-compose.yml
└── Makefile
```

## Features

- 🎵 Real-time collaborative playlists
- 🗳️ Vote on songs (upvote/downvote)
- 👥 Room-based music sessions
- 🎛️ Delegation system for room control
- 🔐 JWT authentication
- 🔌 WebSocket support for real-time updates

## Quick Start

### Backend Setup

1. Copy environment file:
```bash
cp backend/.env.example backend/.env
```

2. Build and start services:
```bash
make build
make up
```

3. Run migrations:
```bash
make migrate
```

4. Create superuser:
```bash
make createsuperuser
```

5. Access the application:
- API: http://localhost:8000
- Admin: http://localhost:8000/admin

### Mobile Setup

1. Navigate to mobile folder:
```bash
cd mobile
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the app:
```bash
flutter run
```

## Available Commands

```bash
make help              # Show all available commands
make up                # Start services
make down              # Stop services
make logs              # View logs
make shell             # Django shell
make migrate           # Run migrations
make makemigrations    # Create migrations
make test              # Run tests
```

## API Endpoints

### Authentication
- `POST /api/users/token/` - Obtain JWT token
- `POST /api/users/token/refresh/` - Refresh JWT token

### Users
- `GET /api/users/` - List users
- `POST /api/users/` - Register user
- `GET /api/users/me/` - Get current user

### Rooms & Playlists
- `GET /api/playlist/rooms/` - List rooms
- `POST /api/playlist/rooms/` - Create room
- `GET /api/playlist/songs/` - List songs
- `POST /api/playlist/songs/` - Add song

### Voting
- `GET /api/vote/` - List votes
- `POST /api/vote/` - Cast vote

### Delegation
- `GET /api/delegation/` - List delegations
- `POST /api/delegation/` - Create delegation

## Tech Stack

### Backend
- Django 5.0
- Django REST Framework
- Django Channels (WebSocket)
- PostgreSQL
- Redis
- Docker

### Mobile
- Flutter
- Dart

## Development

### Backend
The backend uses Django with Channels for WebSocket support, enabling real-time features like live voting and playlist updates.

### Database Models
- **User**: Custom user model with profile info
- **Room**: Music rooms with unique codes
- **Song**: Songs in playlists with voting
- **Vote**: User votes on songs
- **Delegation**: Permission delegation system

## License

MIT
