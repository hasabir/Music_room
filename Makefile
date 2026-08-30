.PHONY: help build up down restart logs shell migrate makemigrations createsuperuser test clean

help:
	@echo "Music Room - Development Commands"
	@echo "=================================="
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
	@echo "make setup          - Initial setup (build, migrate, create superuser)"
	@echo "make dev            - Start development workflow (up + logs)"
	@echo "make db             - Load test data into the database"


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
	@echo "Connecting to 10.238.233.157:$(PORT)..."
	@adb connect 10.238.233.157:$(PORT) 2>&1 | grep -q "connected" || true
	@if adb devices | grep -q "10.238.233.157:$(PORT)\s\+device"; then \
		echo "✅ Connected to 10.238.233.157:$(PORT)"; \
		echo "$(PORT)" > .flutter_device_port; \
		echo "Device port saved to .flutter_device_port"; \
	else \
		echo "❌ Could not connect to 10.238.233.157:$(PORT)"; \
		adb disconnect 10.238.233.157:$(PORT) > /dev/null 2>&1 || true; \
		exit 1; \
	fi

flutter-run:
	@if [ -f .flutter_device_port ]; then \
		PORT=$$(cat .flutter_device_port); \
		echo "Using device port: $$PORT"; \
		cd mobile && flutter run -d 10.238.233.157:$$PORT; \
	else \
		echo "❌ No device port found. Please run 'make flutter-setup PORT=<port>' first"; \
		exit 1; \
	fi

# Development workflow
dev: up logs
