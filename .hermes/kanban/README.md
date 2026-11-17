# .hermes/kanban/

Live orchestration state for the multi-agent workflow, stored as SQLite boards.
Project-local by design: this directory is resolved via `HERMES_KANBAN_HOME`
and must never be shared with or pointed at from another project.

Contents:

- `boards/<slug>/kanban.db` — one SQLite database per board (slug is derived
  from the project directory name, e.g. `thriae`), plus its `board.json`,
  WAL/SHM sidecars, and init lock. Created and maintained by Hermes.
- `boards/<slug>/workspaces/` — per-workspace task scoping used by the board.

Rules:

- The board is authoritative for live task state. Task status lives here, not
  in markdown files.
- Access it only through `hermes kanban <verb>` commands or the `kanban_*`
  agent tools — never by editing the SQLite files directly.
- Agents launched by `.hermes/Start-Agents.sh` receive the correct
  `HERMES_KANBAN_HOME` / `HERMES_KANBAN_BOARD` at process launch; sessions
  started outside the launcher must set both variables explicitly.
