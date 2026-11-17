import json
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path

CTX = None


class OrchestratorError(Exception):
    pass


def _project_root() -> Path:
    if os.environ.get("PROJECT_ROOT"):
        return Path(os.environ["PROJECT_ROOT"]).resolve()
    kanban_home = os.environ.get("HERMES_KANBAN_HOME")
    if kanban_home:
        candidate = Path(kanban_home).resolve().parent
        if (candidate / ".hermes").is_dir():
            return candidate
    return Path.cwd().resolve()


def _herdr() -> str:
    return os.environ.get("HERDR_BIN_PATH") or "herdr"


def _run_herdr(args, timeout=120):
    try:
        proc = subprocess.run(
            [_herdr(), *args],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except FileNotFoundError as exc:
        raise OrchestratorError(f"herdr executable not found: {exc}") from exc
    except subprocess.TimeoutExpired as exc:
        raise OrchestratorError(f"herdr command timed out: {' '.join(args)}") from exc
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip()
        raise OrchestratorError(f"herdr failed ({proc.returncode}): {detail}")
    stdout = proc.stdout.strip()
    if not stdout:
        return {}
    try:
        return json.loads(stdout)
    except json.JSONDecodeError as exc:
        raise OrchestratorError(f"herdr returned non-JSON output: {stdout[:500]}") from exc


def _lead_context():
    pane_id = os.environ.get("HERDR_PANE_ID")
    tab_id = os.environ.get("HERDR_TAB_ID")
    workspace_id = os.environ.get("HERMES_WORKSPACE_ID") or os.environ.get("HERDR_WORKSPACE_ID")
    if not pane_id:
        raise OrchestratorError("Lead is not running inside a Herdr-managed pane (HERDR_PANE_ID is unset)")
    return {
        "pane_id": pane_id,
        "tab_id": tab_id,
        "workspace_id": workspace_id,
    }


def _runtime_dir() -> Path:
    return _project_root() / ".hermes" / "runtime"


def _state_path() -> Path:
    return _runtime_dir() / "agent-broker.json"


def _lock_path() -> Path:
    return _runtime_dir() / "agent-broker.lock"


class _StateLock:
    def __enter__(self):
        self._runtime_dir().mkdir(parents=True, exist_ok=True)
        self.handle = open(_lock_path(), "w", encoding="utf-8")
        import fcntl

        fcntl.flock(self.handle.fileno(), fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        import fcntl

        fcntl.flock(self.handle.fileno(), fcntl.LOCK_UN)
        self.handle.close()
        return False

    def _runtime_dir(self):
        return _runtime_dir()


def _load_state():
    path = _state_path()
    if not path.is_file():
        return {"version": 1, "agents": {}}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise OrchestratorError(f"agent broker state is unreadable: {exc}") from exc
    if not isinstance(data, dict) or not isinstance(data.get("agents"), dict):
        raise OrchestratorError("agent broker state has an invalid shape")
    data.setdefault("version", 1)
    return data


def _save_state(state):
    path = _state_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix="agent-broker.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(state, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
    finally:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass


def _profiles():
    root = _project_root() / ".hermes" / "profiles"
    if not root.is_dir():
        return [], []
    profiles = []
    invalid = []
    for child in sorted(root.iterdir(), key=lambda p: p.name):
        if not child.is_dir() or child.name == "thriae_lead":
            continue
        skills_file = child / "skills.txt"
        prompt_file = child / "initial_prompt.txt"
        if not skills_file.is_file() or not prompt_file.is_file():
            invalid.append({"profile": child.name, "reason": "missing skills.txt or initial_prompt.txt"})
            continue
        skills_text = skills_file.read_text(encoding="utf-8")
        prompt_text = prompt_file.read_text(encoding="utf-8")
        if not skills_text.strip() or not prompt_text.strip():
            invalid.append({"profile": child.name, "reason": "empty skills.txt or initial_prompt.txt"})
            continue
        skills = [line.strip() for line in skills_text.splitlines() if line.strip()]
        skill_status = []
        for skill in skills:
            skill_path = _project_root() / ".hermes" / "skills" / skill / "SKILL.md"
            skill_status.append({"name": skill, "definition_present": skill_path.is_file()})
        profiles.append({
            "name": child.name,
            "skills": skills,
            "skill_status": skill_status,
            "initial_prompt": prompt_text,
        })
    return profiles, invalid


def _profile(name):
    for profile in _profiles()[0]:
        if profile["name"] == name:
            return profile
    return None


def _kanban_show(ctx, task_id):
    result = ctx.dispatch_tool("kanban_show", {"task_id": task_id})
    if isinstance(result, str):
        try:
            result = json.loads(result)
        except json.JSONDecodeError as exc:
            raise OrchestratorError(f"kanban_show returned non-JSON output: {result[:500]}") from exc
    if not isinstance(result, dict):
        raise OrchestratorError("kanban_show returned an unexpected result")
    task = result.get("task")
    if not isinstance(task, dict) or not task.get("id"):
        raise OrchestratorError(f"task not found or inaccessible: {task_id}")
    return task, result


def _task_allowed_for_start(task):
    status = str(task.get("status") or "").strip().lower()
    if status in {"done", "review", "archived", "blocked"}:
        raise OrchestratorError(f"task {task['id']} is not eligible for a new agent (status: {status})")
    if task.get("unsatisfied_parents"):
        raise OrchestratorError(f"task {task['id']} has unsatisfied parent dependencies")
    profile = task.get("assignee")
    if not profile:
        raise OrchestratorError(f"task {task['id']} has no assignee profile")
    if _profile(profile) is None:
        raise OrchestratorError(f"task {task['id']} is assigned to an undeclared profile: {profile}")
    return profile


def _active_entry(state, task_id):
    entry = state.get("agents", {}).get(task_id)
    if not entry:
        return None
    try:
        data = _run_herdr(["agent", "get", entry["agent_name"]])
    except OrchestratorError:
        data = None
    if not isinstance(data, dict):
        return entry
    result = data.get("result", data)
    status = None
    if isinstance(result, dict):
        status = result.get("status") or result.get("agent_status")
    if status in {"working", "idle", "done", "blocked", "unknown"}:
        return entry
    # Stale registration: Herdr no longer knows this agent.
    with _StateLock():
        fresh = _load_state()
        fresh.get("agents", {}).pop(task_id, None)
        _save_state(fresh)
    return None


def _live_agent_status(agent_name):
    try:
        data = _run_herdr(["agent", "get", agent_name])
    except OrchestratorError as exc:
        return None, str(exc)
    result = data.get("result", data) if isinstance(data, dict) else data
    status = None
    if isinstance(result, dict):
        status = result.get("status") or result.get("agent_status") or result.get("state")
    return status, None


def _pane_exists(pane_id):
    try:
        data = _run_herdr(["pane", "get", pane_id])
    except OrchestratorError:
        return False
    return isinstance(data, dict)


def _agent_name_for_task(task_id, profile, state):
    used = {entry["agent_name"] for entry in state.get("agents", {}).values()}
    base = "t" + re.sub(r"[^a-z0-9_-]", "", task_id.lower())[-8:]
    if not base or not base[0].isalpha():
        base = "t" + base
    candidate = base[:32]
    suffix = 1
    while candidate in used:
        suffix_text = f"-{suffix}"
        candidate = (base[: 32 - len(suffix_text)] + suffix_text)
        suffix += 1
    return candidate


def _layout_direction(lead_pane):
    try:
        data = _run_herdr(["pane", "layout", "--pane", lead_pane])
    except OrchestratorError:
        return "right"
    result = data.get("result", data) if isinstance(data, dict) else data
    area = None
    if isinstance(result, dict):
        area = result.get("area") or result.get("pane", {}).get("area")
    if isinstance(area, dict):
        width = area.get("width") or area.get("w")
        height = area.get("height") or area.get("h")
        if isinstance(width, (int, float)) and isinstance(height, (int, float)) and height > width:
            return "down"
    return "right"


def _close_pane_best_effort(pane_id):
    try:
        _run_herdr(["pane", "close", pane_id], timeout=30)
    except OrchestratorError:
        pass


def _cleanup_entry(state, task_id):
    entry = state.get("agents", {}).pop(task_id, None)
    if entry:
        _close_pane_best_effort(entry["pane_id"])
    return entry


def _assignment_text(task, profile):
    body = (task.get("body") or "").strip()
    return (
        f"You are assigned Kanban task {task['id']}.\n\n"
        f"Profile: {profile}\n"
        f"Title: {task.get('title') or ''}\n\n"
        f"Task body:\n{body or '(none provided)'}\n\n"
        "Requirements:\n"
        "- Follow only your own declared prompt and skills.\n"
        "- Read only the project context needed for this task.\n"
        "- Do not discover, contact, or coordinate peer agents.\n"
        "- Report progress and completion through Kanban with the explicit task ID.\n"
        "- Preserve evidence, commits, artifacts, and validation results.\n"
        "- Stop at the task's terminal handoff.\n"
    )


def _handle_catalog(args, **kwargs):
    profiles, invalid = _profiles()
    return json.dumps({
        "profiles": [
            {
                "name": profile["name"],
                "skills": profile["skills"],
                "skill_status": profile["skill_status"],
                "initial_prompt": profile["initial_prompt"],
            }
            for profile in profiles
        ],
        "invalid_profiles": invalid,
        "project_root": str(_project_root()),
    })


def _handle_start(args, **kwargs):
    task_id = str(args.get("task_id") or "").strip()
    if not task_id:
        raise OrchestratorError("task_id is required")
    ctx = CTX
    if ctx is None:
        raise OrchestratorError("orchestrator plugin is not initialized")
    task, _ = _kanban_show(ctx, task_id)
    profile_name = _task_allowed_for_start(task)
    lead = _lead_context()
    with _StateLock():
        state = _load_state()
        state.setdefault("lead_pane_id", lead["pane_id"])
        state.setdefault("lead_tab_id", lead["tab_id"])
        state.setdefault("lead_workspace_id", lead["workspace_id"])
        state.setdefault("agents", {})
        entry = _active_entry(state, task_id)
        if entry is not None:
            _save_state(state)
            return json.dumps({
                "task_id": task_id,
                "profile": entry["profile"],
                "agent_name": entry["agent_name"],
                "pane_id": entry["pane_id"],
                "status": "already_active",
            })
        profile = _profile(profile_name)
        if profile is None:
            raise OrchestratorError(f"assigned profile is not declared: {profile_name}")
        direction = _layout_direction(lead["pane_id"])
        split = _run_herdr([
            "pane", "split", "--current", "--direction", direction,
            "--cwd", str(_project_root()),
            "--env", f"HERMES_KANBAN_HOME={_project_root() / '.hermes'}",
            "--env", f"HERMES_KANBAN_BOARD={os.environ.get('HERMES_KANBAN_BOARD', '')}",
            "--no-focus",
        ])
        split_result = split.get("result", split) if isinstance(split, dict) else split
        pane_id = None
        if isinstance(split_result, dict):
            pane = split_result.get("pane")
            if isinstance(pane, dict):
                pane_id = pane.get("pane_id")
            pane_id = pane_id or split_result.get("pane_id")
        if not pane_id:
            raise OrchestratorError(f"herdr did not return a pane id: {split}")
        agent_name = _agent_name_for_task(task_id, profile_name, state)
        start = _run_herdr([
            "agent", "start", agent_name, "--kind", "hermes",
            "--pane", pane_id, "--", "-p", profile_name, "chat", "--cli",
        ], timeout=90)
        entry = {
            "task_id": task_id,
            "profile": profile_name,
            "agent_name": agent_name,
            "pane_id": pane_id,
            "workspace_id": lead["workspace_id"],
            "tab_id": lead["tab_id"],
            "keep_open": True,
            "keep_open_reason": "active_phase",
            "close_reason": None,
            "closed_at": None,
            "created_at": time.time(),
            "status": "active",
            }
        state["agents"][task_id] = entry
        _save_state(state)
    # Initialize and assign outside the lock; failures are reported and cleaned up.
    try:
        initial_prompt = profile["initial_prompt"]
        _run_herdr(["agent", "prompt", agent_name, initial_prompt, "--wait", "--timeout", "30000"], timeout=60)
        _run_herdr(["agent", "prompt", agent_name, _assignment_text(task, profile_name), "--wait", "--timeout", "120000"], timeout=180)
    except OrchestratorError as exc:
        _close_pane_best_effort(pane_id)
        with _StateLock():
            fresh = _load_state()
            fresh.get("agents", {}).pop(task_id, None)
            _save_state(fresh)
        raise OrchestratorError(f"agent started but assignment failed: {exc}") from exc
    return json.dumps({
        "task_id": task_id,
        "profile": profile_name,
        "agent_name": agent_name,
        "pane_id": pane_id,
        "status": "started",
        "start_result": start,
    })


def _handle_prompt(args, **kwargs):
    task_id = str(args.get("task_id") or "").strip()
    text = str(args.get("text") or "")
    if not task_id:
        raise OrchestratorError("task_id is required")
    if not text.strip():
        raise OrchestratorError("text is required")
    with _StateLock():
        state = _load_state()
        entry = _active_entry(state, task_id)
        if entry is None:
            raise OrchestratorError(f"no active agent for task {task_id}")
        agent_name = entry["agent_name"]
        task, _ = _kanban_show(CTX, task_id)
        status = str(task.get("status") or "").lower()
        if status in {"done", "archived"}:
            raise OrchestratorError(f"task {task_id} is already terminal ({status})")
        agent_status, agent_error = _live_agent_status(agent_name)
        if agent_status in {"working", "blocked"}:
            raise OrchestratorError(f"agent {agent_name} is {agent_status}; cannot prompt now")
    result = _run_herdr(["agent", "prompt", agent_name, text, "--wait", "--timeout", "120000"], timeout=180)
    with _StateLock():
        state = _load_state()
        if task_id in state.get("agents", {}):
            state["agents"][task_id]["last_prompt_at"] = time.time()
            _save_state(state)
    return json.dumps({"task_id": task_id, "agent_name": agent_name, "result": result})


def _handle_wait(args, **kwargs):
    task_id = str(args.get("task_id") or "").strip()
    if not task_id:
        raise OrchestratorError("task_id is required")
    timeout_ms = int(args.get("timeout_ms") or 120000)
    if timeout_ms < 1000 or timeout_ms > 300000:
        raise OrchestratorError("timeout_ms must be between 1000 and 300000")
    until = args.get("until")
    if until is None:
        until = ["idle", "done", "blocked"]
    if isinstance(until, str):
        until = [until]
    if not isinstance(until, list) or not until:
        raise OrchestratorError("until must be a non-empty list of states")
    with _StateLock():
        state = _load_state()
        entry = _active_entry(state, task_id)
        if entry is None:
            raise OrchestratorError(f"no active agent for task {task_id}")
        agent_name = entry["agent_name"]
    cmd = ["agent", "wait", agent_name, "--timeout", str(timeout_ms)]
    for state_name in until:
        cmd.extend(["--until", str(state_name)])
    result = _run_herdr(cmd, timeout=(timeout_ms // 1000) + 30)
    return json.dumps({"task_id": task_id, "agent_name": agent_name, "result": result})


def _handle_status(args, **kwargs):
    task_id = str(args.get("task_id") or "").strip()
    if not task_id:
        raise OrchestratorError("task_id is required")
    with _StateLock():
        state = _load_state()
        entry = _active_entry(state, task_id)
    if entry is None:
        return json.dumps({"task_id": task_id, "active": False})
    agent_status, agent_error = _live_agent_status(entry["agent_name"])
    pane_exists = _pane_exists(entry["pane_id"])
    task, _ = _kanban_show(CTX, task_id)
    return json.dumps({
        "task_id": task_id,
        "active": True,
        "profile": entry["profile"],
        "agent_name": entry["agent_name"],
        "pane_id": entry["pane_id"],
        "agent_status": agent_status,
        "agent_error": agent_error,
        "pane_exists": pane_exists,
        "task_status": task.get("status"),
        "task_assignee": task.get("assignee"),
    })


_CLOSE_REASONS = {
    "phase_complete", "milestone_complete", "stale_context",
    "profile_change", "resource_pressure", "abandoned",
}


def _handle_close(args, **kwargs):
    task_id = str(args.get("task_id") or "").strip()
    evidence_summary = str(args.get("evidence_summary") or "").strip()
    close_reason = str(args.get("close_reason") or "").strip()
    if not task_id:
        raise OrchestratorError("task_id is required")
    if not evidence_summary:
        raise OrchestratorError("evidence_summary is required and must describe verified durable handoff")
    if close_reason not in _CLOSE_REASONS:
        raise OrchestratorError(
            "close_reason must be one of: " + ", ".join(sorted(_CLOSE_REASONS)))
    with _StateLock():
        state = _load_state()
        entry = _active_entry(state, task_id)
        if entry is None:
            raise OrchestratorError(f"no active agent for task {task_id}")
        task, _ = _kanban_show(CTX, task_id)
        status = str(task.get("status") or "").lower()
        if status not in {"done", "review"}:
            raise OrchestratorError(f"task {task_id} is not in a terminal handoff state (status: {status})")
        agent_status, agent_error = _live_agent_status(entry["agent_name"])
        if agent_status in {"working", "blocked"}:
            raise OrchestratorError(f"agent {entry['agent_name']} is {agent_status}; cannot close yet")
        pane_id = entry["pane_id"]
        _run_herdr(["pane", "close", pane_id], timeout=60)
        # Verify removal.
        pane_gone = not _pane_exists(pane_id)
        agent_gone = True
        try:
            _run_herdr(["agent", "get", entry["agent_name"]])
            agent_gone = False
        except OrchestratorError:
            agent_gone = True
        if not (pane_gone and agent_gone):
            raise OrchestratorError(
                f"close verification failed for task {task_id}: pane_gone={pane_gone}, agent_gone={agent_gone}")
        entry["keep_open"] = False
        entry["close_reason"] = close_reason
        entry["closed_at"] = time.time()
        state.setdefault("closed", {})[task_id] = entry
        state.get("agents", {}).pop(task_id, None)
        _save_state(state)
    return json.dumps({
        "task_id": task_id,
        "closed": True,
        "pane_id": pane_id,
        "close_reason": close_reason,
        "evidence_summary": evidence_summary,
    })



def _handle_list_agents(args, **kwargs):
    with _StateLock():
        state = _load_state()
        agents = {}
        for task_id, entry in list(state.get("agents", {}).items()):
            live = _active_entry(state, task_id)
            if live is None:
                agents[task_id] = {"task_id": task_id, "status": "stale", "registered": entry}
            else:
                agent_status, _ = _live_agent_status(live["agent_name"])
                agents[task_id] = {
                    "task_id": task_id,
                    "profile": live["profile"],
                    "agent_name": live["agent_name"],
                    "pane_id": live["pane_id"],
                    "agent_status": agent_status,
                    "status": "active",
                }
        _save_state(state)
    return json.dumps({"agents": agents, "project_root": str(_project_root())})


def register(ctx):
    global CTX
    CTX = ctx
    from . import schemas

    tools = [
        ("agent_catalog", schemas.AGENT_CATALOG, _handle_catalog),
        ("agent_start", schemas.AGENT_START, _handle_start),
        ("agent_prompt", schemas.AGENT_PROMPT, _handle_prompt),
        ("agent_wait", schemas.AGENT_WAIT, _handle_wait),
        ("agent_status", schemas.AGENT_STATUS, _handle_status),
        ("agent_close", schemas.AGENT_CLOSE, _handle_close),
        ("agent_list", schemas.AGENT_LIST, _handle_list_agents),
    ]
    for name, schema, handler in tools:
        ctx.register_tool(name=name, toolset="orchestrator", schema=schema, handler=handler)