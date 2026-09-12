.PHONY: help build up down restart logs shell migrate makemigrations createsuperuser test clean flutter-web flutter-web-build ngrok load-up load-down load-seed load-read load-write load-websocket load-e2e

#test

help:
	@echo "Music Room - Development Commands"
	@echo "=================================="
	@echo "make ngrok          - Build web, start backend and print a public ngrok URL (Ctrl+C stops sharing)"
	@echo "make build          - Build Docker containers"
	@echo "make up             - Start all services"
	@echo "make down           - Stop all services"
	@echo "make restart        - Restart all services"
	@echo "make logs           - View logs"
	@echo "make shell          - Open Django shell"
	@echo "make bash           - Open bash in backend container"
	@echo "make migrate        - Run database migrations"
	@echo "make makemigrations - Create new migrations"
	@echo "make createsuperuser- Create Django superuser"
	@echo "make test           - Run tests"
	@echo "make clean          - Remove containers and volumes"
	@echo "make flutter-get    - Install Flutter dependencies"
	@echo "make flutter-run    - Run Flutter app"
	@echo "make flutter-web    - Run the Flutter app in Chrome (needs 'make up' running; see docs/WEB_BONUS.md)"
	@echo "make flutter-web-build - Compile the Flutter web build without opening a browser"
	@echo "make setup          - Initial setup (build, migrate, create superuser)"
	@echo "make dev            - Start development workflow (up + logs)"
	@echo "make db             - Load test data into the database"
	@echo "make load-up        - Start the isolated production-like load stack"
	@echo "make load-seed      - Seed synthetic load data and copy ignored credentials"
	@echo "make load-read USERS=30 TIME=3m - Run an authenticated read benchmark"
	@echo "make load-write EVENT_ID=1 EVENT_SONG_ID=1 - Run vote/retract contention"
	@echo "make load-websocket EVENT_ID=1 EVENT_SONG_ID=1 - Probe WebSocket fan-out"
	@echo "make load-e2e       - Run the automated two-client collaboration flow"
	@echo "make load-down      - Stop the load stack (keeps its database volume)"


build:
	docker-compose build

up:
	docker-compose up --build
# 	@echo "Services started. Backend: http://localhost:8000"

down:
	docker-compose down

restart: down up

logs:
	docker-compose logs -f

logs-backend:
	docker-compose logs -f backend

shell:
	docker-compose exec backend python manage.py shell

bash:
	docker-compose exec backend bash

migrate:
	docker-compose exec backend python manage.py migrate

makemigrations:
	docker-compose exec backend python manage.py makemigrations

createsuperuser:
	docker-compose exec backend python manage.py createsuperuser

test:
	docker-compose exec backend python manage.py test

fclean:
	docker-compose down -v --remove-orphans
	docker system prune -f

clean:
	docker-compose down --remove-orphans
	docker rm -f $$(docker ps -aq)
	docker image rm -f $$(docker images -q)

volume_clean:
	docker volume rm $$(docker volume ls -q)

db:
	docker compose exec backend python manage.py loaddata build/test_users.json
	docker compose exec backend python manage.py loaddata build/test_profiles.json
	docker compose exec backend python manage.py loaddata build/test_friendships.json

# Initial setup
setup:
	docker-compose up --build -d
	sleep 5
	docker-compose exec backend python manage.py migrate
	docker-compose exec backend python manage.py createsuperuser
	@echo "Setup complete!"

flutter-get:
	@cd mobile &&  flutter pub get
	@echo "Flutter setup is complete"

# At the top of your Makefile
flutter-setup:
	@if [ -z "$(PORT)" ]; then \
		echo "Error: PORT argument is required"; \
		echo "Usage: make flutter-setup PORT=5555"; \
		exit 1; \
	fi
	@echo "Connecting to 10.32.54.146:$(PORT)..."
	@adb connect 10.32.54.146:$(PORT) 2>&1 | grep -q "connected" || true
	@if adb devices | grep -q "10.32.54.146:$(PORT)\s\+device"; then \
		echo "✅ Connected to 10.32.54.146:$(PORT)"; \
		echo "$(PORT)" > .flutter_device_port; \
		echo "Device port saved to .flutter_device_port"; \
	else \
		echo "❌ Could not connect to 10.32.54.146:$(PORT)"; \
		adb disconnect 10.32.54.146:$(PORT) > /dev/null 2>&1 || true; \
		exit 1; \
	fi

flutter-run:
	@if [ -f .flutter_device_port ]; then \
		PORT=$$(cat .flutter_device_port); \
		echo "Using device port: $$PORT"; \
		cd mobile && flutter run -d 10.32.54.146:$$PORT; \
	else \
		echo "❌ No device port found. Please run 'make flutter-setup PORT=<port>' first"; \
		exit 1; \
	fi

frun:
	@cd mobile && flutter run

# Web bonus (see docs/WEB_BONUS.md). Needs the backend up first (`make up`).
# WEB_PORT must match an origin listed in the backend's
# CORS_ALLOWED_ORIGINS/CSRF_TRUSTED_ORIGINS (http://localhost:5000 is
# already the default in backend/.env.example) — override both together if
# you use a different one, e.g. `make flutter-web WEB_PORT=5001`.
WEB_PORT ?= 5000
flutter-web:
	@cd mobile && flutter run -d chrome --web-port=$(WEB_PORT)

# Compiles the web build without launching a browser — a fast way to
# confirm nothing's broken (equivalent to what CI would run).
flutter-web-build:
	@cd mobile && flutter build web

NGROK_PORT ?= 5001
ngrok:
	@NGROK_PORT=$(NGROK_PORT) bash scripts/ngrok.sh

LOAD_USERS ?= 30
LOAD_TIME ?= 3m
load-up:
	docker compose -p music-room-load -f docker-compose.load.yml up -d --build

load-seed:
	docker compose -p music-room-load -f docker-compose.load.yml exec -T backend python manage.py seed_load_test_data --users 1000 --events 100 --playlists 100 --songs 200 --output /tmp/load-accounts.json
	docker compose -p music-room-load -f docker-compose.load.yml cp backend:/tmp/load-accounts.json tests/load/accounts.json

load-read:
	mkdir -p tests/load/results
	LOAD_ACCOUNTS_FILE=$(CURDIR)/tests/load/accounts.json tests/load/.venv/bin/locust -f tests/load/locustfile.py --headless --host http://127.0.0.1:18082 --users $(LOAD_USERS) --spawn-rate 6 --run-time $(LOAD_TIME) --stop-timeout 15 --csv tests/load/results/read-users-$(LOAD_USERS) --csv-full-history --html tests/load/results/read-users-$(LOAD_USERS).html --only-summary

load-write:
	LOAD_ACCOUNTS_FILE=$(CURDIR)/tests/load/accounts.json LOAD_EVENT_ID=$(EVENT_ID) LOAD_EVENT_SONG_ID=$(EVENT_SONG_ID) tests/load/.venv/bin/locust -f tests/load/locustfile_write.py --headless --host http://127.0.0.1:18082 --users $(LOAD_USERS) --spawn-rate 6 --run-time $(LOAD_TIME) --stop-timeout 15 --csv tests/load/results/write-users-$(LOAD_USERS) --csv-full-history --html tests/load/results/write-users-$(LOAD_USERS).html --only-summary

load-websocket:
	tests/load/.venv/bin/python tests/load/websocket_probe.py --accounts tests/load/accounts.json --event-id $(EVENT_ID) --event-song-id $(EVENT_SONG_ID) --users $(LOAD_USERS)

load-e2e:
	tests/load/.venv/bin/python tests/load/two_client_smoke.py --accounts tests/load/accounts.json

load-down:
	docker compose -p music-room-load -f docker-compose.load.yml down

# Development workflow
dev: up logs

# test workflow
