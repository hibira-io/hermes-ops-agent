#!/usr/bin/env bash
# Smoke test: a real Hermes in the image, a scripted model, no Approvals
# workspace. A risky command must be blocked (fail closed) and an everyday
# command must run.
set -euo pipefail
IMAGE=${1:-hermes-ops-agent:dev}
HERE=$(cd "$(dirname "$0")" && pwd)
DATA=$(mktemp -d)
PORT=18999
stop_stub() { if [ -n "${STUB:-}" ]; then kill "$STUB" 2>/dev/null || true; wait "$STUB" 2>/dev/null || true; fi; }
cleanup() { docker rm -f hoa-smoke >/dev/null 2>&1 || true; stop_stub; }
trap cleanup EXIT

start_stub() {
  stop_stub
  STUB_COMMAND="$1" python3 "$HERE/stub_llm.py" "$PORT" & STUB=$!
  sleep 1
}

docker run -d --name hoa-smoke --network host -v "$DATA:/opt/data" \
  -e HERMES_BASE_URL="http://127.0.0.1:$PORT/v1" -e HERMES_MODEL=stub -e OPENAI_API_KEY=stub \
  -e GRAFANA_URL=http://127.0.0.1:3000 -e CLOUDFLARE_API_TOKEN=test \
  "$IMAGE" sleep infinity >/dev/null
for _ in $(seq 1 30); do docker logs hoa-smoke 2>&1 | grep -q '\[hibira\]' && break; sleep 1; done
docker logs hoa-smoke 2>&1 | grep '\[hibira\]'
docker logs hoa-smoke 2>&1 | grep -q 'terminal approvals: on; modules: grafana, cloudflare' || { echo "FAIL: setup line"; exit 1; }

docker exec -u hermes hoa-smoke sh -c 'mkdir -p /opt/data/workspace/old-logs && touch /opt/data/workspace/old-logs/a.log'
chat() { docker exec -u hermes -e HOME=/opt/data -w /opt/data/workspace hoa-smoke hermes chat -Q --oneshot -q "$1" 2>&1; }

start_stub "rm -rf /opt/data/workspace/old-logs"
out=$(chat "clean up old logs"); echo "$out" | grep 'TOOL RESULT'
docker exec hoa-smoke test -d /opt/data/workspace/old-logs || { echo "FAIL: risky command ran without approval"; exit 1; }
echo "$out" | grep -q 'not connected to a Hibira Approvals workspace' || { echo "FAIL: expected the connect message"; exit 1; }

start_stub "ls /opt/data/workspace"
out=$(chat "what is in the workspace"); echo "$out" | grep 'TOOL RESULT'
echo "$out" | grep -q 'old-logs' || { echo "FAIL: everyday command did not run"; exit 1; }

for bin in aws gcloud wrangler mcp-grafana elasticsearch-core-mcp-server prometheus-mcp-server dbhub mcp-approval-gate; do
  docker exec hoa-smoke sh -c "command -v $bin" >/dev/null || { echo "FAIL: $bin missing"; exit 1; }
done
echo "smoke test passed"
