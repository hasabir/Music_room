#!/bin/bash

echo "🎵 Music Room - Quick Start Script"
echo "=================================="
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

echo "✅ Docker and Docker Compose are installed"
echo ""

# Copy .env file if it doesn't exist
if [ ! -f backend/.env ]; then
    echo "📝 Creating .env file from example..."
    cp backend/.env.example backend/.env
    echo "✅ .env file created"
else
    echo "✅ .env file already exists"
fi

echo ""
echo "🔨 Building Docker containers..."
docker-compose build

echo ""
echo "🚀 Starting services..."
docker-compose up -d

echo ""
echo "⏳ Waiting for services to be ready..."
sleep 10

echo ""
echo "📦 Running database migrations..."
docker-compose exec -T backend python manage.py migrate

echo ""
echo "👤 Creating superuser..."
echo "Please enter superuser credentials:"
docker-compose exec backend python manage.py createsuperuser

echo ""
echo "✅ Setup complete!"
echo ""
echo "📌 Your Music Room is ready:"
echo "   - API: http://localhost:8000"
echo "   - Admin: http://localhost:8000/admin"
echo ""
echo "📚 Useful commands:"
echo "   make help       - Show all available commands"
echo "   make logs       - View application logs"
echo "   make down       - Stop all services"
echo "   make restart    - Restart all services"
echo ""
echo "Happy coding! 🎶"
