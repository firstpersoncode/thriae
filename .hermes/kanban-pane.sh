#!/usr/bin/env bash
set -u

: "${HERMES_KANBAN_HOME:?HERMES_KANBAN_HOME is required}"
: "${HERMES_KANBAN_BOARD:?HERMES_KANBAN_BOARD is required}"

hermes kanban boards create "$HERMES_KANBAN_BOARD" >/dev/null 2>&1 || true
hermes kanban boards switch "$HERMES_KANBAN_BOARD" >/dev/null 2>&1 || true

hermes kanban stats
hermes kanban list
exec hermes kanban watch
