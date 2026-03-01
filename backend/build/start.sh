#!/bin/bash
set -e

cd /app

echo "Waiting for database..."
sleep 5

echo "Running migrations..."
python3 manage.py makemigrations --noinput
python3 manage.py migrate --noinput

echo "Starting Daphne server..."
exec daphne -b 0.0.0.0 -p 8000 config.asgi:application