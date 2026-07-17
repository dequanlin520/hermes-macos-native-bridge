#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: Scripts/bootstrap-github.sh [--apply]

Bootstraps GitHub labels, milestones, and initial spike issues for this repo.

Default mode is dry-run. Use --apply to perform GitHub writes through the
authenticated gh account.
USAGE
}

mode="dry-run"

if [[ "$#" -gt 1 ]]; then
  usage >&2
  exit 2
fi

if [[ "$#" -eq 1 ]]; then
  case "$1" in
    --apply)
      mode="apply"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
fi

require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'error: required command not found: %s\n' "$command_name" >&2
    exit 1
  fi
}

run_write() {
  if [[ "$mode" == "apply" ]]; then
    "$@"
  else
    printf 'dry-run:'
    printf ' %q' "$@"
    printf '\n'
  fi
}

gh_read() {
  gh "$@"
}

label_exists() {
  local name="$1"

  gh_read api repos/:owner/:repo/labels \
    --method GET \
    --paginate \
    --field per_page=100 |
    jq -e -s --arg name "$name" 'any(.[][].name; . == $name)' >/dev/null
}

milestone_number() {
  local title="$1"

  gh_read api repos/:owner/:repo/milestones \
    --method GET \
    --paginate \
    --field state=all \
    --field per_page=100 |
    jq -r -s --arg title "$title" 'first(.[][] | select(.title == $title) | .number) // empty'
}

issue_exists() {
  local title="$1"

  gh_read api repos/:owner/:repo/issues \
    --method GET \
    --paginate \
    --field state=all \
    --field per_page=100 |
    jq -e -s --arg title "$title" 'any(.[][]; (has("pull_request") | not) and .title == $title)' >/dev/null
}

ensure_label() {
  local name="$1"
  local color="$2"
  local description="$3"

  if label_exists "$name"; then
    printf 'exists: label %s\n' "$name"
    return
  fi

  run_write gh label create "$name" --color "$color" --description "$description"
}

ensure_milestone() {
  local title="$1"
  local description="$2"

  if [[ -n "$(milestone_number "$title")" ]]; then
    printf 'exists: milestone %s\n' "$title"
    return
  fi

  run_write gh api repos/:owner/:repo/milestones \
    --method POST \
    --field "title=$title" \
    --field "description=$description"
}

ensure_issue() {
  local title="$1"
  local body="$2"
  local milestone="$3"
  local labels="$4"
  local milestone_id

  if issue_exists "$title"; then
    printf 'exists: issue %s\n' "$title"
    return
  fi

  milestone_id="$(milestone_number "$milestone")"
  if [[ -z "$milestone_id" ]]; then
    if [[ "$mode" == "apply" ]]; then
      printf 'error: milestone not found for issue "%s": %s\n' "$title" "$milestone" >&2
      exit 1
    fi
    printf 'dry-run: milestone lookup deferred for issue %s: %s\n' "$title" "$milestone"
  fi

  if [[ "$mode" == "apply" ]]; then
    gh issue create \
      --title "$title" \
      --body "$body" \
      --milestone "$milestone" \
      --label "$labels"
  else
    printf 'dry-run: gh issue create --title %q --body %q --milestone %q --label %q\n' "$title" "$body" "$milestone" "$labels"
  fi
}

require_command gh
require_command jq

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  printf 'error: this script must be run inside a git repository\n' >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if ! gh auth status >/dev/null 2>&1; then
  printf 'error: gh is not authenticated. Run "gh auth login" before using --apply or dry-run checks.\n' >&2
  exit 1
fi

if ! gh repo view --json nameWithOwner --jq '.nameWithOwner' >/dev/null 2>&1; then
  printf 'error: gh cannot resolve the current repository\n' >&2
  exit 1
fi

printf 'mode: %s\n' "$mode"
printf 'repository: %s\n' "$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"

ensure_label "type: spike" "5319E7" "Time-boxed technical validation work."
ensure_label "type: feature" "0E8A16" "Scoped feature work."
ensure_label "type: bug" "D73A4A" "Defect in documented behavior."
ensure_label "type: security" "B60205" "Security hardening or vulnerability-related work."
ensure_label "type: adr" "1D76DB" "Architecture decision record work."
ensure_label "type: governance" "6F42C1" "Repository governance and process work."

ensure_label "area: governance" "C5DEF5" "Repository policy, workflow, and project hygiene."
ensure_label "area: lifecycle" "C5DEF5" "Hermes lifecycle management."
ensure_label "area: shortcuts" "C5DEF5" "Approved macOS Shortcuts ingress or egress."
ensure_label "area: events" "C5DEF5" "macOS system event ingestion."
ensure_label "area: permissions" "C5DEF5" "Permissions and environment diagnostics."
ensure_label "area: menu-bar" "C5DEF5" "Native menu bar controls."
ensure_label "area: audit" "C5DEF5" "Pause, stop, emergency stop, audit, and diagnostics."
ensure_label "area: architecture" "C5DEF5" "Architecture, topology, and contracts."

ensure_label "priority: low" "D4C5F9" "Low-priority work."
ensure_label "priority: medium" "BFD4F2" "Medium-priority work."
ensure_label "priority: high" "FBCA04" "High-priority work."

ensure_label "risk: low" "D4EDDA" "Low implementation or security risk."
ensure_label "risk: medium" "FFF3CD" "Moderate implementation or security risk."
ensure_label "risk: high" "F8D7DA" "High implementation or security risk."

ensure_milestone "M0 Project Foundation" "Repository governance, scope, and project hygiene."
ensure_milestone "M1 Technical Validation" "Technical spikes that validate the V0.1 architecture."

spike_body_template='## Validation question

Document the technical uncertainty and evidence required to resolve it.

## Scope

- Validate the named technical area.
- Document findings, risks, and follow-up recommendations.
- Do not implement product runtime functionality unless a follow-up issue explicitly authorizes it.

## Security boundary

Do not add arbitrary shell execution, arbitrary executable paths, general AppleScript/JXA execution, GUI computer use, browser automation, or unauthenticated remote control.

## Acceptance criteria

- Findings are documented.
- Security and implementation risks are identified.
- Follow-up issues or ADR needs are listed.'

ensure_issue "SPK-01 Validate managed Hermes Gateway" "$spike_body_template" "M1 Technical Validation" "type: spike,area: lifecycle,area: architecture,priority: high,risk: high"
ensure_issue "SPK-02 Validate LaunchAgent and XPC topology" "$spike_body_template" "M1 Technical Validation" "type: spike,area: architecture,priority: high,risk: high"
ensure_issue "SPK-03 Validate process-group cleanup" "$spike_body_template" "M1 Technical Validation" "type: spike,area: lifecycle,area: audit,priority: high,risk: medium"
ensure_issue "SPK-04 Validate Shortcuts execution from LaunchAgent" "$spike_body_template" "M1 Technical Validation" "type: spike,area: shortcuts,area: architecture,priority: high,risk: high"
ensure_issue "SPK-05 Validate file authorization and FSEvents" "$spike_body_template" "M1 Technical Validation" "type: spike,area: events,area: permissions,priority: high,risk: high"
ensure_issue "SPK-06 Validate long-running App Intents" "$spike_body_template" "M1 Technical Validation" "type: spike,area: shortcuts,area: lifecycle,priority: high,risk: medium"
