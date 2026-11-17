# Project

Usage documentation for the multi-agent workflow.

## Prerequisites

- `git`
- `hermes`
- `herdr`
- `jq`
- `bash`

Run `./.hermes/Start-Agents.sh` from the project root.

## Profile Models and Credentials

Every directory under `.hermes/profiles/<profile>/` declares that agent's native Hermes model configuration:

- `provider`: required, one provider ID on one line, such as `opencode-go`.
- `model`: required, one model ID on one line.
- `base_url`: optional custom endpoint. Omit it for built-in providers so Hermes supplies their native endpoint.
- `.env`: required API credentials, or an empty file for a keyless provider. This file is gitignored and must not be committed.

Every profile, including the reserved `thriae_lead` directory, requires `skills.txt` and `initial_prompt.txt`. The reserved directory configures only the fixed Lead and is excluded from worker discovery.

Credentials: the launcher never touches them. Profiles inherit the default Hermes home's API keys at creation; override per profile with `hermes -p <profile> setup` if needed. A project-side `.env` in a profile declaration directory is optional reference material, ignored by the launcher.

Example `.env` for OpenCode Go:

```dotenv
OPENCODE_GO_API_KEY=replace-me
```

`provider`, `model`, and optional `base_url` are authoritative. The launcher sets `model.provider` and `model.default` through the Hermes CLI and verifies the saved values. After editing `provider`, `model`, or `base_url`, rerun `./.hermes/Start-Agents.sh`. API credentials are never touched by the launcher (see above).

## Herdr Session Lifecycle

The launcher never starts, owns, or stops the Herdr daemon:

- With no Herdr server running, it only prepares profiles and opens the Herdr TUI (which launches its own session). Run `./.hermes/Start-Agents.sh` again while the session is up to wire up agent panes and the Kanban board automatically.
- With a Herdr server already running, it wires up panes and starts the agents, then attaches the TUI.
- To fully stop everything (agents and the Herdr server): `herdr server stop`.

Agent topology is static: the launcher loads every declared agent immediately and the Lead coordinates the already-running agents (Kanban dispatcher disabled; a missing agent is a blocker plus escalation, never a spawn).

## Kanban Orchestration State

Live orchestration state is stored in the project Kanban board (SQLite), selected via the `HERMES_KANBAN_BOARD` environment variable.

Kanban database location: `$HERMES_KANBAN_HOME/kanban.db` (default board) or `$HERMES_KANBAN_HOME/kanban/boards/<slug>/kanban.db`, with `HERMES_KANBAN_HOME` set to `<PROJECT_ROOT>/.hermes` by the launcher.

`HERMES_KANBAN_HOME` and `HERMES_KANBAN_BOARD` are exported for the launcher run and injected per agent process — never persisted into the Hermes home or profile `.env` files. Sessions launched outside this launcher must set both explicitly (see `.hermes.md` §4).
