#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
ACCEPTANCE_SCRIPT="${HERMES_M14_002_ACCEPTANCE_SCRIPT:-$ROOT_DIR/Scripts/m14_002_real_user_install_acceptance.sh}"
PS_BIN="${HERMES_M14_002_PS:-/bin/ps}"
KILL_BIN="${HERMES_M14_002_KILL:-/bin/kill}"
ID_BIN="${HERMES_M14_002_ID:-/usr/bin/id}"
CURRENT_UID="${HERMES_M14_002_CURRENT_UID:-$($ID_BIN -u)}"

typeset -a RECORDED_PIDS
typeset -a PROCESS_ROWS
ROOT_PID=""
ROOT_PGID=""
RESUMED="no"
PARSED_PID=""
PARSED_PPID=""
PARSED_PGID=""
PARSED_UID=""
PARSED_COMM=""

fail() {
  print -u2 -- "error: $*"
  exit 1
}

usage() {
  print -u2 -- "usage: Scripts/m14_002_quiesce_real_hermes.zsh <root-hermes-pid>"
}

parse_process_row() {
  local line="$1"
  local fields
  fields=("${(@z)line}")
  (( ${#fields[@]} >= 5 )) || return 1
  PARSED_PID="${fields[1]}"
  PARSED_PPID="${fields[2]}"
  PARSED_PGID="${fields[3]}"
  PARSED_UID="${fields[4]}"
  PARSED_COMM="${(j: :)fields[5,-1]}"
}

process_row_for_pid() {
  local pid="$1"
  "$PS_BIN" -o pid= -o ppid= -o pgid= -o uid= -o comm= -p "$pid" 2>/dev/null | sed '/^[[:space:]]*$/d' | head -n 1
}

enumerate_process_group() {
  local pgid="$1"
  "$PS_BIN" -axo pid=,ppid=,pgid=,uid=,comm= 2>/dev/null | while IFS= read -r line; do
    parse_process_row "$line" || continue
    [[ "$PARSED_PGID" == "$pgid" ]] || continue
    print -r -- "$PARSED_PID	$PARSED_PPID	$PARSED_PGID	$PARSED_UID	$PARSED_COMM"
  done
}

load_process_group() {
  local root_line
  root_line="$(process_row_for_pid "$ROOT_PID")"
  [[ -n "$root_line" ]] || fail "supplied root process exited before suspension"
  parse_process_row "$root_line" || fail "could not parse root process identity"
  [[ "$PARSED_PID" == "$ROOT_PID" ]] || fail "root process identity mismatch"
  [[ "$PARSED_UID" == "$CURRENT_UID" ]] || fail "root process is not owned by the current user"
  ROOT_PGID="$PARSED_PGID"

  PROCESS_ROWS=("${(@f)$(enumerate_process_group "$ROOT_PGID")}")
  (( ${#PROCESS_ROWS[@]} > 0 )) || fail "no process-group members found"

  RECORDED_PIDS=()
  local saw_root="no"
  for line in "${PROCESS_ROWS[@]}"; do
    parse_process_row "$line" || fail "could not parse process-group member"
    [[ "$PARSED_PGID" == "$ROOT_PGID" ]] || fail "process-group enumeration escaped exact PGID"
    [[ "$PARSED_UID" == "$CURRENT_UID" ]] || fail "process-group member $PARSED_PID is not owned by the current user"
    [[ "$PARSED_PID" == "$ROOT_PID" ]] && saw_root="yes"
    RECORDED_PIDS+=("$PARSED_PID")
  done
  [[ "$saw_root" == "yes" ]] || fail "supplied root process exited before suspension"
}

display_process_group() {
  print -r -- "PID	PPID	PGID	EXECUTABLE"
  local line
  for line in "${PROCESS_ROWS[@]}"; do
    parse_process_row "$line" || continue
    print -r -- "$PARSED_PID	$PARSED_PPID	$PARSED_PGID	${PARSED_COMM:t}"
  done
}

resume_recorded_pids() {
  [[ "$RESUMED" == "no" ]] || return 0
  RESUMED="yes"
  local pid
  for pid in "${RECORDED_PIDS[@]}"; do
    "$KILL_BIN" -CONT "$pid" >/dev/null 2>&1 || true
  done
}

signal_exit() {
  local code="$1"
  resume_recorded_pids
  exit "$code"
}

main() {
  (( $# == 1 )) || { usage; exit 1; }
  ROOT_PID="$1"
  [[ "$ROOT_PID" == <-> ]] || fail "root Hermes PID must be numeric"

  load_process_group
  display_process_group

  [[ "${HERMES_QUIESCE_REAL_AGENT:-}" == "YES" ]] \
    || fail "set HERMES_QUIESCE_REAL_AGENT=YES to suspend the recorded process-group members"

  [[ -n "$(process_row_for_pid "$ROOT_PID")" ]] \
    || fail "supplied root process exited before suspension"

  trap 'signal_exit 130' INT TERM HUP
  trap 'resume_recorded_pids' EXIT

  local pid
  for pid in "${RECORDED_PIDS[@]}"; do
    "$KILL_BIN" -STOP "$pid" || signal_exit 1
  done

  HERMES_REAL_USER_INSTALL_ACCEPTANCE=YES "$ACCEPTANCE_SCRIPT"
  local acceptance_status="$?"
  resume_recorded_pids
  trap - EXIT INT TERM HUP
  return "$acceptance_status"
}

main "$@"
