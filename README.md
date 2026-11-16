# Project

Usage documentation for the multi-agent workflow.

## Prerequisites

- `git`
- `hermes`
- `herdr`
- `jq`
- `bash`

Run `./.hermes/Start-Agents.sh` from the project root.

## Kanban Orchestration State

Live orchestration state is stored in the project Kanban board (SQLite), selected via the `HERMES_KANBAN_BOARD` environment variable.

Kanban database location: `$HERMES_KANBAN_HOME/kanban.db` (default board) or `$HERMES_KANBAN_HOME/kanban/boards/<slug>/kanban.db`, with `HERMES_KANBAN_HOME` set to `<PROJECT_ROOT>/.hermes` by the launcher.
