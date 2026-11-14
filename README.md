# Project Autonomous Hermes and Herdr Workflow

This `.hermes` directory provides the project-level skills and shared state for three persistent agents:

1. **Lead**, Hermes profile `thriae_lead`, using skill `planner`.
2. **Engineer**, Hermes profile `thriae_engineer`, using skill `executor`. Engineer loads `delivery` only after independent review approval.
3. **Reviewer**, Hermes profile `thriae_reviewer`, using skill `reviewer`.

`delivery` is not a fourth agent. It is an Engineer subskill used at the PR stage.

## Prerequisites

Before using this multi-agent workflow, ensure the following are installed and available:

- `git` — repository and version control.
- `hermes` — Hermes Agent CLI (with profiles support).
- `herdr` — Herdr TUI and agent automation.
- `jq` — JSON parsing for Herdr responses.
- `bash` — launcher script execution.

Install Hermes and Herdr per their official documentation, then run `./.hermes/Start-Agents.sh` from the project root.

On first run, the launcher prompts for an LLM provider and API key, then saves them for future runs.

## Pre-populating Kanban

For ongoing projects with existing `PLANS.md`/`PROGRESS.md`/`ROADMAP.md`, Lead seeds the Kanban board from that state on first run (see planner skill section 17.10). After seeding, Kanban is the live source of truth.

## 1. Shared state

| File | Owner | Purpose |
|---|---|---|
| `memories/PLANS.md` | Lead | Exactly one active milestone plan |
| `memories/PROGRESS.md` | Engineer | Complete implementation hierarchy and verified progress |
| `memories/reviews/` | Lead preserves Reviewer reports | Immutable review round history |
| `memories/archive/milestones/` | Lead | Completed milestone plan archive |

Project requirements and architecture remain in the root `.hermes/project/` directory. These memory files do not replace project documentation.

## 2. One active milestone

`PLANS.md` is an active milestone slot, not a copy of the complete roadmap.

- If it is missing or empty, Lead reads `.hermes/memories/ROADMAP.md`, recursively examines relevant `.hermes/project/`, inspects the repository and progress, and plans exactly one next eligible milestone.
- If `PLANS.md` contains an active milestone, Lead preserves it and directs Engineer to continue.
- Lead does not plan future milestones in the active plan.
- Lead archives and clears the plan only after all required phases have passed review, required PRs have been merged, and milestone exit criteria are verified.

If the exact `.hermes/memories/ROADMAP.md` path is absent, Lead must locate the actual canonical roadmap within `.hermes/project/`, verify it from content and cross references, and record the path discrepancy. Lead must not create or rename roadmap files.

## 3. Artifact ownership

- Lead owns `PLANS.md` and the Kanban board (SQLite).
- Engineer owns application implementation and `PROGRESS.md`.
- Reviewer is read only and returns review reports to Lead through Herdr.
- Lead preserves Reviewer reports under `memories/reviews/`.
- Engineer creates PRs only after Reviewer approves the exact candidate commit.
- No agent merges PRs unless the user explicitly authorizes a separate merge workflow.

Do not allow agents to edit another agent's authoritative files.

## 3.1 Git and shared-file safety

Lead and Engineer share a working tree but never share file ownership.

- Engineer owns Git branch changes, commits, and pushes during implementation.
- Lead may inspect Git state but must not switch branches, reset files, stage, commit, or push while Engineer is active.
- Engineer stages explicit file paths only. Never use `git add .` or `git add -A`.
- Engineer must not accidentally include `PLANS.md` or review reports in an implementation subitem commit.
- Lead-authored plan creation, plan correction, or archive rotation must be committed as a separate plan-artifact change when version control is required. Engineer may commit the exact Lead-authored artifact only when Lead explicitly requests it; do not mix it with an implementation subitem commit.
- `Kanban board (SQLite, under .hermes/kanban/) and `memories/reviews/` are local orchestration state by default. They can be excluded locally with `.git/info/exclude` so they do not make the implementation branch appear dirty or leak into a PR. The canonical plan, progress tracker, skills, and completed plan archives remain versionable project artifacts.

To exclude local orchestration state:

```bash
cat >> .git/info/exclude <<'EOF'
Kanban board
.hermes/memories/reviews/
EOF
```

Only do this if those paths are not already tracked. If already tracked, coordinate the repository's intended tracking policy instead of assuming an exclude rule will untrack them.

## 4. Create Hermes profiles

First inspect existing profiles:

```bash
hermes profile list
```

Create only profiles that do not already exist:

```bash
hermes profile create thriae_lead --no-skills \
  --description "Project Lead, one-milestone planning and autonomous coordination"

hermes profile create thriae_engineer --no-skills \
  --description "Project Engineer, implementation, validation, progress, commits and PR creation"

hermes profile create thriae_reviewer --no-skills \
  --description "Project independent Reviewer, documentation and engineering quality assessment"
```

A new profile inherits default model and credential behavior according to Hermes profile configuration. Inspect each profile and configure its model and tools deliberately. Do not copy profile state directories into the repository.

## 5. Set the repository working directory

Run from the repository root:

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
```

Set all three profiles to the same repository root for the normal Lead and Engineer workflow:

```bash
for PROFILE in thriae_lead thriae_engineer thriae_reviewer; do
  hermes -p "$PROFILE" config set terminal.backend local
  hermes -p "$PROFILE" config set terminal.cwd "$PROJECT_ROOT"
done
```

Reviewer should preferably be moved to an isolated review worktree or read-only checkout for each review candidate. A Hermes profile is not a filesystem sandbox.

## 6. Trust the repository skills

Trust this project for each profile:

```bash
for PROFILE in thriae_lead thriae_engineer thriae_reviewer; do
  hermes -p "$PROFILE" skills trust "$PROJECT_ROOT"
done
```

Verify that the expected project skills are available:

- `lead`: `planner`
- `engineer`: `executor`, `delivery`
- `reviewer`: `reviewer`

The project-local skills are discovered from `.hermes/skills/`. Hermes requires a project trust decision before loading them.

## 7. Start Herdr

Start or attach to Herdr from the repository root:

```bash
cd "$PROJECT_ROOT"
herdr
```

Leave the Herdr session running. Open a second terminal in the same machine to create the workspace and start agents.

Before creating another workspace, inspect existing sessions:

```bash
herdr workspace list
herdr agent list
```

If the Project workspace and all three agents already exist, reuse them. Do not create duplicate agents with the same names.

## 8. Install or update the Hermes integration in Herdr

Herdr must have its Hermes agent integration available so `agent start --kind hermes` can launch and recognize Hermes.

Check the integration state:

```bash
herdr integration status
```

If the Hermes integration is missing or outdated, install or refresh it:

```bash
herdr integration install hermes
herdr integration status
```

Do this before launching the three agents. Herdr lists Hermes as a supported agent kind and provides an integration installer for it.

## 9. Create a workspace and three panes

The following commands create a new workspace. Run them only if an Project workspace does not already exist.

```bash
CREATED="$(herdr workspace create \
  --cwd "$PROJECT_ROOT" \
  --label project \
  --no-focus)"

LEAD_PANE="$(printf '%s\n' "$CREATED" | jq -r '.result.root_pane.pane_id')"

SPLIT_1="$(herdr pane split "$LEAD_PANE" \
  --direction right \
  --no-focus)"

ENGINEER_PANE="$(printf '%s\n' "$SPLIT_1" | jq -r '.result.pane.pane_id')"

SPLIT_2="$(herdr pane split "$ENGINEER_PANE" \
  --direction right \
  --no-focus)"

REVIEWER_PANE="$(printf '%s\n' "$SPLIT_2" | jq -r '.result.pane.pane_id')"

printf "Lead pane: %s\nEngineer pane: %s\nReviewer pane: %s\n" \
  "$LEAD_PANE" "$ENGINEER_PANE" "$REVIEWER_PANE"
```

Capture the returned pane IDs. Do not predict them.

## 10. Launch the three Hermes agents

```bash
# Prefer the provided launcher instead of manual agent starts:
./.hermes/Start-Agents.sh
```

Verify:

```bash
herdr agent get lead
herdr agent get engineer
herdr agent get reviewer
```

## 11. Initialize the agents

Send one startup prompt to each agent.

### Lead

```bash
herdr agent prompt lead \
"Load the complete planner skill. You are the Project Lead. Inspect the Kanban board, PLANS.md and PROGRESS.md. Recursively inspect .hermes/project/. Reconcile the recorded plan and progress with current Git branches, commits, PRs and the repository. Preserve an active plan. If PLANS.md is empty, plan exactly one eligible milestone from the canonical roadmap. Coordinate Engineer and Reviewer through Herdr. Do not implement code or modify PROGRESS.md. Report the current state and next action."
```

### Engineer

```bash
herdr agent prompt engineer \
"Load the complete executor skill. You are the Project Engineer. Inspect the Kanban board, PLANS.md and PROGRESS.md, plus relevant documentation under .hermes/project/. You own implementation and PROGRESS.md. Do not modify PLANS.md. Do not begin implementation until Lead assigns or confirms the next approved task. Report that you are ready."
```

### Reviewer

```bash
herdr agent prompt reviewer \
"Load the complete reviewer skill. You are the independent Project Reviewer. Remain idle until Lead provides an exact frozen review base commit, candidate commit, phase scope and review round. You are read only. Return your complete review report to Lead through this Herdr session. Do not modify repository files."
```

## 12. Operating the workflow

Lead assigns work asynchronously:

```bash
herdr agent prompt engineer "Implement the next approved subitem in the active milestone. Read all relevant docs and update PROGRESS.md."
```

Lead can continue inspecting documentation and completed work while Engineer runs.

Check state:

```bash
herdr agent get engineer
herdr agent read engineer --source recent-unwrapped --lines 120
```

Wait for a settled state when needed:

```bash
herdr agent wait engineer \
  --until idle \
  --until done \
  --until blocked \
  --timeout 1800000
```

A timeout does not prove that a prompt was not submitted. Read the agent output before retrying to avoid duplicate prompts. `unknown` does not mean success.

Reviewer is assigned only after Lead freezes a candidate commit range:

```bash
herdr agent prompt reviewer \
"Review milestone <MILESTONE>, phase <PHASE>. Base commit: <BASE_SHA>. Candidate commit: <HEAD_SHA>. Review round: <ROUND>. Inspect .hermes/project/, PLANS.md, PROGRESS.md and the complete base-to-candidate diff. Return the structured report to Lead. Do not modify files."
```

Lead triages findings and assigns valid corrections to Engineer. Reviewer rechecks the corrected candidate. Repeat until approval.

After approval, Engineer loads the `delivery` skill and creates the PR against `master`.

## 13. Reviewer isolation

A separate Hermes profile is not a filesystem permission boundary.

For stronger read-only review:

1. Create a separate worktree at the exact candidate commit.
2. Configure the Reviewer profile's `terminal.cwd` to that worktree.
3. Ensure it can read the required docs, plan, progress, and skills.
4. Use a container or operating system read-only mount if strict write prevention is required.
5. Return findings through Herdr; Lead preserves the report in the main repository.

Do not let Reviewer share Engineer's writable checkout when filesystem-level read-only enforcement is required.

## 14. Important current repository state

The supplied `PLANS.md` and `PROGRESS.md` describe Milestone 1, Project Foundation.

`PROGRESS.md` marks Phases 1 and 2 complete and Phases 3 and 4 pending. It also contains a cross-cutting ORM/Express refactor note that must be reconciled against actual Git branches and integration state.

The workflow starts in `RECONCILE_EXISTING_STATE`. Lead must verify the current repository before directing Engineer to Phase 3.

The planning snapshot and progress tracker are not live Git evidence.

## 15. Official documentation

- Hermes profiles: https://hermes-agent.nousresearch.com/.hermes/project/user-guide/profiles
- Hermes skills: https://hermes-agent.nousresearch.com/.hermes/project/user-guide/features/skills
- Herdr agent automation: https://herdr.dev/tui/.hermes/project/agent-automation/
- Herdr CLI reference: https://herdr.dev/tui/.hermes/project/cli-reference/


## Kanban Orchestration State

Live orchestration state is stored in the project Kanban board (SQLite), selected via the `HERMES_KANBAN_BOARD` environment variable (derived from the project directory name by the launcher). Use `hermes kanban` / `kanban_*` tools for tasks, comments, review handoffs, and blockers. Kanban board (SQLite) is the orchestration state.

Kanban database location: `$HERMES_KANBAN_HOME/kanban.db` (default board) or `$HERMES_KANBAN_HOME/kanban/boards/<slug>/kanban.db`, with `HERMES_KANBAN_HOME` set to `<PROJECT_ROOT>/.hermes` by the launcher.
