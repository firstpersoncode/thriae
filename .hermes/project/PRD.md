# Simple Calculator: Product Requirements

## 1. Product Overview

A small command-line calculator performs one arithmetic operation on two numeric operands per invocation. It provides a reusable Python arithmetic API and a terminal interface with predictable output and errors.

The product values simplicity, portability, and clarity over extensibility.

## 2. Target User and Use Cases

The target user is a developer or terminal user who needs quick arithmetic without starting an interactive program.

Primary use cases:

1. Add, subtract, multiply, or divide two numbers from a shell.
2. Use the same arithmetic operations from another Python module.
3. Understand a failed invocation from a concise error and process exit code.

## 3. User Interaction

The user invokes the calculator from the repository root:

```bash
python3 -m calculator <operation> <left> <right>
```

Available operation names are `add`, `subtract`, `multiply`, and `divide`.

Examples:

```bash
python3 -m calculator add 2 3
python3 -m calculator subtract 5 -2
python3 -m calculator divide 5 2
```

Each invocation performs one calculation and exits. There is no interactive prompt.

## 4. Functional Requirements

| ID | Requirement |
|---|---|
| CALC-F-001 | Provide addition, subtraction, multiplication, and division through a reusable Python API. |
| CALC-F-002 | Expose all four operations through `python3 -m calculator` with exactly two operands. |
| CALC-F-003 | Return mathematically correct floating-point results for valid finite inputs. |
| CALC-F-004 | Print successful results with `str(result)` followed by one newline and no stderr output. |
| CALC-F-005 | Reject malformed invocations, invalid numeric input, non-finite values, and arithmetic failures without an application traceback. |
| CALC-F-006 | Reject division by zero with a concise user-facing error. |
| CALC-F-007 | Provide concise user documentation covering commands, examples, errors, and exit codes. |

`TECHNICAL_SPEC.md` defines the exact API, output, errors, and exit codes required by these features.

## 5. Product Constraints

| ID | Constraint |
|---|---|
| CALC-C-001 | Support Python 3.11 or newer. |
| CALC-C-002 | Use only the Python standard library at runtime. |
| CALC-C-003 | Keep arithmetic separate from argument parsing and terminal I/O. |
| CALC-C-004 | Accept only finite numeric operands and produce only finite results. |
| CALC-C-005 | Require no network service, database, account, persistent state, or background process. |
| CALC-C-006 | Never evaluate input as Python code or interpolate it into a shell command. |

## 6. Scope Boundaries

The product includes four binary arithmetic operations, one-shot CLI execution, and user documentation.

It does not include:

- GUI, web, desktop, or mobile interfaces.
- Interactive REPL or expression parsing.
- More than two operands, precedence, parentheses, variables, or functions.
- History, memory keys, configuration files, localization, or plugins.
- Exact decimal, arbitrary-precision, or symbolic arithmetic.
- Package-registry publishing or deployment to a service.

These are product non-goals, not deferred work awaiting implementation.

## 7. User-Facing Outcome

A user can perform basic arithmetic from the command line or Python, receive consistent results, and distinguish input mistakes from arithmetic failures. A user who needs expression parsing, persistent history, or a graphical interface is outside this product's intended scope.
