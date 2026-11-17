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

Example `.env` for OpenCode Go:

```dotenv
OPENCODE_GO_API_KEY=replace-me
```

The project `.env` files are authoritative. The launcher copies each one into the corresponding real Hermes profile, sets `model.provider` and `model.default` through the Hermes CLI, and verifies the saved values. After editing `provider`, `model`, `base_url`, or `.env`, rerun `./.hermes/Start-Agents.sh`.

## Kanban Orchestration State

Live orchestration state is stored in the project Kanban board (SQLite), selected via the `HERMES_KANBAN_BOARD` environment variable.

Kanban database location: `$HERMES_KANBAN_HOME/kanban.db` (default board) or `$HERMES_KANBAN_HOME/kanban/boards/<slug>/kanban.db`, with `HERMES_KANBAN_HOME` set to `<PROJECT_ROOT>/.hermes` by the launcher.
