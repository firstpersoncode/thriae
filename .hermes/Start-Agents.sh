#!/usr/bin/env bash
set -Eeuo pipefail

# One-command launcher for Project's persistent Lead agent and additional agents.
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
  "$PROJECT_ROOT/.hermes/memories/PLANS.md"
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
  # Bootstrap credentials from an existing profile that has them, if this profile lacks any key.
  PROFILE_HOME="${HERMES_HOME:-$HOME/.hermes}/profiles/$profile"
  if ! grep -qE '^(OPENCODE_GO_API_KEY|OPENCODE_ZEN_API_KEY)=.+' "$PROFILE_HOME/.env" 2>/dev/null; then
    for src in "${HERMES_HOME:-$HOME/.hermes}/profiles"/*/; do
      if grep -qE '^(OPENCODE_GO_API_KEY|OPENCODE_ZEN_API_KEY)=.+' "$src/.env" 2>/dev/null; then
        cp "$src/.env" "$PROFILE_HOME/.env"
        break
      fi
    done
  fi
  # Profile metadata lives in .hermes/profiles/$profile/ (skills.txt, initial_prompt.txt).

}

CRED_MARKER="$PROJECT_ROOT/.hermes/.credentials_configured"
if [[ ! -f "$CRED_MARKER" ]]; then
  echo ""
  echo "Select LLM provider:"
  echo "  1) OpenCode Go (OPENCODE_GO_API_KEY)"
  echo "  2) OpenCode Zen (OPENCODE_ZEN_API_KEY)"
  echo "  3) Skip (configure manually later)"
  read -r -p "Choice [1]: " PROVIDER_CHOICE
  PROVIDER_CHOICE="${PROVIDER_CHOICE:-1}"
  case "$PROVIDER_CHOICE" in
    1) ENV_KEY="OPENCODE_GO_API_KEY"; ENV_URL="OPENCODE_GO_BASE_URL=https://opencode.ai/zen/go/v1" ;;
    2) ENV_KEY="OPENCODE_ZEN_API_KEY"; ENV_URL="OPENCODE_ZEN_BASE_URL=https://opencode.ai/zen/v1" ;;
    3) ENV_KEY=""; ENV_URL="" ;;
    *) ENV_KEY="OPENCODE_GO_API_KEY"; ENV_URL="OPENCODE_GO_BASE_URL=https://opencode.ai/zen/go/v1" ;;
  esac
  if [[ -n "$ENV_KEY" ]]; then
    read -r -s -p "Paste your API key: " API_KEY
    echo ""
    [[ -n "$API_KEY" ]] || { echo "No key provided; skipping."; ENV_KEY=""; }
  fi
  if [[ -n "$ENV_KEY" ]]; then
    printf '%s=%s\n%s\n' "$ENV_KEY" "$API_KEY" "$ENV_URL" > "$PROJECT_ROOT/.hermes/.env.tmp"
    # Seed the default Hermes home only; project profiles are seeded after creation.
    cp "$PROJECT_ROOT/.hermes/.env.tmp" "$HOME/.hermes/.env"
    echo "$PROVIDER_CHOICE" > "$CRED_MARKER"
    log "Credentials saved for future runs"
  else
    echo "skipped" > "$CRED_MARKER"
    log "Skipped credential setup"
  fi
fi

log "Preparing Hermes profiles from .hermes/profiles/"
shopt -s nullglob
profile_dirs=("$PROJECT_ROOT/.hermes/profiles"/*/)
shopt -u nullglob
if [[ ${#profile_dirs[@]} -eq 0 ]]; then
  die "No profile directories found in $PROJECT_ROOT/.hermes/profiles/. Create at least one <profile>/ with skills.txt and initial_prompt.txt."
fi
for dir in "${profile_dirs[@]}"; do
  [[ -d "$dir" ]] || continue
  profile="$(basename "$dir")"
  [[ -s "$dir/skills.txt" ]] || die "Missing or empty skills.txt for profile $profile"
  [[ -s "$dir/initial_prompt.txt" ]] || die "Missing or empty initial_prompt.txt for profile $profile"
  description="Project agent profile $profile"
  ensure_profile "$profile" "$description"
done

# Hardcoded Lead agent (orchestrator) - profile created here, loaded last.
ensure_profile "thriae_lead" "Project Lead, one-milestone planning and autonomous coordination"

# Seed credentials into project profiles only (never other profiles).
if [[ -f "$PROJECT_ROOT/.hermes/.env.tmp" ]]; then
  shopt -s nullglob
  for dir in "$PROJECT_ROOT/.hermes/profiles"/*/; do
    [[ -d "$dir" ]] || continue
    profile="$(basename "$dir")"
    cp "$PROJECT_ROOT/.hermes/.env.tmp" "${HERMES_HOME:-$HOME/.hermes}/profiles/$profile/.env"
  done
  shopt -u nullglob
  # Seed Lead profile credentials too.
  cp "$PROJECT_ROOT/.hermes/.env.tmp" "${HERMES_HOME:-$HOME/.hermes}/profiles/thriae_lead/.env" 2>/dev/null || true
  rm -f "$PROJECT_ROOT/.hermes/.env.tmp"
fi

# Collect profile names (source of truth) for subsequent steps.
PROFILE_NAMES=()
shopt -s nullglob
for dir in "$PROJECT_ROOT/.hermes/profiles"/*/; do
  [[ -d "$dir" ]] || continue
  PROFILE_NAMES+=("$(basename "$dir")")
done
shopt -u nullglob

[[ ${#PROFILE_NAMES[@]} -gt 0 ]] || die "No profile directories found in $PROJECT_ROOT/.hermes/profiles/. Create at least one <profile>/ before running."

# Hardcoded Lead agent is loaded last.
PROFILE_NAMES+=("thriae_lead")

# Persist the project Kanban board location into each profile's .env so
# gateway-spawned sessions (which do not inherit this launcher's exports)
# also resolve the project-local board instead of ~/.hermes.
persist_kanban_env() {
  local home="$1"
  local env_file="$home/.env" tmp
  [[ -d "$home" ]] || return 0
  touch "$env_file"
  tmp="$(mktemp)"
  grep -vE '^(HERMES_KANBAN_HOME|HERMES_KANBAN_BOARD)=' "$env_file" > "$tmp" 2>/dev/null || true
  printf '\n# Kanban board (project-local; managed by Start-Agents.sh)\nHERMES_KANBAN_HOME=%s\nHERMES_KANBAN_BOARD=%s\n' "$PROJECT_ROOT/.hermes" "$BOARD_SLUG" >> "$tmp"
  mv "$tmp" "$env_file"
}
log "Enabling Kanban toolset for all profiles"
for profile in "${PROFILE_NAMES[@]}"; do
  hermes -p "$profile" tools enable kanban --platform cli >/dev/null 2>&1 || true
done

log "Trusting the repository-local skills"
hermes skills trust "$PROJECT_ROOT"
for profile in "${PROFILE_NAMES[@]}"; do
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
for profile in "${PROFILE_NAMES[@]}"; do
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
KANBAN_PANE=""
PROFILE_NAMES=()
PROFILE_PANES=()
PROFILE_INIT=()

# Collect profiles from .hermes/profiles/*.txt (source of truth).
shopt -s nullglob
for dir in "$PROJECT_ROOT/.hermes/profiles"/*/; do
  [[ -d "$dir" ]] || continue
  PROFILE_NAMES+=("$(basename "$dir")")
done
shopt -u nullglob

if [[ ${#PROFILE_NAMES[@]} -eq 0 ]]; then
  die "No profile directories found in $PROJECT_ROOT/.hermes/profiles/."
fi

# Hardcoded Lead agent is loaded last.
PROFILE_NAMES+=("thriae_lead")

if [[ -s "$RUNTIME_FILE" ]]; then
  jq -e 'type == "object"' "$RUNTIME_FILE" >/dev/null || die "Invalid runtime state JSON: $RUNTIME_FILE"
  WORKSPACE_ID="$(jq -r '.workspace_id // empty' "$RUNTIME_FILE")"
  KANBAN_PANE="$(jq -r '.kanban_pane_id // empty' "$RUNTIME_FILE")"
  for p in "${PROFILE_NAMES[@]}"; do
    pid="$(jq -r --arg p "$p" '.profiles[$p] // empty' "$RUNTIME_FILE")"
    init="$(jq -r --arg p "$p" '.initialized[$p] // false' "$RUNTIME_FILE")"
    PROFILE_PANES+=("$pid")
    PROFILE_INIT+=("$init")
  done
  need_recreate=false
  if [[ -n "$WORKSPACE_ID" ]]; then
    # validate at least first pane if present
    :
  fi
  for pid in "${PROFILE_PANES[@]}"; do
    if [[ -z "$pid" ]] || ! herdr pane get "$pid" >/dev/null 2>&1; then
      need_recreate=true
    fi
  done
  if [[ -n "$KANBAN_PANE" ]] && ! herdr pane get "$KANBAN_PANE" >/dev/null 2>&1; then
    need_recreate=true
  fi
  if $need_recreate; then
    log "Saved pane state is unavailable; recreating agents"
    WORKSPACE_ID=""
    KANBAN_PANE=""
    PROFILE_PANES=()
    PROFILE_INIT=()
  fi
else
  : # no runtime record; will create
fi

save_runtime() {
  local tmp="$RUNTIME_FILE.tmp"
  local profiles_json="{" initialized_json="{"
  for i in "${!PROFILE_NAMES[@]}"; do
    profiles_json+="\"${PROFILE_NAMES[$i]}\":\"${PROFILE_PANES[$i]}\","
    initialized_json+="\"${PROFILE_NAMES[$i]}\":${PROFILE_INIT[$i]},"
  done
  profiles_json="${profiles_json%,}}"
  initialized_json="${initialized_json%,}}"
  jq -n \
    --arg workspace_id "$WORKSPACE_ID" \
    --arg kanban_pane_id "$KANBAN_PANE" \
    --argjson profiles "$profiles_json" \
    --argjson initialized "$initialized_json" \
    '{workspace_id:$workspace_id,kanban_pane_id:$kanban_pane_id,profiles:$profiles,initialized:$initialized}' \
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
export HERMES_KANBAN_HOME="$PROJECT_ROOT/.hermes"
export HERMES_KANBAN_BOARD="$BOARD_SLUG"
# Guard against cross-project board misplacement: the home must be project-local.
[[ "$HERMES_KANBAN_HOME" == "$PROJECT_ROOT/.hermes" ]] || { echo "ERROR: HERMES_KANBAN_HOME is not project-local" >&2; exit 1; }
log "Kanban home: $HERMES_KANBAN_HOME (board: $BOARD_SLUG)"
log "Ensuring Kanban board: $BOARD_SLUG"
hermes kanban boards create "$BOARD_SLUG" --name "$(basename "$PROJECT_ROOT")" >/dev/null 2>&1 || true
hermes kanban boards set-default-workdir "$BOARD_SLUG" "$PROJECT_ROOT" >/dev/null 2>&1 || true
hermes kanban boards switch "$BOARD_SLUG" >/dev/null 2>&1 || true

# Keep the Kanban pane command in a script file so herdr does not split the
# multi-command shell string into separate arguments.
KANBAN_PANE_SCRIPT="$PROJECT_ROOT/.hermes/kanban-pane.sh"
cat > "$KANBAN_PANE_SCRIPT" <<'KANBAN_PANE_EOF'
#!/usr/bin/env bash
set -u

: "${HERMES_KANBAN_HOME:?HERMES_KANBAN_HOME is required}"
: "${HERMES_KANBAN_BOARD:?HERMES_KANBAN_BOARD is required}"

hermes kanban boards create "$HERMES_KANBAN_BOARD" >/dev/null 2>&1 || true
hermes kanban boards switch "$HERMES_KANBAN_BOARD" >/dev/null 2>&1 || true

hermes kanban stats
hermes kanban list
exec hermes kanban watch
KANBAN_PANE_EOF
chmod +x "$KANBAN_PANE_SCRIPT"

persist_kanban_env "${HERMES_HOME:-$HOME/.hermes}"
for profile in "${PROFILE_NAMES[@]}"; do
  persist_kanban_env "${HERMES_HOME:-$HOME/.hermes}/profiles/$profile"
done
log "Kanban board persisted to profile envs: $BOARD_SLUG ($PROJECT_ROOT/.hermes)"

if [[ -z "$WORKSPACE_ID" ]]; then
  log "Creating the Project Agents workspace"
  CREATED="$(herdr workspace create --cwd "$PROJECT_ROOT" --label "Project Agents" --no-focus)"
  WORKSPACE_ID="$(printf '%s\n' "$CREATED" | jq -r '.result.workspace.workspace_id // empty')"
  ROOT_PANE="$(printf '%s\n' "$CREATED" | jq -r '.result.root_pane.pane_id // empty')"
  [[ -n "$WORKSPACE_ID" && -n "$ROOT_PANE" ]] || die "Could not parse Herdr workspace response: $CREATED"

  PROFILE_PANES=()
  PROFILE_INIT=()
  for i in "${!PROFILE_NAMES[@]}"; do
    if [[ $i -eq 0 ]]; then
      PROFILE_PANES+=("$ROOT_PANE")
    else
      SPLIT_OUTPUT="$(herdr pane split --pane "${PROFILE_PANES[$((i-1))]}" --direction right --cwd "$PROJECT_ROOT" --no-focus)"
      NEW_PANE="$(printf '%s\n' "$SPLIT_OUTPUT" | jq -r '.result.pane.pane_id // empty')"
      [[ -n "$NEW_PANE" ]] || die "Could not split pane for ${PROFILE_NAMES[$i]}: $SPLIT_OUTPUT"
      sleep 0.5
      PROFILE_PANES+=("$NEW_PANE")
    fi
    PROFILE_INIT+=("false")
  done

  KANBAN_SPLIT_OUTPUT="$(herdr pane split --pane "${PROFILE_PANES[${#PROFILE_PANES[@]}-1]}" --direction down --cwd "$PROJECT_ROOT" --no-focus)"
  KANBAN_PANE="$(printf '%s\n' "$KANBAN_SPLIT_OUTPUT" | jq -r '.result.pane.pane_id // empty')"
  [[ -n "$KANBAN_PANE" ]] || die "Could not split Kanban pane: $KANBAN_SPLIT_OUTPUT"
  sleep 1

  for i in "${!PROFILE_NAMES[@]}"; do
    herdr pane run "${PROFILE_PANES[$i]}" env HERMES_KANBAN_HOME="$PROJECT_ROOT/.hermes" HERMES_KANBAN_BOARD="$BOARD_SLUG" hermes -p "${PROFILE_NAMES[$i]}" chat --cli
  done
  sleep 1
  herdr pane run "$KANBAN_PANE" env HERMES_KANBAN_HOME="$PROJECT_ROOT/.hermes" HERMES_KANBAN_BOARD="$BOARD_SLUG" bash "$PROJECT_ROOT/.hermes/kanban-pane.sh"
  save_runtime
fi

for pane in "${PROFILE_PANES[@]}" "$KANBAN_PANE"; do
  herdr pane get "$pane" >/dev/null 2>&1 || die "Saved pane '$pane' is unavailable. Inspect the Herdr workspace before changing runtime state."
  wait_for_shell "$pane"
done


start_agent() {
  local idx="$1"
  local profile="${PROFILE_NAMES[$idx]}"
  local pane="${PROFILE_PANES[$idx]}"
  local skills_list prompt_text initialized was_running=true

  if [[ "$profile" == "thriae_lead" ]]; then
    skills_list="planner"
    prompt_text="BEGIN THE AUTONOMOUS MULTI-AGENT WORKFLOW.

You are the Project Lead and workflow orchestrator.

1. Load the complete project-local planner skill using skill_view(\"planner\").
2. Read the root .hermes.md instructions.
3. Read .hermes/memories/PLANS.md.
4. Verify that all other agents are running and have completed initialization.
5. Recursively inspect relevant documentation under .hermes/project/, including the canonical roadmap.

INITIAL STATE RECONCILIATION IS REQUIRED.

Do not begin Phase 3 until reconciliation is complete and all required prerequisites are satisfied.

After reconciliation, autonomously coordinate agents through Herdr. Preserve an active milestone plan. If PLANS.md is empty, plan exactly one next eligible milestone from the verified roadmap and relevant documentation. Never plan the entire roadmap.

During implementation, continuously compare completed committed subitems against .hermes/project/ and PLANS.md. Do not modify application source code. Send focused feedback and pause affected work when a material scope, requirement, or architecture decision needs authorization.

At phase completion, freeze the exact candidate commit range, stop implementation assignments, and coordinate independent review. Triage findings, assign valid corrections, and repeat review until approved the exact candidate.

Only after actual independent approval may you authorize PR creation against master. Do not create or merge PRs yourself.

Do not archive or clear the active milestone plan until required PRs are merged or otherwise explicitly integrated, dependencies are satisfied, and milestone exit criteria are verified.

Use Herdr for agent communication. Do not rely on conversational memory. Escalate genuine owner decisions or blockers instead of inventing answers.

Begin reconciliation now and continue autonomously within these boundaries."
  else
    local profile_dir="$PROJECT_ROOT/.hermes/profiles/$profile"
    local skills_file="$profile_dir/skills.txt"
    local prompt_file="$profile_dir/initial_prompt.txt"
    skills_list="$(grep -v '^[[:space:]]*$' "$skills_file" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//')"
    [[ -s "$skills_file" ]] || die "Missing skills.txt for profile $profile"
    [[ -s "$prompt_file" ]] || die "Missing initial_prompt.txt for profile $profile"
    prompt_text="$(cat "$prompt_file")"
  fi

  if herdr pane process-info --pane "$pane" 2>/dev/null | grep -q 'hermes.*chat'; then
    log "$profile is already running in $pane; reusing its current session"
  else
    was_running=false
    log "Starting $profile using profile $profile in $pane"
    herdr pane run "$pane" env HERMES_KANBAN_HOME="$PROJECT_ROOT/.hermes" HERMES_KANBAN_BOARD="$BOARD_SLUG" hermes -p "$profile" chat --cli
    wait_for_hermes "$pane"
  fi

  initialized="${PROFILE_INIT[$idx]}"
  if [[ "$initialized" == "true" && "$was_running" == "true" ]]; then return 0; fi

  log "Initializing $profile"
  herdr pane send-text "$pane" "$prompt_text"
  herdr pane send-keys "$pane" Enter

  PROFILE_INIT[$idx]=true
  save_runtime
}


# Initialize workers first so Lead can verify their readiness before assigning work.
for i in "${!PROFILE_NAMES[@]}"; do
  start_agent "$i"
done

log "All Project agents are started and initialized"
herdr workspace focus "$WORKSPACE_ID" >/dev/null 2>&1 || true

echo ""
echo "Project autonomous workflow is active."
echo ""
echo "Repository: $PROJECT_ROOT"
echo "Workspace:  $WORKSPACE_ID"
for i in "${!PROFILE_NAMES[@]}"; do
  echo "Profile ${PROFILE_NAMES[$i]}: pane ${PROFILE_PANES[$i]}"
done
echo "Kanban pane: $KANBAN_PANE"
echo "Runtime:    ${RUNTIME_FILE#$PROJECT_ROOT/}"
echo ""
echo "Useful commands:"
echo "  herdr pane list --workspace $WORKSPACE_ID"
for i in "${!PROFILE_NAMES[@]}"; do
  echo "  herdr pane read ${PROFILE_PANES[$i]} --source recent-unwrapped --lines 120"
done
echo ""

log "Opening the visible Herdr TUI now. Press Ctrl+B then Q to detach; agents continue running."
exec herdr
