#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

for tool in docker flutter node ngrok curl python3; do
  command -v "$tool" >/dev/null || { echo "Missing required command: $tool" >&2; exit 1; }
done
export NGROK_PORT="${NGROK_PORT:-5001}"
node -e '
const server = require("net").createServer();
server.on("error", () => {console.error("Port " + process.env.NGROK_PORT + " is in use. Stop the existing server or use make ngrok NGROK_PORT=5002."); process.exit(1);});
server.listen(Number(process.env.NGROK_PORT), "127.0.0.1", () => server.close());
'
ngrok version
ngrok config check
docker compose up -d db redis backend
echo "Building the web release..."
(cd mobile && flutter build web --release --no-web-resources-cdn --pwa-strategy=none)

runtime_dir=$(mktemp -d "${TMPDIR:-/tmp}/music-room-ngrok.XXXXXX")
proxy_pid=''
tunnel_pid=''
cleanup() {
  trap - EXIT INT TERM
  if [[ -n "$tunnel_pid" ]]; then kill "$tunnel_pid" 2>/dev/null || true; wait "$tunnel_pid" 2>/dev/null || true; fi
  if [[ -n "$proxy_pid" ]]; then kill "$proxy_pid" 2>/dev/null || true; wait "$proxy_pid" 2>/dev/null || true; fi
  rm -rf "$runtime_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

node scripts/web-proxy.cjs >"$runtime_dir/proxy.log" 2>&1 &
proxy_pid=$!
ready=false
for ((attempt=0; attempt<60; attempt++)); do
  if ! kill -0 "$proxy_pid" 2>/dev/null; then cat "$runtime_dir/proxy.log" >&2; exit 1; fi
  web_status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://127.0.0.1:$NGROK_PORT/" || true)
  api_status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://127.0.0.1:$NGROK_PORT/api/v1/user/me/" || true)
  if [[ "$web_status" == 200 && "$api_status" == 401 ]]; then ready=true; break; fi
  sleep 1
done
if [[ "$ready" != true ]]; then echo "Web/API did not become ready. Check docker compose logs backend." >&2; exit 1; fi

ngrok http "http://127.0.0.1:$NGROK_PORT" --log=stdout --log-format=json >"$runtime_dir/ngrok.log" 2>&1 &
tunnel_pid=$!
public_url=''
for ((attempt=0; attempt<60; attempt++)); do
  if ! kill -0 "$tunnel_pid" 2>/dev/null; then cat "$runtime_dir/ngrok.log" >&2; exit 1; fi
  public_url=$(python3 - "$runtime_dir/ngrok.log" <<'PY'
import json, sys
for line in open(sys.argv[1]):
    try:
        record = json.loads(line)
    except ValueError:
        continue
    if record.get('msg') == 'started tunnel' and record.get('url', '').startswith('https://'):
        print(record['url'])
        break
PY
)
  if [[ -n "$public_url" ]]; then break; fi
  sleep 1
done
if [[ -z "$public_url" ]]; then cat "$runtime_dir/ngrok.log" >&2; echo "Timed out waiting for ngrok." >&2; exit 1; fi
printf '\nMusic Room: %s\nKeep this terminal open. Ctrl+C stops the tunnel and web server.\n\n' "$public_url"
while kill -0 "$proxy_pid" 2>/dev/null && kill -0 "$tunnel_pid" 2>/dev/null; do sleep 2; done
cat "$runtime_dir/proxy.log" "$runtime_dir/ngrok.log" >&2
exit 1
