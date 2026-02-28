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

build:
	docker-compose build

up:
	docker-compose up -d
	@echo "Services started. Backend: http://localhost:8000"

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

clean:
	docker-compose down -v
	docker system prune -f

# Flutter commands
flutter-get:
	cd mobile && flutter pub get

flutter-run:
	cd mobile && flutter run

flutter-build-android:
	cd mobile && flutter build apk

flutter-build-ios:
	cd mobile && flutter build ios

# Initial setup
setup: build up migrate createsuperuser
	@echo "Setup complete!"

# Development workflow
dev: up logs
