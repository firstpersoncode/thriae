# Project Implementation Plan

## 1. Plan Metadata

- **Plan owner:** Lead (planning agent)
- **Source of truth:** `.hermes/project/` (PRD.md, ARCHITECTURE.md, TECHNICAL_SPEC.md, README.md)
- **Roadmap source:** `.hermes/memories/ROADMAP.md` is currently `NOT_YET_GENERATED`; no canonical roadmap document exists under `.hermes/project/`. This plan defines the first eligible milestone directly from the verified product documentation. The missing roadmap is recorded as an unresolved planning gap.
- **Active milestone:** M1 only. No future milestone is planned by this document.

## 2. Current State Reconciliation Summary

- Repository contains no application source code initially. Only workflow documentation, project documentation, and agent configuration exist.
- `.hermes/memories/PLANS.md` was empty and has been populated with M1.
- `.hermes/memories/PROGRESS.md` initialized by Lead.
- Kanban board (`thriae`) used for task orchestration; state may be reset/lost due to scratch cleanup, but implementation commits preserve progress.
- Git branch is `master`.
- Python 3.14.9 available, satisfying CALC-C-001.
- No external dependencies required (CALC-C-002).

## 3. Milestone M1 — Simple Calculator Implementation

### 3.1 Milestone Metadata

- **Milestone ID:** M1
- **Name:** Simple Calculator Implementation
- **Objective:** Implement the documented local Python command-line calculator: pure arithmetic core, package-level public API, an `argparse`-based CLI adapter, and concise user-facing documentation, satisfying PRD, Architecture, and Technical Specification.
- **Expected outcome:** A user can run `python3 -m calculator <operation> <left> <right>` for `add`, `subtract`, `multiply`, and `divide`, receiving `str(result)` plus one newline on stdout and exit code 0 for valid finite inputs; invalid input and arithmetic failures produce documented stderr and exit codes; the same operations are importable from `calculator` and `calculator.operations`.
- **Scope included:**
  - `calculator/operations.py` arithmetic core and finite validation.
  - `calculator/__init__.py` public API exports.
  - `calculator/__main__.py` CLI adapter, argument parsing, exit codes, stdout/stderr behavior.
  - User-facing documentation content required by TECHNICAL_SPEC.md section 6.
- **Scope excluded (product non-goals, not deferred work):**
  - GUI/web/desktop/mobile interfaces, interactive REPL, expression parsing, more than two operands, precedence, variables, functions, history, memory, configuration, localization, plugins, exact decimal/arbitrary precision/symbolic arithmetic, publishing or service deployment (PRD.md section 6).
- **Dependencies:** Python 3.11+ standard library only.
- **Completion criteria:**
  1. All M1 phases and planner TODO items are implemented and validated.
  2. Documented CLI examples produce the exact specified stdout/stderr and exit codes.
  3. API behavior matches TECHNICAL_SPEC.md section 2.
  4. Independent review of the exact candidate commit is approved.
  5. Required PR against `master` is created and merged (or otherwise explicitly integrated) and the integrated result is verified in `master`.
- **Known risks / unresolved decisions:**
  1. The repository location for user-facing documentation is not specified by ARCHITECTURE.md (runtime modules are only `calculator/*`). Resolution: choose a documentation file location consistent with repository conventions; record the decision before implementation. This does not block Phase 1 or Phase 2.
  2. No canonical roadmap document exists; milestone sequencing is based on product documentation only. If a roadmap is later generated, M1 eligibility must be rechecked against it.

### 3.2 Phase M1-P1 — Arithmetic Core and Public API

- **Phase ID:** M1-P1
- **Name:** Arithmetic Core and Public API
- **Objective:** Implement the pure arithmetic core with finite-input and finite-result validation and expose the four operations at the package root.
- **Scope and boundaries:** `calculator/operations.py` and `calculator/__init__.py` only. No CLI, printing, parsing, process exit, file, network, or stateful behavior.
- **Dependencies / prerequisites:** Python 3.11+ standard library.
- **Expected deliverables:** Four arithmetic functions returning `float`, finite validation, zero-division handling, package exports.
- **Validation requirements:** Direct Python calls for valid finite inputs, non-finite operand rejection, non-finite result rejection, division by zero; type/behavior checks per TECHNICAL_SPEC.md section 2.
- **Exit criteria:** API behavior matches TECHNICAL_SPEC.md section 2 and ARCHITECTURE.md sections 3 and 5.

#### Planner TODO Items

##### M1-P1-T1 — Implement finite validation and four arithmetic operations

- **Identifier:** M1-P1-T1
- **Title:** Implement arithmetic operations with finite validation
- **Objective:** Provide `add`, `subtract`, `multiply`, and `divide` that accept valid finite `int` or `float` operands, perform floating-point arithmetic, and reject non-finite operands/results and zero divisors with the specified exceptions.
- **Scope:** `calculator/operations.py`; shared internal finite-number validation used by all four operations (ARCHITECTURE.md section 3).
- **Requirements:** CALC-F-001, CALC-F-003, CALC-F-006, CALC-C-003, CALC-C-004; TECHNICAL_SPEC.md section 2.
- **Documentation references:** `.hermes/project/PRD.md` sections 4 and 5; `.hermes/project/ARCHITECTURE.md` sections 3 and 5; `.hermes/project/TECHNICAL_SPEC.md` section 2.
- **Existing implementation:** Implemented (commit de594df).
- **Implementation approach:** Create `calculator/operations.py` with a shared validation helper for finite `int`/`float` operands and finite results. `add`, `subtract`, `multiply` perform the operation and validate the result. `divide` validates operands, rejects zero divisor with `ZeroDivisionError("cannot divide by zero")`, performs division, and validates the result. Non-finite operands raise `ValueError`; non-finite results raise `OverflowError("result must be finite")`.
- **Dependencies:** None.
- **Validation requirements:** Python import and direct calls: valid finite cases; `ValueError` for NaN/inf operands; `OverflowError("result must be finite")` for non-finite results; `ZeroDivisionError("cannot divide by zero")` for zero divisor; functions return `float`.
- **Acceptance criteria:**
  1. `add`, `subtract`, `multiply`, `divide` are available from `calculator.operations`.
  2. Each returns a `float` for valid finite `int`/`float` inputs.
  3. Non-finite operands raise `ValueError`.
  4. Non-finite results raise `OverflowError` with message `result must be finite`.
  5. Division by zero raises `ZeroDivisionError` with message `cannot divide by zero`.
  6. Arithmetic module does not import CLI, print, parse, exit, read files, access network, or retain state.
- **Status:** Regressed (removed from HEAD by fdc668e; restore required)
- **Notes and risks:** Type handling for non-`int`/`float` is outside the public contract (ARCHITECTURE.md section 3). Do not add unnecessary abstraction or exception hierarchy (ARCHITECTURE.md section 6).

##### M1-P1-T2 — Expose public arithmetic API at package root

- **Identifier:** M1-P1-T2
- **Title:** Expose four arithmetic functions from the package root
- **Objective:** Make `add`, `subtract`, `multiply`, and `divide` importable from both `calculator` and `calculator.operations`.
- **Scope:** `calculator/__init__.py`.
- **Requirements:** CALC-F-001; TECHNICAL_SPEC.md section 2.
- **Documentation references:** `.hermes/project/ARCHITECTURE.md` section 2; `.hermes/project/TECHNICAL_SPEC.md` section 2.
- **Existing implementation:** Implemented (commit 58d46e9).
- **Implementation approach:** Import the four functions from `.operations` into `calculator/__init__.py` and define `__all__`. Avoid circular imports; arithmetic must not import CLI.
- **Dependencies:** M1-P1-T1.
- **Validation requirements:** `from calculator import add, subtract, multiply, divide` and `from calculator.operations import ...` succeed; both refer to the same callables.
- **Acceptance criteria:**
  1. Public functions are available from both `calculator` and `calculator.operations`.
  2. No CLI dependency is introduced into the arithmetic or package init path.
- **Status:** Regressed (removed from HEAD by fdc668e; restore required)
- **Notes and risks:** None.

### 3.3 Phase M1-P2 — CLI Adapter

- **Phase ID:** M1-P2
- **Name:** Command-Line Adapter
- **Objective:** Implement the terminal interface that parses one operation and two operands, invokes the arithmetic core once, and produces documented stdout, stderr, and exit codes.
- **Scope and boundaries:** `calculator/__main__.py` only. Uses `argparse` and `math`; no `eval`, shell construction, or dynamic expression evaluation.
- **Dependencies / prerequisites:** M1-P1 complete.
- **Expected deliverables:** Executable `python3 -m calculator` interface with documented grammar, output, errors, and exit codes.
- **Validation requirements:** Invoke documented commands and compare stdout/stderr/exit codes to TECHNICAL_SPEC.md sections 4 and 5.
- **Exit criteria:** CLI behavior matches TECHNICAL_SPEC.md sections 3, 4, and 5 and ARCHITECTURE.md section 4.

#### Planner TODO Items

##### M1-P2-T1 — Implement argparse CLI with documented behavior

- **Identifier:** M1-P2-T1
- **Title:** Implement command-line adapter
- **Objective:** Parse `python3 -m calculator {add,subtract,multiply,divide} left right`, convert operands to finite floats, call the selected arithmetic function exactly once, and translate results/failures into documented terminal behavior.
- **Scope:** `calculator/__main__.py`.
- **Requirements:** CALC-F-002, CALC-F-004, CALC-F-005, CALC-F-006, CALC-C-003, CALC-C-006; TECHNICAL_SPEC.md sections 3, 4, 5.
- **Documentation references:** `.hermes/project/PRD.md` sections 3, 4, 5; `.hermes/project/ARCHITECTURE.md` sections 4, 5; `.hermes/project/TECHNICAL_SPEC.md` sections 3, 4, 5.
- **Existing implementation:** Implemented (commits 0557a21, 7acf834); removed from HEAD by fdc668e. Restore required.
- **Implementation approach:** Use `argparse` with a choices operation and two positional operands. Convert tokens using Python float syntax, rejecting malformed and non-finite tokens as usage errors (exit code 2). Call the selected arithmetic function exactly once. On success print `str(result)` plus one newline to stdout and return 0. On expected arithmetic failure (`ZeroDivisionError`, `OverflowError`) print exactly `error: <message>` to stderr and return 1. Usage failures rely on argparse (exit code 2, no traceback). `--help` prints help and returns 0.
- **Dependencies:** M1-P1-T1, M1-P1-T2.
- **Validation requirements:** Run all examples in TECHNICAL_SPEC.md sections 4 and 5; verify stdout/stderr/exit codes; verify no traceback; verify `--help`.
- **Acceptance criteria:**
  1. Grammar `python3 -m calculator {add,subtract,multiply,divide} left right` is enforced.
  2. Unknown operations, missing/extra arguments, malformed tokens are usage errors with exit code 2 and no application traceback.
  3. Tokens resolving to NaN or infinity are usage errors with exit code 2 and stderr containing `finite`.
  4. Valid invocations print exactly `str(result)` plus one newline to stdout, nothing to stderr, exit code 0.
  5. Division by zero prints exactly `error: cannot divide by zero\n` to stderr, empty stdout, exit code 1.
  6. Non-finite result prints exactly `error: result must be finite\n` to stderr, empty stdout, exit code 1.
  7. `--help` prints help including operation names to stdout and exits 0.
  8. CLI does not use `eval`, shell construction, or dynamic expression evaluation.
- **Status:** Regressed (removed from HEAD by fdc668e; restore required)
- **Notes and risks:** Error ownership per ARCHITECTURE.md section 5. Current implementation includes extra patch-resolution logic; review should assess whether it is necessary or should be simplified.

### 3.4 Phase M1-P3 — User-Facing Documentation

- **Phase ID:** M1-P3
- **Name:** User-Facing Documentation
- **Objective:** Provide concise user documentation covering commands, examples, errors, and exit codes, consistent with the specification.
- **Scope and boundaries:** User-facing documentation content only. No changes to runtime behavior.
- **Dependencies / prerequisites:** M1-P2 complete (soft dependency for examples and messages).
- **Expected deliverables:** Documentation satisfying TECHNICAL_SPEC.md section 6.
- **Validation requirements:** Examples and messages in documentation agree with TECHNICAL_SPEC.md sections 4 and 5.
- **Exit criteria:** Documentation content requirements in TECHNICAL_SPEC.md section 6 are satisfied.

#### Planner TODO Items

##### M1-P3-T1 — Add user-facing documentation

- **Identifier:** M1-P3-T1
- **Title:** Add concise user documentation
- **Objective:** Document Python 3.11+ and installation-free usage, command grammar and operation names, at least one successful example with expected output per operation, usage vs arithmetic errors and exit codes, division-by-zero and finite-number behavior, and non-goals.
- **Scope:** User-facing documentation content. Exact file location unresolved (M1-R1); likely a repository documentation file or CLI help text, but runtime modules remain `calculator/*`.
- **Requirements:** CALC-F-007; TECHNICAL_SPEC.md section 6.
- **Documentation references:** `.hermes/project/PRD.md` section 4 (CALC-F-007); `.hermes/project/TECHNICAL_SPEC.md` section 6; `.hermes/project/ARCHITECTURE.md` section 2.
- **Existing implementation:** None.
- **Implementation approach:** Create or update user-facing documentation with the required content. Ensure examples and messages exactly match TECHNICAL_SPEC.md. If documentation is placed in a new file, keep it outside runtime modules; do not alter the three-module runtime architecture.
- **Dependencies:** M1-P2-T1 (soft).
- **Validation requirements:** Compare documented examples/messages to TECHNICAL_SPEC.md sections 4 and 5; execute documented examples.
- **Acceptance criteria:**
  1. Documentation states Python 3.11+ and installation-free usage.
  2. Documents command grammar and all four operation names.
  3. Contains at least one successful example with expected output for each operation.
  4. Explains usage errors vs arithmetic errors and exit codes.
  5. Documents division-by-zero and finite-number behavior.
  6. States non-goals of interactive expression evaluation and advanced calculator features.
  7. Examples and messages agree with the specification.
- **Status:** Implemented in a648ee2 (USAGE.md remains); calculator package removed by fdc668e; restore and validate required
- **Notes and risks:** Unresolved decision M1-R1 regarding documentation file location.

## 4. Phase Ordering and Dependencies

1. M1-P1 (Arithmetic Core and Public API) complete.
2. M1-P2 (CLI Adapter) implemented and needs commit/validation.
3. M1-P3 (User-Facing Documentation) pending.

Recommended execution order: M1-P1 (done) → M1-P2 (commit/validate) → M1-P3 → review.

## 5. Blocker Register (Planning)

- **M1-R1 (WAITING_OWNER):** User-facing documentation file location is unspecified by architecture. Owner: user/Lead decision. Required before M1-P3 implementation if a file location cannot be inferred. Impact: M1-P3 only. Unblock: choose documentation location consistent with repository conventions.
- **M1-R2 (OPEN):** Canonical roadmap absent (`ROADMAP.md` not generated; no `6.RoadMap.md` in `.hermes/project/`). Owner: Lead. Impact: milestone eligibility cannot be verified against a roadmap. Unblock: generate or locate roadmap, or proceed with documentation-derived milestone M1 with this gap recorded.
- **M1-R3 (OPEN):** Kanban task state has been lost/reset during scratch cleanup, but implementation commits preserve progress. Lead recreated tracking tasks; orchestration state may be incomplete. Impact: task auditability. Unblock: continue using commits and PROGRESS.md as evidence.
- **M1-R4 (WAITING_OWNER/ENV):** Lead session launched without `HERMES_KANBAN_HOME`, `HERMES_KANBAN_BOARD`, or `HERDR_PANE_ID`. `calculator/` removed from HEAD by `fdc668e`. Owner: user/environment. Impact: cannot seed/run Kanban agents or implementation safely. Unblock: relaunch via `Start-Agents.sh` (exports env and starts Herdr) or export the variables, then restore `calculator/` from `a648ee2`.

## 6. Out of Scope for M1

All items listed in PRD.md section 6 are product non-goals, not deferred work. They must not be implemented or planned as future phases unless the user explicitly changes product scope.
