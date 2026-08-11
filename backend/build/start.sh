#!/bin/bash
set -e
echo "Waiting for database..."
sleep 5
echo "Running migrations..."
python3 manage.py makemigrations --noinput
python3 manage.py migrate --noinput
echo "Starting Django dev server (auto-reload enabled)..."
exec python3 manage.py runserver 0.0.0.0:8000