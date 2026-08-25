#!/usr/bin/env bash
# Updates API_BASE_URL in mobile/.env to this machine's current LAN IP,
# so the app can be pointed at whatever Wi-Fi network the dev machine is on.
#
# Usage: ./scripts/update_api_ip.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
PORT="8000"

IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") print $(i+1)}')

if [ -z "$IP" ]; then
  echo "Could not detect LAN IP (no default route found)." >&2
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "API_BASE_URL not found: $ENV_FILE does not exist." >&2
  exit 1
fi

NEW_URL="http://${IP}:${PORT}"

if grep -q '^API_BASE_URL=' "$ENV_FILE"; then
  sed -i "s|^API_BASE_URL=.*|API_BASE_URL=${NEW_URL}|" "$ENV_FILE"
else
  echo "API_BASE_URL=${NEW_URL}" >> "$ENV_FILE"
fi

echo "Updated API_BASE_URL to ${NEW_URL} in $ENV_FILE"
echo "Hot-restart the Flutter app for the change to take effect."
