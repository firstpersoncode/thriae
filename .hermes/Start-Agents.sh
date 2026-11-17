#!/usr/bin/env bash
set -Eeuo pipefail

# One-command launcher for Project's Lead agent and additional agents.
# Run from the repository root. Starts all declared agents in Herdr panes when
# a Herdr server is running; otherwise just prepares profiles and opens the TUI.

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

# This launcher is intentionally interactive and always ends by opening the
# visible Herdr TUI; it does not support headless mode.
if [[ ! -t 0 || ! -t 1 ]]; then
  echo "ERROR: Run this script from an interactive terminal. The launcher opens the visible Herdr TUI; it does not support headless mode." >&2
  exit 2
fi

RUNTIME_DIR="$PROJECT_ROOT/.hermes/runtime"
LEAD_PROFILE="thriae_lead"
RUNTIME_FILE="$RUNTIME_DIR/herdr-agents.json"
mkdir -p "$RUNTIME_DIR"

log() { printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

for cmd in git hermes herdr; do require_cmd "$cmd"; done

# Fail early if the root project instructions are missing. PLANS.md is only a
# warning: the Lead's own initialization plans the first milestone when it is
# absent or empty, so a first run must not be blocked by it.
[[ -s "$PROJECT_ROOT/.hermes.md" ]] || die "Required file is missing or empty: .hermes.md"
if [[ ! -s "$PROJECT_ROOT/.hermes/memories/PLANS.md" ]]; then
  log "NOTE: .hermes/memories/PLANS.md is missing or empty - the Lead will plan the first milestone during initialization"
fi

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

read_project_setting() {
  local file="$1" label="$2" value
  [[ -s "$file" ]] || die "Missing or empty $label: ${file#$PROJECT_ROOT/}"
  value="$(<"$file")"
  [[ -n "${value//[[:space:]]/}" && "$value" != *$'\n'* && "$value" != *$'\r'* ]] || die "$label must contain exactly one non-empty line: ${file#$PROJECT_ROOT/}"
  printf '%s' "$value"
}

ensure_profile() {
  local profile="$1" description="$2" declaration_dir="$3"
  local provider model base_url profile_home actual
  provider="$(read_project_setting "$declaration_dir/provider" "provider for $profile")" || return 1
  model="$(read_project_setting "$declaration_dir/model" "model for $profile")" || return 1

  if hermes profile show "$profile" >/dev/null 2>&1; then
    log "Using existing Hermes profile: $profile"
  else
    log "Creating Hermes profile: $profile"
    hermes profile create "$profile" --no-skills --description "$description"
  fi
  profile_home="${HERMES_HOME:-$HOME/.hermes}/profiles/$profile"
  # Launcher never touches credentials; profile creation copies the Hermes
  # home's keys. Warn only if the profile still ends up credential-less.
  if [[ ! -s "$profile_home/.env" ]]; then
    log "WARNING: $profile has no credentials yet ($profile_home/.env is missing or empty)"
    log "         Add API keys manually before starting agents, e.g.: hermes -p $profile setup"
  fi
  hermes -p "$profile" config set terminal.backend local >/dev/null
  hermes -p "$profile" config set terminal.cwd "$PROJECT_ROOT" >/dev/null
  hermes -p "$profile" config set model.provider "$provider" >/dev/null
  hermes -p "$profile" config set model.default "$model" >/dev/null
  if [[ -e "$declaration_dir/base_url" ]]; then
    base_url="$(read_project_setting "$declaration_dir/base_url" "base_url for $profile")" || return 1
    hermes -p "$profile" config set model.base_url "$base_url" >/dev/null
    actual="$(hermes -p "$profile" config get model.base_url)"
    [[ "$actual" == "$base_url" ]] || die "Failed to set base_url for $profile"
  elif hermes -p "$profile" config get model.base_url >/dev/null 2>&1; then
    # Built-in providers supply their native endpoint; clear a previous custom endpoint.
    hermes -p "$profile" config unset model.base_url >/dev/null
  fi
  actual="$(hermes -p "$profile" config get model.provider)"
  [[ "$actual" == "$provider" ]] || die "Failed to set provider for $profile"
  actual="$(hermes -p "$profile" config get model.default)"
  [[ "$actual" == "$model" ]] || die "Failed to set model for $profile"
  log "Configured $profile: $provider / $model"
}

log "Preparing Hermes profiles from .hermes/profiles/"
shopt -s nullglob
profile_dirs=()
for dir in "$PROJECT_ROOT/.hermes/profiles"/*/; do
  [[ -d "$dir" ]] || continue
  [[ "$(basename "$dir")" == "$LEAD_PROFILE" ]] && continue
  profile_dirs+=("$dir")
done
shopt -u nullglob
if [[ ${#profile_dirs[@]} -eq 0 ]]; then
  die "No worker profile directories found in $PROJECT_ROOT/.hermes/profiles/. Create at least one non-Lead <profile>/ with skills.txt and initial_prompt.txt."
fi
for dir in "${profile_dirs[@]}"; do
  [[ -d "$dir" ]] || continue
  profile="$(basename "$dir")"
  [[ -s "$dir/skills.txt" ]] || die "Missing or empty skills.txt for profile $profile"
  [[ -s "$dir/initial_prompt.txt" ]] || die "Missing or empty initial_prompt.txt for profile $profile"
  description="Project agent profile $profile"
  ensure_profile "$profile" "$description" "$dir"
done

# Hardcoded Lead agent (orchestrator) - configured separately, loaded last.
lead_dir="$PROJECT_ROOT/.hermes/profiles/$LEAD_PROFILE"
[[ -d "$lead_dir" ]] || die "Missing Lead profile declaration: .hermes/profiles/$LEAD_PROFILE/"
[[ -s "$lead_dir/skills.txt" ]] || die "Missing skills.txt for profile $LEAD_PROFILE"
[[ -s "$lead_dir/initial_prompt.txt" ]] || die "Missing initial_prompt.txt for profile $LEAD_PROFILE"
ensure_profile "$LEAD_PROFILE" "Project Lead, one-milestone planning and autonomous coordination" "$lead_dir"

# Collect profile names (source of truth) for subsequent steps.
PROFILE_NAMES=()
shopt -s nullglob
for dir in "$PROJECT_ROOT/.hermes/profiles"/*/; do
  [[ -d "$dir" ]] || continue
  [[ "$(basename "$dir")" == "$LEAD_PROFILE" ]] && continue
  PROFILE_NAMES+=("$(basename "$dir")")
done
shopt -u nullglob

[[ ${#PROFILE_NAMES[@]} -gt 0 ]] || die "No profile directories found in $PROJECT_ROOT/.hermes/profiles/. Create at least one <profile>/ before running."

# Hardcoded Lead agent is loaded last.
PROFILE_NAMES+=("thriae_lead")

log "Enabling Kanban toolset for all profiles"
for profile in "${PROFILE_NAMES[@]}"; do
  hermes -p "$profile" tools enable kanban --platform cli >/dev/null 2>&1 || true
  # Static topology: all agents pre-started here; dispatcher spawning disabled.
  hermes -p "$profile" config set kanban.dispatch_in_gateway false >/dev/null 2>&1 || true
done

# Trust repository-local skills per profile only (never the global trust store).
for profile in "${PROFILE_NAMES[@]}"; do
  HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}/profiles/$profile" hermes skills trust "$PROJECT_ROOT" >/dev/null 2>&1 || true
done

# Herdr manages its own daemon lifecycle (`herdr` to start/attach, `herdr
# server stop` to fully stop); panes are wired only when a server is running.
# Detect from output text: `herdr status server` exits 0 even when down.
herdr_status="$(herdr status server 2>/dev/null || true)"
if [[ -n "$herdr_status" ]] && ! grep -qi 'not running' <<<"$herdr_status"; then
  HERDR_SERVER_RUNNING=1
  log "Herdr server is running; agent panes will be wired up"
else
  HERDR_SERVER_RUNNING=0
  log "Herdr server is not running; skipping pane wiring (the TUI below manages its own session)"
  echo ""
  echo "Panes and agents were NOT wired up because no Herdr server is running."
  echo "To enable automatic wiring: run 'herdr' to start a session, keep it running,"
  echo "then rerun ./.hermes/Start-Agents.sh"
  echo ""
fi

# jq is required only for the wiring path (Herdr's JSON responses).
if [[ $HERDR_SERVER_RUNNING -eq 1 ]] && ! command -v jq >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    log "jq is required for Herdr's JSON responses; installing it with Homebrew"
    brew install jq
  else
    die "jq is required. Install it with 'brew install jq', then rerun this script."
  fi
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
PROFILE_PANES=()
PROFILE_INIT=()

# All declared profiles are started by the launcher; Lead is loaded last.
# Do not reset PROFILE_NAMES here: the list built above is the source of truth.

# Pane wiring needs the Herdr socket API (a running server).
if [[ $HERDR_SERVER_RUNNING -eq 1 ]]; then

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
      ""|zsh|bash|sh|fish)    sleep 0.5 ;;
      *) return 0 ;;
    esac
  done
}

fi # end HERDR_SERVER_RUNNING pane-wiring block

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

# Kanban env is injected per agent process at launch, never persisted into profile .env files.

# Lead coordinates through Kanban and Herdr CLI commands, not a profile-specific
# plugin. Keep the terminal tool enabled so Lead can run `herdr` directly.
hermes -p "$LEAD_PROFILE" tools enable terminal --platform cli >/dev/null
log "Lead Herdr CLI coordination enabled (no orchestration plugin)"

# Workspace/pane creation and agent startup need a running Herdr server.
if [[ $HERDR_SERVER_RUNNING -eq 1 ]]; then

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
    herdr pane run "${PROFILE_PANES[$i]}" env HERDR_PANE_ID="${PROFILE_PANES[$i]}" HERMES_WORKSPACE_ID="$WORKSPACE_ID" HERMES_KANBAN_HOME="$PROJECT_ROOT/.hermes" HERMES_KANBAN_BOARD="$BOARD_SLUG" hermes -p "${PROFILE_NAMES[$i]}" chat --cli
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

  local profile_dir="$PROJECT_ROOT/.hermes/profiles/$profile"
  local skills_file="$profile_dir/skills.txt"
  local prompt_file="$profile_dir/initial_prompt.txt"
  skills_list="$(grep -v '^[[:space:]]*$' "$skills_file" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/^ //;s/ $//')"
  [[ -s "$skills_file" ]] || die "Missing skills.txt for profile $profile"
  [[ -s "$prompt_file" ]] || die "Missing initial_prompt.txt for profile $profile"
  prompt_text="$(cat "$prompt_file")"

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

fi # end HERDR_SERVER_RUNNING workspace/agent block

if [[ $HERDR_SERVER_RUNNING -eq 1 ]]; then
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
else
echo ""
echo "Profile preparation complete; no agent panes were created (no Herdr server was running)."
echo "Repository: $PROJECT_ROOT"
echo "Profiles:   ${PROFILE_NAMES[*]}"
echo ""
echo "Next steps:"
echo "  1. Run 'herdr' (or use the TUI opening now) to start a Herdr session."
echo "  2. Rerun ./.hermes/Start-Agents.sh while the session is running to wire"
echo "     up the agent panes and Kanban board automatically."
echo ""
echo "To fully stop Herdr and all agents later: herdr server stop"
echo ""
fi

log "Opening the visible Herdr TUI now. Press Ctrl+B then Q to detach; agents keep running while the Herdr session is up."
exec herdr
