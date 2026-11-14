#!/usr/bin/env bash
set -Eeuo pipefail

# One-command launcher for Project's persistent Lead, Engineer, and Reviewer agents.
# Run from the repository root: ./start-project-agents.sh
# Always attaches to the visible Herdr TUI after preparing the agents.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Support being located either in the repository root or in .hermes/.
if [[ -d "$SCRIPT_DIR/.hermes/skills" ]]; then
  PROJECT_ROOT="$SCRIPT_DIR"
elif [[ -d "$SCRIPT_DIR/../.hermes/skills" ]]; then
  PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
else
  PROJECT_ROOT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "${PROJECT_ROOT:-}" && -d "$PROJECT_ROOT/.hermes/skills" ]] || {
  echo "ERROR: Place this script in the Project repository root or .hermes and run it there." >&2
  exit 2
}
PROJECT_ROOT="$(cd -- "$PROJECT_ROOT" && pwd)"

case "${1:-}" in
  "") ;;
  --help|-h)
    echo "Usage: $0"
    echo "Prepares the Project agents and always opens the visible Herdr TUI."
    exit 0
    ;;
  *) echo "Usage: $0" >&2; exit 2 ;;
esac

# This launcher is intentionally interactive. Never silently leave the agents
# running without attaching the visible Herdr terminal UI.
if [[ ! -t 0 || ! -t 1 ]]; then
  echo "ERROR: Run this script from an interactive terminal. The launcher always opens the visible Herdr TUI; it does not support headless mode." >&2
  exit 2
fi

RUNTIME_DIR="$PROJECT_ROOT/.hermes/runtime"
RUNTIME_FILE="$RUNTIME_DIR/herdr-agents.json"
mkdir -p "$RUNTIME_DIR"

log() { printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

for cmd in git hermes herdr; do require_cmd "$cmd"; done
if ! command -v jq >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    log "jq is required for Herdr's JSON responses; installing it with Homebrew"
    brew install jq
  else
    die "jq is required. Install it with 'brew install jq', then rerun this script."
  fi
fi

# Fail early rather than start agents with an incomplete project configuration.
REQUIRED_FILES=(
  "$PROJECT_ROOT/.hermes.md"
  "$PROJECT_ROOT/.hermes/skills/planner/SKILL.md"
  "$PROJECT_ROOT/.hermes/skills/executor/SKILL.md"
  "$PROJECT_ROOT/.hermes/skills/reviewer/SKILL.md"
  "$PROJECT_ROOT/.hermes/skills/delivery/SKILL.md"
  "$PROJECT_ROOT/.hermes/memories/PLANS.md"
  "$PROJECT_ROOT/.hermes/memories/PROGRESS.md"
)
for file in "${REQUIRED_FILES[@]}"; do
  [[ -s "$file" ]] || die "Required file is missing or empty: ${file#$PROJECT_ROOT/}"
done

# Keep the local Herdr IDs and flags out of implementation commits.
if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_DIR="$(git -C "$PROJECT_ROOT" rev-parse --git-dir)"
  [[ "$GIT_DIR" = /* ]] || GIT_DIR="$PROJECT_ROOT/$GIT_DIR"
  EXCLUDE_FILE="$GIT_DIR/info/exclude"
  mkdir -p "$(dirname "$EXCLUDE_FILE")"
  touch "$EXCLUDE_FILE"
  if ! grep -Fqx '.hermes/runtime/' "$EXCLUDE_FILE"; then
    printf '\n# Local Herdr runtime identifiers for Project agents\n.hermes/runtime/\n' >> "$EXCLUDE_FILE"
  fi
fi

ensure_profile() {
  local profile="$1" description="$2"
  if hermes profile show "$profile" >/dev/null 2>&1; then
    log "Using existing Hermes profile: $profile"
  else
    log "Creating Hermes profile: $profile"
    hermes profile create "$profile" --no-skills --description "$description"
  fi
  hermes -p "$profile" config set terminal.backend local >/dev/null
  hermes -p "$profile" config set terminal.cwd "$PROJECT_ROOT" >/dev/null
}

log "Preparing three isolated Hermes profiles"
ensure_profile thriae_lead "Project Lead, one-milestone planning and autonomous coordination"
ensure_profile thriae_engineer "Project Engineer, implementation, validation, progress tracking, commits and PR creation"
ensure_profile thriae_reviewer "Project independent Reviewer, documentation and engineering quality assessment"

log "Enabling Kanban toolset for all profiles"
for profile in thriae_lead thriae_engineer thriae_reviewer; do
  hermes -p "$profile" tools enable kanban --platform cli >/dev/null 2>&1 || true
done

log "Trusting the repository-local skills"
hermes skills trust "$PROJECT_ROOT"
for profile in thriae_lead thriae_engineer thriae_reviewer; do
  HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}/profiles/$profile" hermes skills trust "$PROJECT_ROOT" >/dev/null 2>&1 || true
done

# Herdr uses a background session server internally; the visible TUI is attached at the end.
if herdr status server >/dev/null 2>&1; then
  log "Herdr server is already running"
else
  log "Starting Herdr background session service (Herdr TUI will attach visibly after agent setup)"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    LOG_ROOT="$HOME/Library/Logs"
  else
    LOG_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/herdr"
  fi
  mkdir -p "$LOG_ROOT"
  SERVER_LOG="$LOG_ROOT/project-herdr-server.log"
  nohup herdr server >"$SERVER_LOG" 2>&1 < /dev/null &
  SERVER_PID=$!
  printf '%s\n' "$SERVER_PID" > "$RUNTIME_DIR/herdr-server.pid"

  READY=0
  for _ in $(seq 1 45); do
    if herdr status server >/dev/null 2>&1; then READY=1; break; fi
    if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then break; fi
    sleep 1
  done
  [[ "$READY" -eq 1 ]] || {
    echo "Herdr server failed to start. Log: $SERVER_LOG" >&2
    tail -n 80 "$SERVER_LOG" >&2 || true
    exit 1
  }
fi

# The Hermes integration is profile-scoped. Install it into each named profile,
# not only the default ~/.hermes home.
HERMES_BASE="${HERMES_HOME:-$HOME/.hermes}"
for profile in thriae_lead thriae_engineer thriae_reviewer; do
  PROFILE_HOME="$HERMES_BASE/profiles/$profile"
  [[ -d "$PROFILE_HOME" ]] || die "Hermes profile home not found: $PROFILE_HOME"
  PLUGIN_DIR="$PROFILE_HOME/plugins/herdr-agent-state"
  PROFILE_CONFIG="$PROFILE_HOME/config.yaml"
  OUTDATED_STATUS="$(HERMES_HOME="$PROFILE_HOME" herdr integration status --outdated-only 2>&1 || true)"
  if [[ ! -d "$PLUGIN_DIR" ]] || ! grep -q 'herdr-agent-state' "$PROFILE_CONFIG" 2>/dev/null; then
    log "Installing Herdr Hermes session integration for profile $profile"
    HERMES_HOME="$PROFILE_HOME" herdr integration install hermes
  elif printf '%s\n' "$OUTDATED_STATUS" | grep -qi 'hermes'; then
    log "Refreshing outdated Herdr Hermes integration for profile $profile"
    HERMES_HOME="$PROFILE_HOME" herdr integration install hermes
  else
    log "Herdr Hermes session integration is ready for profile $profile"
  fi
done

WORKSPACE_ID=""
LEAD_PANE=""
ENGINEER_PANE=""
REVIEWER_PANE=""
LEAD_INITIALIZED=false
ENGINEER_INITIALIZED=false
REVIEWER_INITIALIZED=false

if [[ -s "$RUNTIME_FILE" ]]; then
  jq -e 'type == "object"' "$RUNTIME_FILE" >/dev/null || die "Invalid runtime state JSON: $RUNTIME_FILE"
  WORKSPACE_ID="$(jq -r '.workspace_id // empty' "$RUNTIME_FILE")"
  LEAD_PANE="$(jq -r '.lead_pane_id // empty' "$RUNTIME_FILE")"
  ENGINEER_PANE="$(jq -r '.engineer_pane_id // empty' "$RUNTIME_FILE")"
  REVIEWER_PANE="$(jq -r '.reviewer_pane_id // empty' "$RUNTIME_FILE")"
  LEAD_INITIALIZED="$(jq -r '.lead_initialized // false' "$RUNTIME_FILE")"
  ENGINEER_INITIALIZED="$(jq -r '.engineer_initialized // false' "$RUNTIME_FILE")"
  REVIEWER_INITIALIZED="$(jq -r '.reviewer_initialized // false' "$RUNTIME_FILE")"
  if [[ -n "$WORKSPACE_ID" && -n "$LEAD_PANE" ]] && ! herdr pane get "$LEAD_PANE" >/dev/null 2>&1; then
    log "Saved Herdr workspace/pane is unavailable; recreating agents"
    WORKSPACE_ID=""
    LEAD_PANE=""
    ENGINEER_PANE=""
    REVIEWER_PANE=""
    LEAD_INITIALIZED=false
    ENGINEER_INITIALIZED=false
    REVIEWER_INITIALIZED=false
  fi
  if [[ -n "$ENGINEER_PANE" ]] && ! herdr pane get "$ENGINEER_PANE" >/dev/null 2>&1; then
    log "Saved Engineer pane is unavailable; recreating it"
    ENGINEER_PANE=""
    ENGINEER_INITIALIZED=false
  fi
  if [[ -n "$REVIEWER_PANE" ]] && ! herdr pane get "$REVIEWER_PANE" >/dev/null 2>&1; then
    log "Saved Reviewer pane is unavailable; recreating it"
    REVIEWER_PANE=""
    REVIEWER_INITIALIZED=false
  fi
else
  for agent in lead engineer reviewer; do
    if herdr agent get "$agent" >/dev/null 2>&1; then
      die "Agent '$agent' is already live but the runtime record is missing. Refusing to create duplicate agents. Inspect 'herdr agent list' and recover the runtime record first."
    fi
  done
fi

save_runtime() {
  local tmp="$RUNTIME_FILE.tmp"
  jq -n \
    --arg workspace_id "$WORKSPACE_ID" \
    --arg lead_pane_id "$LEAD_PANE" \
    --arg engineer_pane_id "$ENGINEER_PANE" \
    --arg reviewer_pane_id "$REVIEWER_PANE" \
    --argjson lead_initialized "$LEAD_INITIALIZED" \
    --argjson engineer_initialized "$ENGINEER_INITIALIZED" \
    --argjson reviewer_initialized "$REVIEWER_INITIALIZED" \
    '{workspace_id:$workspace_id,lead_pane_id:$lead_pane_id,engineer_pane_id:$engineer_pane_id,reviewer_pane_id:$reviewer_pane_id,lead_initialized:$lead_initialized,engineer_initialized:$engineer_initialized,reviewer_initialized:$reviewer_initialized}' \
    > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$RUNTIME_FILE"
}

wait_for_shell() {
  local pane="$1" name
  for _ in $(seq 1 10); do
    name="$(herdr pane process-info --pane "$pane" 2>/dev/null | jq -r '.result.process_info.foreground_processes[0].name // empty')"
    case "$name" in
      zsh|bash|sh|fish) return 0 ;;
    esac
    sleep 0.5
  done
  herdr pane wait-output "$pane" --match "%" --timeout 5000 >/dev/null 2>&1 || true
}

wait_for_hermes() {
  local pane="$1" name
  for _ in $(seq 1 20); do
    name="$(herdr pane process-info --pane "$pane" 2>/dev/null | jq -r '.result.process_info.foreground_processes[0].name // empty')"
    case "$name" in
      ""|zsh|bash|sh|fish) sleep 0.5 ;;
      *) return 0 ;;
    esac
  done
}

# Derive a per-project Kanban board slug from the project directory name.
BOARD_SLUG="$(printf '%s' "$(basename "$PROJECT_ROOT")" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/-\+/-/g; s/^-//; s/-$//')"
[[ -n "$BOARD_SLUG" ]] || BOARD_SLUG="project"
log "Ensuring Kanban board: $BOARD_SLUG"
hermes kanban boards create "$BOARD_SLUG" --name "$(basename "$PROJECT_ROOT")" >/dev/null 2>&1 || true
hermes kanban boards set-default-workdir "$BOARD_SLUG" "$PROJECT_ROOT" >/dev/null 2>&1 || true
export HERMES_KANBAN_HOME="$PROJECT_ROOT/.hermes"
export HERMES_KANBAN_BOARD="$BOARD_SLUG"

if [[ -z "$WORKSPACE_ID" ]]; then
  log "Creating the Project Agents workspace"
  CREATED="$(herdr workspace create --cwd "$PROJECT_ROOT" --label "Project Agents" --no-focus)"
  WORKSPACE_ID="$(printf '%s\n' "$CREATED" | jq -r '.result.workspace.workspace_id // empty')"
  LEAD_PANE="$(printf '%s\n' "$CREATED" | jq -r '.result.root_pane.pane_id // empty')"
  [[ -n "$WORKSPACE_ID" && -n "$LEAD_PANE" ]] || die "Could not parse Herdr workspace response: $CREATED"
  save_runtime
fi

if [[ -z "$ENGINEER_PANE" ]]; then
  log "Splitting an Engineer pane from the Lead pane"
  ENG_SPLIT_OUTPUT="$(herdr pane split --pane "$LEAD_PANE" --direction right --cwd "$PROJECT_ROOT" --no-focus)"
  ENGINEER_PANE="$(printf '%s\n' "$ENG_SPLIT_OUTPUT" | jq -r '.result.pane.pane_id // empty')"
  [[ -n "$ENGINEER_PANE" ]] || die "Could not split Engineer pane: $ENG_SPLIT_OUTPUT"
  sleep 1
  herdr pane run "$ENGINEER_PANE" env HERMES_KANBAN_HOME="$PROJECT_ROOT/.hermes" HERMES_KANBAN_BOARD="$BOARD_SLUG" hermes -p thriae_engineer chat --cli
  save_runtime
fi

if [[ -z "$REVIEWER_PANE" ]]; then
  log "Splitting a Reviewer pane from the Engineer pane"
  REV_SPLIT_OUTPUT="$(herdr pane split --pane "$LEAD_PANE" --direction down --cwd "$PROJECT_ROOT" --no-focus)"
  REVIEWER_PANE="$(printf '%s\n' "$REV_SPLIT_OUTPUT" | jq -r '.result.pane.pane_id // empty')"
  [[ -n "$REVIEWER_PANE" ]] || die "Could not split Reviewer pane: $REV_SPLIT_OUTPUT"
  sleep 1
  herdr pane run "$REVIEWER_PANE" env HERMES_KANBAN_HOME="$PROJECT_ROOT/.hermes" HERMES_KANBAN_BOARD="$BOARD_SLUG" hermes -p thriae_reviewer chat --cli
  save_runtime
fi


for pane in "$LEAD_PANE" "$ENGINEER_PANE" "$REVIEWER_PANE"; do
  herdr pane get "$pane" >/dev/null 2>&1 || die "Saved pane '$pane' is unavailable. Inspect the Herdr workspace before changing runtime state."
  wait_for_shell "$pane"
done

start_agent() {
  local name="$1" profile="$2" pane="$3" skill="$4" flag="$5" prompt_text initialized was_running=true

  if herdr pane process-info --pane "$pane" 2>/dev/null | grep -q 'hermes.*chat'; then
    log "$name is already running in $pane; reusing its current session"
  else
    was_running=false
    log "Starting $name using profile $profile in $pane"
    herdr pane run "$pane" env HERMES_KANBAN_HOME="$PROJECT_ROOT/.hermes" HERMES_KANBAN_BOARD="$BOARD_SLUG" hermes -p "$profile" chat --cli
    wait_for_hermes "$pane"
  fi

  case "$flag" in
    lead) initialized="$LEAD_INITIALIZED" ;;
    engineer) initialized="$ENGINEER_INITIALIZED" ;;
    reviewer) initialized="$REVIEWER_INITIALIZED" ;;
    *) die "Unknown internal initialization flag: $flag" ;;
  esac
  if [[ "$initialized" == "true" && "$was_running" == "true" ]]; then return 0; fi

  case "$name" in
    engineer)
      prompt_text=$(cat <<'PROMPT'
Initialize as the Project Engineer.

1. Load the complete project-local `executor` skill using `skill_view("executor")`.
2. Read the root `.hermes.md` instructions.
3. Read `.hermes/memories/PLANS.md` and `PROGRESS.md`.
4. Inspect relevant documentation under `.hermes/project/`.
5. Confirm that you own application implementation and `PROGRESS.md`, but not `PLANS.md`.
6. Do not begin implementation until Lead assigns or confirms the next approved task through Herdr.
7. Report readiness and wait for Lead.
PROMPT
)
      ;;
    reviewer)
      prompt_text=$(cat <<'PROMPT'
Initialize as the independent Project Reviewer.

1. Load the complete project-local `reviewer` skill using `skill_view("reviewer")`.
2. Read the root `.hermes.md` instructions.
3. Read relevant project context: `.hermes/project/`, `.hermes/memories/PLANS.md`, and `PROGRESS.md`.
4. Remain strictly read only. Never modify repository files or fix findings.
5. Do not review until Lead provides the exact review base commit, candidate commit, phase scope, and review round.
6. Report readiness and wait for Lead.
PROMPT
)
      ;;
    lead)
      prompt_text=$(cat <<'PROMPT'
BEGIN THE AUTONOMOUS MULTI-AGENT WORKFLOW.

You are the Project Lead and workflow orchestrator.

1. Load the complete project-local `planner` skill using `skill_view("planner")`.
2. Read the root `.hermes.md` instructions.
3. Read `.hermes/memories/PLANS.md` and `PROGRESS.md`.
4. Verify that Engineer and Reviewer are running and have completed initialization. Use Herdr status and output inspection. Do not assign work to an agent that is still initializing or blocked.
5. Recursively inspect relevant documentation under `.hermes/project/`, including the canonical roadmap.

INITIAL STATE RECONCILIATION IS REQUIRED.


Do not begin Phase 3 until reconciliation is complete and all required prerequisites are satisfied.

After reconciliation, autonomously coordinate Engineer through Herdr. Preserve an active milestone plan. If PLANS.md is empty, plan exactly one next eligible milestone from the verified roadmap and relevant documentation. Never plan the entire roadmap.

During implementation, continuously compare completed committed subitems against .hermes/project/, PLANS.md, and PROGRESS.md. Do not modify Engineer-owned files. Send focused feedback and pause affected work when a material scope, requirement, or architecture decision needs authorization.

At phase completion, freeze the exact candidate commit range, stop implementation assignments, and coordinate independent Reviewer assessment. Triage findings, assign valid corrections to Engineer, and repeat review until Reviewer approves the exact candidate.

Only after actual independent approval may you authorize Engineer to load `delivery` and create the PR against master. Do not create or merge PRs yourself.

Do not archive or clear the active milestone plan until required PRs are merged or otherwise explicitly integrated, dependencies are satisfied, and milestone exit criteria are verified.

Use Herdr for agent communication. Do not rely on conversational memory. Escalate genuine owner decisions or blockers instead of inventing answers.

Begin reconciliation now and continue autonomously within these boundaries.
PROMPT
)
      ;;
  esac

  log "Initializing $name and loading its $skill skill"
  # Herdr can only bind agents to the original workspace root pane, so submit
  # initialization text directly to every pane.
  herdr pane send-text "$pane" "$prompt_text"
  herdr pane send-keys "$pane" Enter

  case "$flag" in
    lead) LEAD_INITIALIZED=true ;;
    engineer) ENGINEER_INITIALIZED=true ;;
    reviewer) REVIEWER_INITIALIZED=true ;;
  esac
  save_runtime
}

# Initialize workers first so Lead can verify their readiness before assigning work.
start_agent engineer engineer "$ENGINEER_PANE" executor engineer
start_agent reviewer reviewer "$REVIEWER_PANE" reviewer reviewer
start_agent lead lead "$LEAD_PANE" planner lead

log "All three Project agents are started and initialized"
herdr workspace focus "$WORKSPACE_ID" >/dev/null 2>&1 || true

cat <<SUMMARY

Project autonomous workflow is active.

Repository: $PROJECT_ROOT
Workspace:  $WORKSPACE_ID
Lead pane:  $LEAD_PANE
Engineer:   $ENGINEER_PANE
Reviewer:   $REVIEWER_PANE
Runtime:    ${RUNTIME_FILE#$PROJECT_ROOT/}

Lead has been instructed to reconcile existing project state before assigning implementation work.

Useful commands:
  herdr pane list --workspace "$WORKSPACE_ID"
  herdr pane read "$LEAD_PANE" --source recent-unwrapped --lines 120
  herdr pane read "$ENGINEER_PANE" --source recent-unwrapped --lines 120
  herdr pane read "$REVIEWER_PANE" --source recent-unwrapped --lines 120

SUMMARY

log "Opening the visible Herdr TUI now. Press Ctrl+B then Q to detach; agents continue running."
exec herdr
