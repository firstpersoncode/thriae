# Usage

This document is the user-facing guide for the simple calculator. It is separate from
the workflow documentation in `README.md`.

## Requirements

- Python 3.11 or newer.
- No installation is required. The calculator uses only the Python standard library.
- Run commands from the repository root.

## Command Grammar

```text
python3 -m calculator {add,subtract,multiply,divide} left right
```

- `<operation>` must be one of `add`, `subtract`, `multiply`, or `divide`.
- `<left>` and `<right>` use Python-compatible finite float syntax, including negative
  and scientific-notation values (for example, `-2`, `2.5`, `1e2`).
- One process performs one calculation and exits. There is no interactive prompt,
  REPL, or expression parser.
- Operands are treated as data values only. They are never evaluated as Python code
  or interpolated into a shell command.

## Operations

| Operation | Meaning |
|---|---|
| `add` | `left + right` |
| `subtract` | `left - right` |
| `multiply` | `left * right` |
| `divide` | `left / right` |

## Successful Examples

Each successful command writes exactly `str(result)` plus one newline to stdout,
writes nothing to stderr, and exits with status `0`.

```text
$ python3 -m calculator add 2 3
5.0

$ python3 -m calculator subtract 5 -2
7.0

$ python3 -m calculator multiply -4 2.5
-10.0

$ python3 -m calculator divide 5 2
2.5

$ python3 -m calculator add 1e2 0.5
100.5
```

No formatting beyond `str(result)` is provided.

## Python API

The same operations are available without the command line:

```python
from calculator import add, subtract, multiply, divide

add(2, 3)        # 5.0
subtract(5, -2)  # 7.0
multiply(-4, 2.5)  # -10.0
divide(5, 2)     # 2.5
```

Each function accepts finite `int` or `float` operands and returns a `float`.

## Errors and Exit Codes

| Case | stdout | stderr | Exit code |
|---|---|---|---|
| Success | Result plus newline. | Empty. | `0` |
| `--help` | Help including operation names. | Empty. | `0` |
| Missing or extra arguments, unknown operation, malformed numeric token | Empty. | `argparse` usage/error output, no application traceback. | `2` |
| Non-finite numeric token | Empty. | Usage/error output containing `finite`, no application traceback. | `2` |
| Division by zero | Empty. | Exactly `error: cannot divide by zero\n`. | `1` |
| Non-finite arithmetic result | Empty. | Exactly `error: result must be finite\n`. | `1` |

### Usage Errors (exit code 2)

Usage errors come from argument validation and include unknown operations, missing or
extra arguments, malformed numeric tokens, and tokens that resolve to `NaN` or
infinity. They produce `argparse` usage/error output on stderr, contain no
application traceback, leave stdout empty, and exit with status `2`.

### Arithmetic Errors (exit code 1)

Arithmetic errors come from the calculation itself. They produce one line on stderr,
leave stdout empty, and exit with status `1`:

- Division by zero: `error: cannot divide by zero`
- A non-finite arithmetic result: `error: result must be finite`

## Division by Zero and Finite Numbers

- A divisor of zero raises `ZeroDivisionError` with the message `cannot divide by
  zero`. Through the CLI this becomes `error: cannot divide by zero` on stderr with
  exit code `1`.
- Operands must be finite. Tokens resolving to `NaN` or either infinity are rejected
  as usage errors (exit code `2`) with stderr containing `finite`.
- In the Python API, non-finite operands raise `ValueError` with the message
  `operands must be finite`, and a non-finite arithmetic result raises
  `OverflowError` with the message `result must be finite`.
- Only finite results are returned; an overflow that produces infinity or `NaN` is
  reported as `error: result must be finite` (exit code `1`).

## Non-Goals

This calculator intentionally does not provide:

- A GUI, web, desktop, or mobile interface.
- An interactive REPL or expression parsing.
- More than two operands, precedence, parentheses, variables, or functions.
- History, memory keys, configuration files, localization, or plugins.
- Exact decimal, arbitrary-precision, or symbolic arithmetic.
- Package-registry publishing or deployment to a service.

These are product non-goals, not deferred features.
