#!/bin/bash
set -e

echo "=== CoachDesk Deploy ==="

# Load environment
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# Build and start with docker compose
docker compose down
docker compose up --build -d

echo "=== Waiting for services ==="
sleep 8

# Health check
if curl -sf http://localhost:3010/api/health > /dev/null; then
  echo "=== CoachDesk is running on port 3010 ==="
else
  echo "=== Health check failed, checking logs ==="
  docker compose logs app --tail 50
  exit 1
fi

# Copy nginx config if exists
if [ -f nginx.conf ]; then
  echo "=== Nginx config available at nginx.conf ==="
  echo "Copy to /etc/nginx/sites-available/coachdesk and reload nginx"
fi

echo "=== Deploy complete ==="
