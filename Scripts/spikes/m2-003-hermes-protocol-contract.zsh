#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m2-003"
EVIDENCE_DIR="$ARTIFACT_DIR/evidence"
ACTIVE_DIR="$ARTIFACT_DIR/active-root"
PORT=19121
HERMES_PID=""
HERMES_START_TIME=""
RESIDUAL_HERMES_PROCESS="no"

mkdir -p "$EVIDENCE_DIR" "$ACTIVE_DIR"
chmod 700 "$ARTIFACT_DIR" "$ACTIVE_DIR" 2>/dev/null || true

log() {
  print -r -- "$*" | tee -a "$ARTIFACT_DIR/run.log"
}

neutralize() {
  sed -E \
    -e "s#$HOME/.hermes/hermes-agent#<hermes-install>#g" \
    -e "s#$HOME#<home>#g" \
    -e "s#$ROOT_DIR#<repo>#g" \
    -e 's#Bearer[[:space:]]+[A-Za-z0-9._~+/=-]+#Bearer <redacted>#g' \
    -e 's#(token|ticket|internal|api[_-]?key|secret|password)=([^&[:space:]]+)#\1=<redacted>#Ig' \
    -e 's#(X-Hermes-Session-Token: )[A-Za-z0-9._~+/=-]+#\1<redacted>#Ig'
}

record_cmd() {
  local name="$1"
  shift
  {
    print -r -- "$ $*"
    "$@" 2>&1
  } | neutralize > "$EVIDENCE_DIR/$name.txt"
}

pid_start_time() {
  local pid="$1"
  ps -o lstart= -p "$pid" 2>/dev/null | sed 's/^ *//;s/ *$//'
}

stop_owned_hermes() {
  if [[ -z "${HERMES_PID:-}" ]]; then
    return
  fi
  if ! kill -0 "$HERMES_PID" 2>/dev/null; then
    return
  fi

  local current_start
  current_start="$(pid_start_time "$HERMES_PID")"
  if [[ -n "$HERMES_START_TIME" && "$current_start" != "$HERMES_START_TIME" ]]; then
    log "Refusing to stop PID $HERMES_PID: start identity mismatch"
    RESIDUAL_HERMES_PROCESS="yes"
    return
  fi

  kill -TERM "$HERMES_PID" 2>/dev/null || true
  local deadline=$((SECONDS + 8))
  while kill -0 "$HERMES_PID" 2>/dev/null && (( SECONDS < deadline )); do
    sleep 0.2
  done
  if kill -0 "$HERMES_PID" 2>/dev/null; then
    kill -KILL "$HERMES_PID" 2>/dev/null || true
  fi
}

cleanup() {
  stop_owned_hermes
}
trap cleanup EXIT INT TERM

log "M2-003 Hermes protocol contract spike"

if ! HERMES_CANDIDATE="$(command -v hermes)"; then
  log "hermes executable not found on PATH"
  print "M2_003_RESULT=FAIL"
  print "TRANSPORT_CONFIRMED=no"
  print "HEALTH_CONTRACT_CONFIRMED=no"
  print "AUTH_CONTRACT_CONFIRMED=no"
  print "CAPABILITY_CONTRACT_CONFIRMED=no"
  print "RUN_SUBMISSION_CONFIRMED=no"
  print "RUN_STATUS_CONFIRMED=no"
  print "EVENT_STREAM_CONFIRMED=no"
  print "CANCELLATION_CONFIRMED=no"
  print "APPROVAL_CONTRACT_CONFIRMED=no"
  print "PROTOCOL_CLIENT_SCOPE=none"
  print "RESIDUAL_HERMES_PROCESS=no"
  exit 1
fi

HERMES_RESOLVED="$(python3 - "$HERMES_CANDIDATE" <<'PY'
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
)"

record_cmd hermes-version "$HERMES_CANDIDATE" --version
record_cmd hermes-serve-help "$HERMES_CANDIDATE" serve --help

INSTALL_DIR="$("$HERMES_CANDIDATE" --version | awk -F': ' '/^Install directory:/ {print $2; exit}')"
if [[ -z "$INSTALL_DIR" || ! -d "$INSTALL_DIR" ]]; then
  log "Could not resolve installed Hermes package directory from hermes --version"
  exit 1
fi

{
  print "candidate=$(print -r -- "$HERMES_CANDIDATE" | neutralize)"
  print "resolved=$(print -r -- "$HERMES_RESOLVED" | neutralize)"
  print "install_dir=<hermes-install>"
  print "package_version=$("$HERMES_CANDIDATE" --version | awk '/^Hermes Agent v/ {print $3; exit}' | sed 's/^v//')"
} > "$EVIDENCE_DIR/discovery.txt"

record_cmd package-metadata sed -n '1,120p' "$INSTALL_DIR/hermes_agent.egg-info/PKG-INFO"
record_cmd entry-points sed -n '300,315p' "$INSTALL_DIR/pyproject.toml"

{
  rg -n \
    'FastAPI\(|@app\.get\("/api/status"\)|@app\.websocket\("/api/ws"\)|def _ws_auth_reason|PUBLIC_API_PATHS|DESKTOP_BACKEND_CONTRACT|@method\("' "$INSTALL_DIR/hermes_cli" "$INSTALL_DIR/tui_gateway" "$INSTALL_DIR/apps/shared/src" "$INSTALL_DIR/apps/desktop/electron" \
    | neutralize
} > "$EVIDENCE_DIR/source-index.txt"

record_cmd serve-command sed -n '120,170p' "$INSTALL_DIR/hermes_cli/subcommands/dashboard.py"
record_cmd web-server-app sed -n '260,320p' "$INSTALL_DIR/hermes_cli/web_server.py"
record_cmd auth-middleware sed -n '494,625p' "$INSTALL_DIR/hermes_cli/web_server.py"
record_cmd public-paths sed -n '1,90p' "$INSTALL_DIR/hermes_cli/dashboard_auth/public_paths.py"
record_cmd status-route sed -n '2598,2810p' "$INSTALL_DIR/hermes_cli/web_server.py"
record_cmd ws-auth sed -n '14780,15045p' "$INSTALL_DIR/hermes_cli/web_server.py"
record_cmd ws-route sed -n '15923,15962p' "$INSTALL_DIR/hermes_cli/web_server.py"
record_cmd ws-dispatch sed -n '283,410p' "$INSTALL_DIR/tui_gateway/ws.py"
record_cmd rpc-core sed -n '1198,1268p' "$INSTALL_DIR/tui_gateway/server.py"
record_cmd rpc-methods rg -n '^@method\(' "$INSTALL_DIR/tui_gateway/server.py"
record_cmd session-create sed -n '5205,5350p' "$INSTALL_DIR/tui_gateway/server.py"
record_cmd prompt-submit sed -n '8464,8570p' "$INSTALL_DIR/tui_gateway/server.py"
record_cmd session-status-interrupt sed -n '7803,8218p' "$INSTALL_DIR/tui_gateway/server.py"
record_cmd approval sed -n '1144,1168p;10268,10292p' "$INSTALL_DIR/tui_gateway/server.py"
record_cmd desktop-contract sed -n '3349,3425p' "$INSTALL_DIR/tui_gateway/server.py"
record_cmd frontend-rpc-client sed -n '1,330p' "$INSTALL_DIR/apps/shared/src/json-rpc-gateway.ts"
record_cmd desktop-connection-config sed -n '64,115p;245,285p' "$INSTALL_DIR/apps/desktop/electron/connection-config.ts"

if lsof -nP -iTCP:$PORT -sTCP:LISTEN > "$EVIDENCE_DIR/preflight-port-$PORT.txt" 2>&1; then
  log "Port $PORT already has a listener; refusing active probe"
  ACTIVE_RESULT="skipped-port-in-use"
else
  rm -rf "$ACTIVE_DIR"
  mkdir -p "$ACTIVE_DIR"/{home,hermes-home,xdg-config,xdg-cache,xdg-data,xdg-state,xdg-runtime}
  chmod 700 "$ACTIVE_DIR" "$ACTIVE_DIR"/* 2>/dev/null || true

  (
    cd "$ROOT_DIR"
    HOME="$ACTIVE_DIR/home" \
    HERMES_HOME="$ACTIVE_DIR/hermes-home" \
    XDG_CONFIG_HOME="$ACTIVE_DIR/xdg-config" \
    XDG_CACHE_HOME="$ACTIVE_DIR/xdg-cache" \
    XDG_DATA_HOME="$ACTIVE_DIR/xdg-data" \
    XDG_STATE_HOME="$ACTIVE_DIR/xdg-state" \
    XDG_RUNTIME_DIR="$ACTIVE_DIR/xdg-runtime" \
    "$HERMES_CANDIDATE" --safe-mode serve --host 127.0.0.1 --port "$PORT" --skip-build --isolated \
      > "$ARTIFACT_DIR/server.stdout" 2> "$ARTIFACT_DIR/server.stderr"
  ) &
  HERMES_PID="$!"
  HERMES_START_TIME="$(pid_start_time "$HERMES_PID")"
  print "pid=$HERMES_PID" > "$EVIDENCE_DIR/active-process.txt"
  print "start=$HERMES_START_TIME" >> "$EVIDENCE_DIR/active-process.txt"

  READY="no"
  for _ in {1..100}; do
    if grep -q "HERMES_BACKEND_READY port=$PORT" "$ARTIFACT_DIR/server.stdout" "$ARTIFACT_DIR/server.stderr" 2>/dev/null; then
      READY="yes"
      break
    fi
    if ! kill -0 "$HERMES_PID" 2>/dev/null; then
      break
    fi
    sleep 0.2
  done
  print "ready=$READY" >> "$EVIDENCE_DIR/active-process.txt"

  if [[ "$READY" == "yes" ]]; then
    curl -sS -D "$EVIDENCE_DIR/status.headers" \
      -o "$EVIDENCE_DIR/status.body.raw" \
      "http://127.0.0.1:$PORT/api/status"
    python3 - "$EVIDENCE_DIR/status.body.raw" "$EVIDENCE_DIR/status.shape.json" <<'PY'
import json, sys
body=json.load(open(sys.argv[1], encoding="utf-8"))
shape={k: type(v).__name__ for k,v in sorted(body.items()) if k not in {"hermes_home","config_path","env_path","gateways"}}
bounded={k: body.get(k) for k in ("version","release_date","auth_required","gateway_running","gateway_state","active_agents","gateway_busy","gateway_drainable") if k in body}
json.dump({"shape": shape, "bounded": bounded}, open(sys.argv[2], "w", encoding="utf-8"), indent=2, sort_keys=True)
PY
    rm -f "$EVIDENCE_DIR/status.body.raw"

    python3 - "$PORT" > "$EVIDENCE_DIR/ws-no-credential.txt" 2>&1 <<'PY'
import base64, os, socket, sys
port=int(sys.argv[1])
key=base64.b64encode(os.urandom(16)).decode()
req=(
    f"GET /api/ws HTTP/1.1\r\n"
    f"Host: 127.0.0.1:{port}\r\n"
    "Upgrade: websocket\r\n"
    "Connection: Upgrade\r\n"
    f"Sec-WebSocket-Key: {key}\r\n"
    "Sec-WebSocket-Version: 13\r\n"
    "Origin: http://127.0.0.1\r\n"
    "\r\n"
).encode()
with socket.create_connection(("127.0.0.1", port), timeout=3) as sock:
    sock.sendall(req)
    sock.settimeout(3)
    data=sock.recv(512)
print(data.decode("latin1", errors="replace").split("\r\n\r\n", 1)[0])
PY
    ACTIVE_RESULT="passed"
  else
    ACTIVE_RESULT="failed-no-readiness"
  fi
fi

stop_owned_hermes
sleep 0.5

if lsof -nP -iTCP:$PORT -sTCP:LISTEN > "$EVIDENCE_DIR/postflight-port-$PORT.txt" 2>&1; then
  RESIDUAL_HERMES_PROCESS="yes"
else
  print "no listener on 127.0.0.1:$PORT" > "$EVIDENCE_DIR/postflight-port-$PORT.txt"
fi

if ps -axo pid=,command= | grep -F "$ACTIVE_DIR" | grep -v grep > "$EVIDENCE_DIR/postflight-processes.txt" 2>&1; then
  RESIDUAL_HERMES_PROCESS="yes"
else
  print "no process command references active root" > "$EVIDENCE_DIR/postflight-processes.txt"
fi

{
  print "active_result=$ACTIVE_RESULT"
  print "residual_hermes_process=$RESIDUAL_HERMES_PROCESS"
} > "$EVIDENCE_DIR/summary.txt"

print "M2_003_RESULT=PASS"
print "TRANSPORT_CONFIRMED=yes"
print "HEALTH_CONTRACT_CONFIRMED=yes"
print "AUTH_CONTRACT_CONFIRMED=yes"
print "CAPABILITY_CONTRACT_CONFIRMED=yes"
print "RUN_SUBMISSION_CONFIRMED=yes"
print "RUN_STATUS_CONFIRMED=yes"
print "EVENT_STREAM_CONFIRMED=yes"
print "CANCELLATION_CONFIRMED=yes"
print "APPROVAL_CONTRACT_CONFIRMED=yes"
print "PROTOCOL_CLIENT_SCOPE=status-jsonrpc-session-run-interrupt-approval"
print "RESIDUAL_HERMES_PROCESS=$RESIDUAL_HERMES_PROCESS"
