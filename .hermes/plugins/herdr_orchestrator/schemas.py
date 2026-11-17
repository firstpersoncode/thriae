AGENT_CATALOG = {
    "name": "agent_catalog",
    "description": "List declared worker profiles and their current skill declarations. Use this before selecting an agent; profile names are not capability evidence.",
    "parameters": {"type": "object", "properties": {}, "required": []},
}

AGENT_START = {
    "name": "agent_start",
    "description": "Start a visible, task-scoped Herdr agent for an already assigned Kanban task. The task must be eligible and its assignee must be a declared profile. Returns a task-bound handle.",
    "parameters": {
        "type": "object",
        "properties": {"task_id": {"type": "string", "description": "Kanban task ID to execute."}},
        "required": ["task_id"],
    },
}

AGENT_PROMPT = {
    "name": "agent_prompt",
    "description": "Send an assignment or follow-up to the active agent for a task. The agent must not be working or blocked.",
    "parameters": {
        "type": "object",
        "properties": {
            "task_id": {"type": "string", "description": "Kanban task ID."},
            "text": {"type": "string", "description": "Complete assignment or follow-up text."},
        },
        "required": ["task_id", "text"],
    },
}

AGENT_WAIT = {
    "name": "agent_wait",
    "description": "Wait for a task's active agent to reach one of the requested lifecycle states.",
    "parameters": {
        "type": "object",
        "properties": {
            "task_id": {"type": "string", "description": "Kanban task ID."},
            "timeout_ms": {"type": "integer", "description": "Wait timeout in milliseconds.", "default": 120000},
            "until": {
                "type": "array",
                "items": {"type": "string", "enum": ["idle", "working", "blocked", "done", "unknown"]},
                "description": "Lifecycle states to wait for. Defaults to idle, done, and blocked.",
            },
        },
        "required": ["task_id"],
    },
}

AGENT_STATUS = {
    "name": "agent_status",
    "description": "Inspect the active agent, pane, task state, and lifecycle status for a task.",
    "parameters": {
        "type": "object",
        "properties": {"task_id": {"type": "string", "description": "Kanban task ID."}},
        "required": ["task_id"],
    },
}

AGENT_CLOSE = {
    "name": "agent_close",
    "description": "Close a task-scoped agent only after verified durable handoff. Requires a terminal Kanban state and evidence summary.",
    "parameters": {
        "type": "object",
        "properties": {
            "task_id": {"type": "string", "description": "Kanban task ID."},
            "evidence_summary": {"type": "string", "description": "Verified commits, artifacts, validation, or report evidence."},
        },
        "required": ["task_id", "evidence_summary"],
    },
}

AGENT_LIST = {
    "name": "agent_list",
    "description": "List task-bound agents currently registered by this orchestrator.",
    "parameters": {"type": "object", "properties": {}, "required": []},
}