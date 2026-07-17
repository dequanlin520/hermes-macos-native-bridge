#!/bin/zsh
set -u
set -o pipefail

SCRIPT_NAME="${0:t}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ARTIFACT_ROOT="$REPO_ROOT/artifacts/spk-03"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
RUN_DIR="$ARTIFACT_ROOT/$RUN_ID"
HELPER_C="$RUN_DIR/spk03_tree.c"
HELPER_BIN="$RUN_DIR/spk03_tree"
MARKER="SPK03_MARKER_${RUN_ID}"

typeset -a VERIFIED_PIDS
typeset -a VERIFIED_PGIDS
TREE_PARENT=""
TREE_CHILD=""
TREE_GRANDCHILD=""

ACTIVE_RESULT="FAIL"
PARENT_ONLY_LEAVES_DESCENDANTS="unknown"
PROCESS_GROUP_TERM_CLEAN="no"
PROCESS_GROUP_KILL_ESCALATION_CLEAN="no"
ESCAPED_DESCENDANT_OBSERVED="no"
IDENTITY_VERIFICATION_AVAILABLE="no"
SELECTED_OWNERSHIP_MODEL="undetermined"

usage() {
  print "Usage: $SCRIPT_NAME [--active-test]"
}

log() {
  print -- "$*"
}

die() {
  print -u2 -- "ERROR: $*"
  exit 1
}

ensure_artifacts() {
  mkdir -p "$RUN_DIR" || die "cannot create artifact directory"
}

run_read_only() {
  ensure_artifacts
  {
    print "SPK-03 read-only inspection"
    print "run_id=$RUN_ID"
    print "uname=$(uname -a)"
    print "sw_vers:"
    sw_vers 2>/dev/null || true
    print "architecture=$(uname -m)"
    print "shell_pid=$$"
    ps -o pid= -o ppid= -o pgid= -o sess= -o lstart= -o command= -p $$ 2>/dev/null || true
    print "tool_availability:"
    for tool in ps kill swiftc clang python3 python; do
      if command -v "$tool" >/dev/null 2>&1; then
        print "  $tool=$(command -v "$tool")"
      else
        print "  $tool=missing"
      fi
    done
    print "process_group_api_headers:"
    for symbol in setpgid setsid posix_spawn waitpid kill signal; do
      if xcrun --show-sdk-path >/dev/null 2>&1; then
        print "  $symbol=available-via-macOS-SDK"
      else
        print "  $symbol=availability-not-checked"
      fi
    done
    print "local_manpage_probe:"
    for topic in "kill 2" "setpgid 2" "setsid 2" "posix_spawn 3" "waitpid 2" "signal 3"; do
      if man $=topic >/dev/null 2>&1; then
        print "  $topic=available"
      else
        print "  $topic=not-found"
      fi
    done
    print "read_only_result=PASS"
  } | tee "$RUN_DIR/read-only-inspection.txt"
}

write_helper() {
  cat > "$HELPER_C" <<'EOF'
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static const char *artifact_dir;
static const char *scenario;
static const char *marker;

static void write_identity(const char *role) {
  char path[1024];
  snprintf(path, sizeof(path), "%s/%s-%s.pid", artifact_dir, scenario, role);
  FILE *pid_file = fopen(path, "w");
  if (pid_file == NULL) {
    _exit(80);
  }
  fprintf(pid_file, "%ld\n", (long)getpid());
  fclose(pid_file);

  snprintf(path, sizeof(path), "%s/%s-%s.meta", artifact_dir, scenario, role);
  FILE *meta_file = fopen(path, "w");
  if (meta_file == NULL) {
    _exit(81);
  }
  fprintf(meta_file, "marker=%s\n", marker);
  fprintf(meta_file, "scenario=%s\n", scenario);
  fprintf(meta_file, "role=%s\n", role);
  fprintf(meta_file, "pid=%ld\n", (long)getpid());
  fprintf(meta_file, "ppid=%ld\n", (long)getppid());
  fprintf(meta_file, "pgid=%ld\n", (long)getpgrp());
  fprintf(meta_file, "sid=%ld\n", (long)getsid(0));
  fclose(meta_file);
}

static void wait_forever(void) {
  for (;;) {
    pause();
  }
}

static void ignore_term(int signo) {
  (void)signo;
}

static void default_signal(int signo) {
  struct sigaction action;
  memset(&action, 0, sizeof(action));
  action.sa_handler = SIG_DFL;
  sigemptyset(&action.sa_mask);
  sigaction(signo, &action, NULL);
}

int main(int argc, char **argv) {
  if (argc != 7) {
    fprintf(stderr, "usage: %s <artifact-dir> <scenario> <marker> <new-pgrp> <child-ignore-term> <child-escape-session>\n", argv[0]);
    return 64;
  }

  artifact_dir = argv[1];
  scenario = argv[2];
  marker = argv[3];
  int new_pgrp = atoi(argv[4]);
  int child_ignore_term = atoi(argv[5]);
  int child_escape_session = atoi(argv[6]);

  default_signal(SIGTERM);
  default_signal(SIGINT);
  default_signal(SIGHUP);

  if (new_pgrp && setpgid(0, 0) != 0) {
    perror("setpgid");
    return 70;
  }

  write_identity("parent");

  pid_t child = fork();
  if (child < 0) {
    perror("fork child");
    return 71;
  }

  if (child == 0) {
    if (child_escape_session) {
      if (setsid() < 0) {
        perror("setsid");
        _exit(72);
      }
    }
    if (child_ignore_term) {
      struct sigaction action;
      memset(&action, 0, sizeof(action));
      action.sa_handler = ignore_term;
      sigemptyset(&action.sa_mask);
      if (sigaction(SIGTERM, &action, NULL) != 0) {
        _exit(73);
      }
    }

    write_identity("child");

    pid_t grandchild = fork();
    if (grandchild < 0) {
      _exit(74);
    }
    if (grandchild == 0) {
      if (child_ignore_term) {
        struct sigaction action;
        memset(&action, 0, sizeof(action));
        action.sa_handler = ignore_term;
        sigemptyset(&action.sa_mask);
        if (sigaction(SIGTERM, &action, NULL) != 0) {
          _exit(75);
        }
      }
      write_identity("grandchild");
      wait_forever();
    }

    wait_forever();
  }

  wait_forever();
  return 0;
}
EOF
  clang -Wall -Wextra -O2 -o "$HELPER_BIN" "$HELPER_C" || die "failed to compile helper"
}

pid_alive() {
  local pid="$1"
  local stat
  stat="$(ps -o stat= -p "$pid" 2>/dev/null | awk '{print $1}')" || return 1
  [[ -n "$stat" && "$stat" != Z* ]]
}

read_pid() {
  local scenario="$1"
  local role="$2"
  local file="$RUN_DIR/$scenario-$role.pid"
  [[ -f "$file" ]] || return 1
  tr -d '[:space:]' < "$file"
}

wait_for_tree() {
  local scenario="$1"
  local deadline=$((SECONDS + 5))
  while (( SECONDS < deadline )); do
    if [[ -s "$RUN_DIR/$scenario-parent.pid" && -s "$RUN_DIR/$scenario-child.pid" && -s "$RUN_DIR/$scenario-grandchild.pid" ]]; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

ps_identity_line() {
  local pid="$1"
  ps -o pid= -o ppid= -o pgid= -o sess= -o lstart= -o command= -p "$pid" 2>/dev/null
}

pid_command_has_marker() {
  local pid="$1"
  local line
  line="$(ps_identity_line "$pid")" || return 1
  [[ "$line" == *"$MARKER"* ]]
}

record_identity() {
  local scenario="$1"
  local role="$2"
  local pid
  pid="$(read_pid "$scenario" "$role")" || die "missing pid for $scenario $role"
  local line
  line="$(ps_identity_line "$pid")" || die "process $pid for $scenario $role is not alive"
  [[ "$line" == *"$MARKER"* ]] || die "process $pid for $scenario $role lacks marker"
  print "$role $line" >> "$RUN_DIR/$scenario-identities.txt"
}

pgid_for_pid() {
  local pid="$1"
  ps -o pgid= -p "$pid" 2>/dev/null | tr -d '[:space:]'
}

verify_pid_for_signal() {
  local pid="$1"
  if [[ -z "$pid" || "$pid" == *[!0-9]* ]]; then
    return 1
  fi
  pid_alive "$pid" || return 1
  pid_command_has_marker "$pid" || return 1
  return 0
}

remember_pid() {
  local pid="$1"
  verify_pid_for_signal "$pid" || die "refusing to remember unverified pid $pid"
  VERIFIED_PIDS+=("$pid")
}

verify_pgid_for_signal() {
  local pgid="$1"
  if [[ -z "$pgid" || "$pgid" == *[!0-9]* ]]; then
    return 1
  fi
  local rows
  rows="$(ps -axo pid=,pgid=,command= | awk -v pgid="$pgid" '$2 == pgid {print}')" || return 1
  [[ -n "$rows" ]] || return 1
  local bad
  bad="$(print -- "$rows" | awk -v marker="$MARKER" 'index($0, marker) == 0 {print}')" || return 1
  if [[ -n "$bad" ]]; then
    print -u2 -- "non-experiment process shares PGID $pgid:"
    print -u2 -- "$bad"
    return 1
  fi
  return 0
}

remember_pgid() {
  local pgid="$1"
  verify_pgid_for_signal "$pgid" || die "refusing to remember unverified pgid $pgid"
  VERIFIED_PGIDS+=("$pgid")
}

signal_pid() {
  local sig="$1"
  local pid="$2"
  verify_pid_for_signal "$pid" || die "refusing to signal unverified pid $pid"
  /bin/kill "-$sig" "$pid" || die "failed to signal pid $pid"
}

signal_pgid() {
  local sig="$1"
  local pgid="$2"
  verify_pgid_for_signal "$pgid" || die "refusing to signal unverified pgid $pgid"
  /bin/kill "-$sig" "-$pgid" || die "failed to signal pgid $pgid"
}

wait_gone_pid() {
  local pid="$1"
  local timeout="$2"
  local deadline=$((SECONDS + timeout))
  while (( SECONDS < deadline )); do
    pid_alive "$pid" || return 0
    sleep 0.1
  done
  pid_alive "$pid" && return 1
  return 0
}

marked_processes() {
  ps -axo pid=,ppid=,pgid=,sess=,command= | awk -v marker="$MARKER" -v helper="$HELPER_BIN" 'index($0, marker) != 0 && index($0, helper) != 0 {print}'
}

cleanup_verified() {
  local rows
  rows="$(marked_processes || true)"
  [[ -z "$rows" ]] && return 0

  local pgid
  for pgid in "${VERIFIED_PGIDS[@]}"; do
    if verify_pgid_for_signal "$pgid"; then
      /bin/kill -TERM "-$pgid" >/dev/null 2>&1 || true
    fi
  done
  sleep 0.5
  for pgid in "${VERIFIED_PGIDS[@]}"; do
    if verify_pgid_for_signal "$pgid"; then
      /bin/kill -KILL "-$pgid" >/dev/null 2>&1 || true
    fi
  done
  sleep 0.5
  local pid
  for pid in "${VERIFIED_PIDS[@]}"; do
    if verify_pid_for_signal "$pid"; then
      /bin/kill -TERM "$pid" >/dev/null 2>&1 || true
    fi
  done
  sleep 0.5
  for pid in "${VERIFIED_PIDS[@]}"; do
    if verify_pid_for_signal "$pid"; then
      /bin/kill -KILL "$pid" >/dev/null 2>&1 || true
    fi
  done
}

trap 'cleanup_verified' EXIT INT TERM

start_tree() {
  local scenario="$1"
  local new_pgrp="$2"
  local ignore_term="$3"
  local escape_session="$4"
  "$HELPER_BIN" "$RUN_DIR" "$scenario" "$MARKER" "$new_pgrp" "$ignore_term" "$escape_session" &
  local launched_pid=$!
  wait_for_tree "$scenario" || die "tree did not become ready for $scenario"
  local parent child grandchild
  parent="$(read_pid "$scenario" parent)"
  child="$(read_pid "$scenario" child)"
  grandchild="$(read_pid "$scenario" grandchild)"
  [[ "$parent" == "$launched_pid" ]] || die "$scenario parent pid mismatch: launched $launched_pid recorded $parent"
  record_identity "$scenario" parent
  record_identity "$scenario" child
  record_identity "$scenario" grandchild
  remember_pid "$parent"
  remember_pid "$child"
  remember_pid "$grandchild"
  TREE_PARENT="$parent"
  TREE_CHILD="$child"
  TREE_GRANDCHILD="$grandchild"
}

scenario_a() {
  log "Scenario A: parent PID only"
  local parent child grandchild
  start_tree "scenario-a" 0 0 0
  parent="$TREE_PARENT"
  child="$TREE_CHILD"
  grandchild="$TREE_GRANDCHILD"
  signal_pid TERM "$parent"
  wait_gone_pid "$parent" 3 || die "scenario A parent did not exit after SIGTERM"
  local child_alive="no"
  local grandchild_alive="no"
  pid_alive "$child" && child_alive="yes"
  pid_alive "$grandchild" && grandchild_alive="yes"
  print "child_alive_after_parent_term=$child_alive" >> "$RUN_DIR/scenario-a-result.txt"
  print "grandchild_alive_after_parent_term=$grandchild_alive" >> "$RUN_DIR/scenario-a-result.txt"
  if [[ "$child_alive" == "yes" || "$grandchild_alive" == "yes" ]]; then
    PARENT_ONLY_LEAVES_DESCENDANTS="yes"
  else
    PARENT_ONLY_LEAVES_DESCENDANTS="no"
  fi
  if [[ "$child_alive" == "yes" ]]; then
    signal_pid TERM "$child"
    wait_gone_pid "$child" 2 || signal_pid KILL "$child"
  fi
  if [[ "$grandchild_alive" == "yes" ]]; then
    signal_pid TERM "$grandchild"
    wait_gone_pid "$grandchild" 2 || signal_pid KILL "$grandchild"
  fi
  wait_gone_pid "$child" 3 || die "scenario A child remained after cleanup"
  wait_gone_pid "$grandchild" 3 || die "scenario A grandchild remained after cleanup"
}

scenario_b() {
  log "Scenario B: owned process group"
  local parent child grandchild pgid child_pgid grandchild_pgid
  start_tree "scenario-b" 1 0 0
  parent="$TREE_PARENT"
  child="$TREE_CHILD"
  grandchild="$TREE_GRANDCHILD"
  pgid="$(pgid_for_pid "$parent")"
  child_pgid="$(pgid_for_pid "$child")"
  grandchild_pgid="$(pgid_for_pid "$grandchild")"
  [[ "$pgid" == "$child_pgid" && "$pgid" == "$grandchild_pgid" ]] || die "scenario B PGID membership mismatch"
  remember_pgid "$pgid"
  print "owned_pgid=$pgid" >> "$RUN_DIR/scenario-b-result.txt"
  signal_pgid TERM "$pgid"
  wait_gone_pid "$parent" 3 || die "scenario B parent remained after group SIGTERM"
  wait_gone_pid "$child" 3 || die "scenario B child remained after group SIGTERM"
  wait_gone_pid "$grandchild" 3 || die "scenario B grandchild remained after group SIGTERM"
  PROCESS_GROUP_TERM_CLEAN="yes"
}

scenario_c() {
  log "Scenario C: SIGTERM-resistant child"
  local parent child grandchild pgid
  start_tree "scenario-c" 1 1 0
  parent="$TREE_PARENT"
  child="$TREE_CHILD"
  grandchild="$TREE_GRANDCHILD"
  pgid="$(pgid_for_pid "$parent")"
  [[ "$pgid" == "$(pgid_for_pid "$child")" && "$pgid" == "$(pgid_for_pid "$grandchild")" ]] || die "scenario C PGID membership mismatch"
  remember_pgid "$pgid"
  signal_pgid TERM "$pgid"
  sleep 1
  local after_term
  after_term="$(marked_processes || true)"
  print "after_sigterm:" >> "$RUN_DIR/scenario-c-result.txt"
  print -- "$after_term" >> "$RUN_DIR/scenario-c-result.txt"
  signal_pgid KILL "$pgid"
  wait_gone_pid "$parent" 3 || true
  wait_gone_pid "$child" 3 || die "scenario C child remained after group SIGKILL"
  wait_gone_pid "$grandchild" 3 || die "scenario C grandchild remained after group SIGKILL"
  PROCESS_GROUP_KILL_ESCALATION_CLEAN="yes"
}

scenario_d() {
  log "Scenario D: escaped descendant"
  local parent child grandchild parent_pgid child_pgid grandchild_pgid
  start_tree "scenario-d" 1 0 1
  parent="$TREE_PARENT"
  child="$TREE_CHILD"
  grandchild="$TREE_GRANDCHILD"
  parent_pgid="$(pgid_for_pid "$parent")"
  child_pgid="$(pgid_for_pid "$child")"
  grandchild_pgid="$(pgid_for_pid "$grandchild")"
  remember_pgid "$parent_pgid"
  print "parent_pgid=$parent_pgid" >> "$RUN_DIR/scenario-d-result.txt"
  print "child_pgid=$child_pgid" >> "$RUN_DIR/scenario-d-result.txt"
  print "grandchild_pgid=$grandchild_pgid" >> "$RUN_DIR/scenario-d-result.txt"
  signal_pgid TERM "$parent_pgid"
  wait_gone_pid "$parent" 3 || die "scenario D parent remained after original group SIGTERM"
  local child_alive="no"
  local grandchild_alive="no"
  pid_alive "$child" && child_alive="yes"
  pid_alive "$grandchild" && grandchild_alive="yes"
  print "child_alive_after_original_group_term=$child_alive" >> "$RUN_DIR/scenario-d-result.txt"
  print "grandchild_alive_after_original_group_term=$grandchild_alive" >> "$RUN_DIR/scenario-d-result.txt"
  if [[ "$child_alive" == "yes" || "$grandchild_alive" == "yes" ]]; then
    ESCAPED_DESCENDANT_OBSERVED="yes"
  fi
  if [[ "$child_alive" == "yes" ]]; then
    signal_pid TERM "$child"
  fi
  if [[ "$grandchild_alive" == "yes" ]]; then
    signal_pid TERM "$grandchild"
  fi
  wait_gone_pid "$child" 3 || signal_pid KILL "$child"
  wait_gone_pid "$grandchild" 3 || signal_pid KILL "$grandchild"
  wait_gone_pid "$child" 3 || die "scenario D child remained after PID cleanup"
  wait_gone_pid "$grandchild" 3 || die "scenario D grandchild remained after PID cleanup"
}

run_active() {
  ensure_artifacts
  write_helper
  IDENTITY_VERIFICATION_AVAILABLE="yes"
  {
    print "SPK-03 active test"
    print "run_id=$RUN_ID"
    print "marker=$MARKER"
    print "artifact_dir=artifacts/spk-03/$RUN_ID"
  } | tee "$RUN_DIR/active-summary.txt"

  scenario_a
  scenario_b
  scenario_c
  scenario_d

  local residual
  residual="$(marked_processes || true)"
  print "residual_marked_processes:" > "$RUN_DIR/residual-check.txt"
  print -- "$residual" >> "$RUN_DIR/residual-check.txt"
  [[ -z "$residual" ]] || die "marked process remains after active test"

  if [[ "$PROCESS_GROUP_TERM_CLEAN" == "yes" && "$PROCESS_GROUP_KILL_ESCALATION_CLEAN" == "yes" && "$IDENTITY_VERIFICATION_AVAILABLE" == "yes" ]]; then
    ACTIVE_RESULT="PASS"
    SELECTED_OWNERSHIP_MODEL="dedicated-process-group-with-pid-pgid-launch-identity-term-then-kill-and-escaped-descendant-detection"
  else
    ACTIVE_RESULT="FAIL"
  fi

  {
    print "SPK03_ACTIVE_RESULT=$ACTIVE_RESULT"
    print "PARENT_ONLY_LEAVES_DESCENDANTS=$PARENT_ONLY_LEAVES_DESCENDANTS"
    print "PROCESS_GROUP_TERM_CLEAN=$PROCESS_GROUP_TERM_CLEAN"
    print "PROCESS_GROUP_KILL_ESCALATION_CLEAN=$PROCESS_GROUP_KILL_ESCALATION_CLEAN"
    print "ESCAPED_DESCENDANT_OBSERVED=$ESCAPED_DESCENDANT_OBSERVED"
    print "IDENTITY_VERIFICATION_AVAILABLE=$IDENTITY_VERIFICATION_AVAILABLE"
    print "SPK03_SELECTED_OWNERSHIP_MODEL=$SELECTED_OWNERSHIP_MODEL"
  } | tee "$RUN_DIR/machine-result.env"
}

main() {
  if (( $# == 0 )); then
    run_read_only
    return
  fi

  case "$1" in
    --active-test)
      run_active
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      return 64
      ;;
  esac
}

main "$@"
