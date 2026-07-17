#!/usr/bin/env zsh
set -euo pipefail
unsetopt bg_nice 2>/dev/null || true

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h}"
ARTIFACT_DIR="${REPO_ROOT}/artifacts/spk-01"
TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
READ_ONLY_LOG="${ARTIFACT_DIR}/read-only-${TIMESTAMP}.log"
ACTIVE_LOG="${ARTIFACT_DIR}/active-${TIMESTAMP}.log"
SERVER_STDOUT_LOG="${ARTIFACT_DIR}/serve-${TIMESTAMP}.stdout.log"
SERVER_STDERR_LOG="${ARTIFACT_DIR}/serve-${TIMESTAMP}.stderr.log"

ACTIVE_TEST=0
ABNORMAL_TEST=0
PORT=19119
HOST="127.0.0.1"
HERMES_PID=""
HERMES_BIN=""

ACTIVE_ROOT="${ARTIFACT_DIR}/active-root"
ACTIVE_HOME="${ACTIVE_ROOT}/home"
ACTIVE_HERMES_HOME="${ACTIVE_ROOT}/hermes-home"
ACTIVE_XDG_CONFIG_HOME="${ACTIVE_ROOT}/xdg-config"
ACTIVE_XDG_CACHE_HOME="${ACTIVE_ROOT}/xdg-cache"
ACTIVE_XDG_DATA_HOME="${ACTIVE_ROOT}/xdg-data"
ACTIVE_XDG_STATE_HOME="${ACTIVE_ROOT}/xdg-state"
ACTIVE_XDG_RUNTIME_DIR="${ACTIVE_ROOT}/xdg-runtime"
HERMES_START_TIME=""
HERMES_COMMAND=""

usage() {
  cat <<'USAGE'
Usage: Scripts/spikes/spk-01-managed-gateway.zsh [--active-test] [--abnormal-test]

Default mode is read-only. It inspects only the Hermes binary path, version,
top-level help, and relevant subcommand help.

Options:
  --active-test     Start a temporary Hermes server child process for
                    evidence-first observation. This may create files only
                    under artifacts/spk-01/.
  --abnormal-test   With --active-test, terminate the exact spike-owned child
                    with SIGKILL after protocol-neutral probes.
  -h, --help        Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --active-test)
      ACTIVE_TEST=1
      shift
      ;;
    --abnormal-test)
      ABNORMAL_TEST=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$ABNORMAL_TEST" -eq 1 && "$ACTIVE_TEST" -ne 1 ]]; then
  echo "error: --abnormal-test is valid only with --active-test" >&2
  exit 2
fi

mkdir -p "${ARTIFACT_DIR}"

redact() {
  sed -E \
    -e 's/((^|[[:space:]])[-_[:alnum:]]*([Kk][Ee][Yy]|[Tt][Oo][Kk][Ee][Nn]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Aa][Pp][Ii][_-]?[Kk][Ee][Yy])[-_[:alnum:]]*=)[^[:space:]&;,)]+/\1<redacted>/g' \
    -e 's/((^|[[:space:]])[-_[:alnum:]]*([Kk][Ee][Yy]|[Tt][Oo][Kk][Ee][Nn]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Aa][Pp][Ii][_-]?[Kk][Ee][Yy])[-_[:alnum:]]*:[[:space:]]*)[^[:space:],;)]+/\1<redacted>/g' \
    -e 's/(["'\''][-_[:alnum:]]*([Kk][Ee][Yy]|[Tt][Oo][Kk][Ee][Nn]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Aa][Pp][Ii][_-]?[Kk][Ee][Yy])[-_[:alnum:]]*["'\''][[:space:]]*:[[:space:]]*["'\''])[^"'\'']+(["'\''])/\1<redacted>\3/g' \
    -e 's/([Aa]uthorization:[[:space:]]*[Bb]earer[[:space:]]+)[^[:space:]]+/\1<redacted>/g' \
    -e 's/([Aa]uthorization:[[:space:]]*[Bb]asic[[:space:]]+)[^[:space:]]+/\1<redacted>/g' \
    -e 's/([Cc]ookie:[[:space:]]*)[^[:cntrl:]]+/\1<redacted>/g' \
    -e 's/([Ss]et-[Cc]ookie:[[:space:]]*)[^[:cntrl:]]+/\1<redacted>/g' \
    -e 's/([Xx]-[Aa][Pp][Ii]-[Kk][Ee][Yy]:[[:space:]]*)[^[:space:]]+/\1<redacted>/g' \
    -e 's/([?&]([-_[:alnum:]]*([Kk][Ee][Yy]|[Tt][Oo][Kk][Ee][Nn]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Aa][Pp][Ii][_-]?[Kk][Ee][Yy])[-_[:alnum:]]*)=)[^&[:space:]]+/\1<redacted>/g' \
    -e 's/(--[-_[:alnum:]]*([Kk][Ee][Yy]|[Tt][Oo][Kk][Ee][Nn]|[Ss][Ee][Cc][Rr][Ee][Tt])[-_[:alnum:]]*[=[:space:]]+)[^[:space:]]+/\1<redacted>/g'
}

log_line() {
  local target="$1"
  shift
  print -r -- "$*"
  print -r -- "$*" >> "$target"
}

append_stream() {
  local target="$1"
  while IFS= read -r line; do
    print -r -- "$line"
    print -r -- "$line" >> "$target"
  done
}

run_capture() {
  local target="$1"
  shift
  local rendered_command
  rendered_command="$(print -r -- "\$ $*" | redact)"
  log_line "$target" ""
  log_line "$target" "$rendered_command"
  {
    "$@" 2>&1 || true
  } | redact | append_stream "$target"
}

require_tool() {
  local target="$1"
  local tool="$2"
  local tool_path
  tool_path="$(command -v "$tool" || true)"
  if [[ -z "$tool_path" ]]; then
    log_line "$target" "prerequisite ${tool}=missing"
    echo "error: required tool not found on PATH: ${tool}" >&2
    exit 1
  fi
  log_line "$target" "prerequisite ${tool}=${tool_path}"
}

is_port_open() {
  nc -z "$HOST" "$PORT" >/dev/null 2>&1
}

record_tree() {
  local target="$1"
  local root="$2"
  local label="$3"
  log_line "$target" ""
  log_line "$target" "${label}: ${root}"
  if [[ ! -e "$root" ]]; then
    log_line "$target" "tree_absent=${root}"
    return
  fi
  run_capture "$target" find "$root" -exec stat -f 'path=%N type=%HT size=%z mtime=%Sm ctime=%Sc' -t '%Y-%m-%dT%H:%M:%SZ' {} \;
}

record_ps_metadata() {
  local target="$1"
  local pid="$2"
  if kill -0 "$pid" >/dev/null 2>&1; then
    run_capture "$target" ps -o pid,ppid,pgid,stat,lstart,command -p "$pid"
  else
    log_line "$target" "ps: pid ${pid} is not running"
  fi
}

record_descendants() {
  local target="$1"
  local pid="$2"
  log_line "$target" ""
  log_line "$target" "descendants for pid ${pid}:"
  ps -axo pid=,ppid=,pgid=,stat=,command= | awk -v root="$pid" '
    {
      pid=$1
      ppid=$2
      parent[pid]=ppid
      line[pid]=$0
    }
    END {
      found=0
      for (pid in parent) {
        current=parent[pid]
        while (current != "" && current != "0") {
          if (current == root) {
            print line[pid]
            found=1
            break
          }
          current=parent[current]
        }
      }
      if (found == 0) {
        print "none"
      }
    }
  ' | redact | append_stream "$target"
}

record_listener() {
  local target="$1"
  run_capture "$target" lsof -nP "-iTCP@${HOST}:${PORT}" -sTCP:LISTEN
}

record_active_root_processes() {
  local target="$1"
  log_line "$target" ""
  log_line "$target" "processes referencing active root ${ACTIVE_ROOT}:"
  ps -axo pid=,ppid=,pgid=,stat=,command= | awk -v root="$ACTIVE_ROOT" '
    index($0, root) > 0 {
      print
      found=1
    }
    END {
      if (found != 1) {
        print "none"
      }
    }
  ' | redact | append_stream "$target"
}

process_start_time() {
  local pid="$1"
  ps -o lstart= -p "$pid" 2>/dev/null | awk '{$1=$1; print}'
}

process_command() {
  local pid="$1"
  ps -o command= -p "$pid" 2>/dev/null | awk '{$1=$1; print}'
}

capture_child_identity() {
  local target="$1"
  if [[ -z "${HERMES_PID}" ]] || ! kill -0 "${HERMES_PID}" >/dev/null 2>&1; then
    log_line "$target" "identity: child pid is not running"
    return 1
  fi

  HERMES_START_TIME="$(process_start_time "$HERMES_PID")"
  HERMES_COMMAND="$(process_command "$HERMES_PID")"
  log_line "$target" "identity_pid=${HERMES_PID}"
  log_line "$target" "identity_start_time=${HERMES_START_TIME}"
  log_line "$target" "identity_command=$(print -r -- "$HERMES_COMMAND" | redact)"

  if [[ -z "$HERMES_START_TIME" || -z "$HERMES_COMMAND" ]]; then
    log_line "$target" "identity: unable to capture launch identity"
    return 1
  fi
}

verify_child_identity() {
  local target="$1"
  local label="$2"
  local current_start_time
  local current_command

  if [[ -z "${HERMES_PID}" ]]; then
    log_line "$target" "${label}: no child pid recorded"
    return 1
  fi
  if ! kill -0 "${HERMES_PID}" >/dev/null 2>&1; then
    log_line "$target" "${label}: pid ${HERMES_PID} is not running"
    return 1
  fi

  current_start_time="$(process_start_time "$HERMES_PID")"
  current_command="$(process_command "$HERMES_PID")"
  if [[ "$current_start_time" != "$HERMES_START_TIME" || "$current_command" != "$HERMES_COMMAND" ]]; then
    log_line "$target" "${label}: refusing to signal pid ${HERMES_PID}; identity mismatch"
    log_line "$target" "${label}: recorded_start_time=${HERMES_START_TIME}"
    log_line "$target" "${label}: current_start_time=${current_start_time}"
    log_line "$target" "${label}: recorded_command=$(print -r -- "$HERMES_COMMAND" | redact)"
    log_line "$target" "${label}: current_command=$(print -r -- "$current_command" | redact)"
    return 1
  fi

  return 0
}

capture_log_evidence() {
  local target="$1"
  local log="$2"
  local label="$3"
  log_line "$target" ""
  log_line "$target" "${label} evidence from ${log}:"
  if [[ ! -s "$log" ]]; then
    log_line "$target" "${label}: empty"
    return
  fi
  run_capture "$target" grep -E -i 'protocol|json-rpc|jsonrpc|websocket|ws://|wss://|auth|token|key|ready|readiness|api|schema|docs|documentation|openapi|swagger' "$log"
}

shutdown_child() {
  local target="$1"
  local signal="$2"
  local label="$3"

  if [[ -z "${HERMES_PID}" ]]; then
    return
  fi
  if ! kill -0 "${HERMES_PID}" >/dev/null 2>&1; then
    log_line "$target" "${label}: pid ${HERMES_PID} already exited"
    HERMES_PID=""
    return
  fi
  if ! verify_child_identity "$target" "$label"; then
    log_line "$target" "${label}: cleanup refused because pid identity was not verified"
    return 1
  fi

  log_line "$target" "${label}: sending ${signal} to exact spike-owned pid ${HERMES_PID}"
  if ! kill "-${signal}" "${HERMES_PID}" >/dev/null 2>&1; then
    log_line "$target" "${label}: kill ${signal} failed for pid ${HERMES_PID}"
    return 1
  fi

  local waited=0
  while kill -0 "${HERMES_PID}" >/dev/null 2>&1 && [[ "$waited" -lt 40 ]]; do
    sleep 0.25
    waited=$((waited + 1))
  done

  if kill -0 "${HERMES_PID}" >/dev/null 2>&1; then
    log_line "$target" "${label}: pid ${HERMES_PID} still running after ${signal}"
    return 1
  else
    log_line "$target" "${label}: pid ${HERMES_PID} exited after ${signal}"
    HERMES_PID=""
    return 0
  fi
}

cleanup() {
  if [[ -n "${HERMES_PID}" ]] && kill -0 "${HERMES_PID}" >/dev/null 2>&1; then
    log_line "$ACTIVE_LOG" "cleanup: retrying shutdown for exact spike-owned pid ${HERMES_PID}"
    if ! shutdown_child "$ACTIVE_LOG" TERM cleanup; then
      if [[ -n "${HERMES_PID}" ]] && verify_child_identity "$ACTIVE_LOG" "cleanup SIGKILL"; then
        log_line "$ACTIVE_LOG" "cleanup: escalating to SIGKILL for verified spike-owned pid ${HERMES_PID}"
        shutdown_child "$ACTIVE_LOG" KILL "cleanup SIGKILL" || true
      fi
    fi
  fi
}
trap cleanup EXIT INT TERM

log_line "$READ_ONLY_LOG" "SPK-01 read-only Hermes inspection"
log_line "$READ_ONLY_LOG" "timestamp_utc=${TIMESTAMP}"
log_line "$READ_ONLY_LOG" "repo_root=${REPO_ROOT}"

for tool in hermes curl nc lsof ps find; do
  require_tool "$READ_ONLY_LOG" "$tool"
done

HERMES_BIN="$(command -v hermes || true)"
log_line "$READ_ONLY_LOG" "hermes_bin=${HERMES_BIN}"

run_capture "$READ_ONLY_LOG" ls -l "$HERMES_BIN"
if [[ -L "$HERMES_BIN" ]]; then
  run_capture "$READ_ONLY_LOG" readlink "$HERMES_BIN"
fi

run_capture "$READ_ONLY_LOG" "$HERMES_BIN" --version
run_capture "$READ_ONLY_LOG" "$HERMES_BIN" --help
run_capture "$READ_ONLY_LOG" "$HERMES_BIN" gateway --help
run_capture "$READ_ONLY_LOG" "$HERMES_BIN" gateway run --help
run_capture "$READ_ONLY_LOG" "$HERMES_BIN" gateway status --help
run_capture "$READ_ONLY_LOG" "$HERMES_BIN" serve --help
run_capture "$READ_ONLY_LOG" "$HERMES_BIN" dashboard --help
run_capture "$READ_ONLY_LOG" "$HERMES_BIN" profile --help
run_capture "$READ_ONLY_LOG" "$HERMES_BIN" profile list --help
run_capture "$READ_ONLY_LOG" "$HERMES_BIN" profile show --help
run_capture "$READ_ONLY_LOG" "$HERMES_BIN" profile use --help
run_capture "$READ_ONLY_LOG" "$HERMES_BIN" config --help
run_capture "$READ_ONLY_LOG" "$HERMES_BIN" auth --help
run_capture "$READ_ONLY_LOG" "$HERMES_BIN" sessions --help

log_line "$READ_ONLY_LOG" ""
log_line "$READ_ONLY_LOG" "read-only inspection complete"
log_line "$READ_ONLY_LOG" "log=${READ_ONLY_LOG}"

if [[ "$ACTIVE_TEST" -ne 1 ]]; then
  echo "Read-only inspection complete: ${READ_ONLY_LOG}"
  echo "Active tests were not run. Re-run with --active-test to start a spike-owned child process."
  exit 0
fi

log_line "$ACTIVE_LOG" "SPK-01 active Hermes serve evidence-first probe"
log_line "$ACTIVE_LOG" "timestamp_utc=${TIMESTAMP}"
log_line "$ACTIVE_LOG" "host=${HOST}"
log_line "$ACTIVE_LOG" "port=${PORT}"
log_line "$ACTIVE_LOG" "fixed_spike_port=${PORT}"
log_line "$ACTIVE_LOG" "stdout_log=${SERVER_STDOUT_LOG}"
log_line "$ACTIVE_LOG" "stderr_log=${SERVER_STDERR_LOG}"

for tool in hermes curl nc lsof ps find; do
  require_tool "$ACTIVE_LOG" "$tool"
done

if is_port_open; then
  log_line "$ACTIVE_LOG" "error: ${HOST}:${PORT} is already open; refusing to interfere with an external process"
  echo "Active test refused: ${HOST}:${PORT} is already in use. See ${ACTIVE_LOG}" >&2
  exit 1
fi

mkdir -p "$ACTIVE_HOME" "$ACTIVE_HERMES_HOME" "$ACTIVE_XDG_CONFIG_HOME" "$ACTIVE_XDG_CACHE_HOME" "$ACTIVE_XDG_DATA_HOME" "$ACTIVE_XDG_STATE_HOME" "$ACTIVE_XDG_RUNTIME_DIR"
chmod 700 "$ACTIVE_ROOT" "$ACTIVE_HOME" "$ACTIVE_HERMES_HOME" "$ACTIVE_XDG_CONFIG_HOME" "$ACTIVE_XDG_CACHE_HOME" "$ACTIVE_XDG_DATA_HOME" "$ACTIVE_XDG_STATE_HOME" "$ACTIVE_XDG_RUNTIME_DIR"

log_line "$ACTIVE_LOG" ""
log_line "$ACTIVE_LOG" "Stage A - process launch"
log_line "$ACTIVE_LOG" "HOME=${ACTIVE_HOME}"
log_line "$ACTIVE_LOG" "HERMES_HOME=${ACTIVE_HERMES_HOME}"
log_line "$ACTIVE_LOG" "XDG_CONFIG_HOME=${ACTIVE_XDG_CONFIG_HOME}"
log_line "$ACTIVE_LOG" "XDG_CACHE_HOME=${ACTIVE_XDG_CACHE_HOME}"
log_line "$ACTIVE_LOG" "XDG_DATA_HOME=${ACTIVE_XDG_DATA_HOME}"
log_line "$ACTIVE_LOG" "XDG_STATE_HOME=${ACTIVE_XDG_STATE_HOME}"
log_line "$ACTIVE_LOG" "XDG_RUNTIME_DIR=${ACTIVE_XDG_RUNTIME_DIR}"
record_tree "$ACTIVE_LOG" "$ACTIVE_ROOT" "filesystem before launch"

log_line "$ACTIVE_LOG" "command=env HOME=${ACTIVE_HOME} HERMES_HOME=${ACTIVE_HERMES_HOME} XDG_CONFIG_HOME=${ACTIVE_XDG_CONFIG_HOME} XDG_CACHE_HOME=${ACTIVE_XDG_CACHE_HOME} XDG_DATA_HOME=${ACTIVE_XDG_DATA_HOME} XDG_STATE_HOME=${ACTIVE_XDG_STATE_HOME} XDG_RUNTIME_DIR=${ACTIVE_XDG_RUNTIME_DIR} ${HERMES_BIN} --safe-mode serve --host ${HOST} --port ${PORT} --skip-build --isolated"
HERMES_PID="$(
env \
  "HOME=${ACTIVE_HOME}" \
  "HERMES_HOME=${ACTIVE_HERMES_HOME}" \
  "XDG_CONFIG_HOME=${ACTIVE_XDG_CONFIG_HOME}" \
  "XDG_CACHE_HOME=${ACTIVE_XDG_CACHE_HOME}" \
  "XDG_DATA_HOME=${ACTIVE_XDG_DATA_HOME}" \
  "XDG_STATE_HOME=${ACTIVE_XDG_STATE_HOME}" \
  "XDG_RUNTIME_DIR=${ACTIVE_XDG_RUNTIME_DIR}" \
  zsh -fc '
    stdout_log="$1"
    stderr_log="$2"
    shift 2
    unsetopt bg_nice 2>/dev/null || true
    "$@" >"$stdout_log" 2>"$stderr_log" &
    print -r -- $!
  ' spawn \
  "$SERVER_STDOUT_LOG" \
  "$SERVER_STDERR_LOG" \
  "$HERMES_BIN" --safe-mode serve --host "$HOST" --port "$PORT" --skip-build --isolated
)"
log_line "$ACTIVE_LOG" "pid=${HERMES_PID}"
capture_child_identity "$ACTIVE_LOG"

ready=0
for _ in {1..80}; do
  if ! kill -0 "$HERMES_PID" >/dev/null 2>&1; then
    log_line "$ACTIVE_LOG" "server exited before opening port"
    break
  fi
  if is_port_open; then
    ready=1
    break
  fi
  sleep 0.25
done

log_line "$ACTIVE_LOG" ""
log_line "$ACTIVE_LOG" "Stage B - runtime observation"
if kill -0 "$HERMES_PID" >/dev/null 2>&1; then
  log_line "$ACTIVE_LOG" "child_alive=yes"
else
  log_line "$ACTIVE_LOG" "child_alive=no"
fi
record_ps_metadata "$ACTIVE_LOG" "$HERMES_PID"
record_descendants "$ACTIVE_LOG" "$HERMES_PID"
record_listener "$ACTIVE_LOG"
record_active_root_processes "$ACTIVE_LOG"
capture_log_evidence "$ACTIVE_LOG" "$SERVER_STDOUT_LOG" stdout
capture_log_evidence "$ACTIVE_LOG" "$SERVER_STDERR_LOG" stderr

if [[ "$ready" -ne 1 ]]; then
  log_line "$ACTIVE_LOG" "server did not open ${HOST}:${PORT}"
  echo "Active test could not start server. See ${ACTIVE_LOG}" >&2
  exit 1
fi

log_line "$ACTIVE_LOG" ""
log_line "$ACTIVE_LOG" "Stage C - protocol-neutral probes"
run_capture "$ACTIVE_LOG" nc -z "$HOST" "$PORT"
run_capture "$ACTIVE_LOG" curl --silent --show-error --max-time 3 --include --request GET "http://${HOST}:${PORT}/"
log_line "$ACTIVE_LOG" ""
log_line "$ACTIVE_LOG" "\$ printf WebSocket upgrade handshake for / | nc -w 3 ${HOST} ${PORT}"
{
  printf 'GET / HTTP/1.1\r\n'
  printf 'Host: %s:%s\r\n' "$HOST" "$PORT"
  printf 'Upgrade: websocket\r\n'
  printf 'Connection: Upgrade\r\n'
  printf 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
  printf 'Sec-WebSocket-Version: 13\r\n'
  printf '\r\n'
} | nc -w 3 "$HOST" "$PORT" | redact | append_stream "$ACTIVE_LOG" || true

log_line "$ACTIVE_LOG" ""
log_line "$ACTIVE_LOG" "Stage D - filesystem evidence before shutdown"
record_tree "$ACTIVE_LOG" "$ACTIVE_ROOT" "filesystem after launch"

log_line "$ACTIVE_LOG" ""
log_line "$ACTIVE_LOG" "Stage E - shutdown"
if [[ "$ABNORMAL_TEST" -eq 1 ]]; then
  shutdown_child "$ACTIVE_LOG" KILL "abnormal shutdown" || {
    log_line "$ACTIVE_LOG" "abnormal shutdown failed; leaving cleanup trap armed"
    exit 1
  }
else
  shutdown_child "$ACTIVE_LOG" TERM "normal shutdown" || {
    log_line "$ACTIVE_LOG" "normal shutdown failed; leaving cleanup trap armed"
    exit 1
  }
fi

sleep 1
if [[ -n "${HERMES_PID}" ]]; then
  record_descendants "$ACTIVE_LOG" "$HERMES_PID"
fi
log_line "$ACTIVE_LOG" ""
log_line "$ACTIVE_LOG" "post-shutdown listener evidence:"
record_listener "$ACTIVE_LOG"
record_active_root_processes "$ACTIVE_LOG"
if is_port_open; then
  log_line "$ACTIVE_LOG" "port cleanup: ${HOST}:${PORT} still open after child exit"
  exit 1
else
  log_line "$ACTIVE_LOG" "port cleanup: ${HOST}:${PORT} closed after child exit"
fi
record_tree "$ACTIVE_LOG" "$ACTIVE_ROOT" "filesystem after shutdown"

echo "Active evidence-first probe complete: ${ACTIVE_LOG}"
