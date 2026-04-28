#!/bin/bash
set -e

IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1")
PORT="${COACHDESK_API_PORT:-3000}"
echo "Debug server: http://$IP:$PORT"
flutter run \
  --dart-define=DEBUG_SERVER_IP="$IP" \
  --dart-define=COACHDESK_API_PORT="$PORT" \
  "$@"
