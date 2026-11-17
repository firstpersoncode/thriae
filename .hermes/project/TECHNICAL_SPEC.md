# Simple Calculator: Technical Specification

## 1. Runtime and Entry Point

- Python 3.11 or newer.
- Python standard-library runtime only.
- Invoked from the repository root with `python3 -m calculator`.
- One process performs one calculation and exits; no REPL is provided.

## 2. Arithmetic API

The public functions are available from both `calculator` and `calculator.operations`:

```python
add(a, b)
subtract(a, b)
multiply(a, b)
divide(a, b)
```

For valid finite `int` or `float` inputs:

| Function | Result |
|---|---|
| `add(a, b)` | Floating-point addition with finite-result validation. |
| `subtract(a, b)` | Floating-point subtraction with finite-result validation. |
| `multiply(a, b)` | Floating-point multiplication with finite-result validation. |
| `divide(a, b)` | Floating-point division with zero-divisor and finite-result validation. |

Every function rejects NaN and either infinity in an operand with `ValueError`. A non-finite arithmetic result raises `OverflowError` with message `result must be finite`. Division by zero raises `ZeroDivisionError` with message `cannot divide by zero`.

Internal helpers and type annotations are implementation details; public behavior is contractual.

## 3. Command-Line Grammar

```text
python3 -m calculator {add,subtract,multiply,divide} left right
```

- `left` and `right` use Python-compatible finite float syntax, including negative and scientific-notation values.
- Unknown operations, missing arguments, extra arguments, and malformed numeric tokens are usage errors.
- Tokens resolving to NaN or either infinity are also usage errors.
- Operands are treated exclusively as values, never executable source or shell syntax.

## 4. Successful Results

A successful command writes exactly `str(result)` plus one newline to stdout, writes nothing to stderr, and exits 0.

| Invocation | stdout | Exit code |
|---|---|---|
| `python3 -m calculator add 2 3` | `5.0\n` | 0 |
| `python3 -m calculator subtract 5 -2` | `7.0\n` | 0 |
| `python3 -m calculator multiply -4 2.5` | `-10.0\n` | 0 |
| `python3 -m calculator divide 5 2` | `2.5\n` | 0 |
| `python3 -m calculator add 1e2 0.5` | `100.5\n` | 0 |

No formatting beyond `str(result)` is provided.

## 5. Failures and Exit Codes

| Case | stdout | stderr | Exit code |
|---|---|---|---|
| Success | Result plus newline. | Empty. | 0 |
| `--help` | Help including operation names. | Empty. | 0 |
| Missing or extra arguments, unknown operation, malformed numeric token | Empty. | `argparse` usage/error output, no application traceback. | 2 |
| Non-finite numeric token | Empty. | Usage/error output containing `finite`, no application traceback. | 2 |
| Division by zero | Empty. | Exactly `error: cannot divide by zero\n`. | 1 |
| Non-finite arithmetic result | Empty. | Exactly `error: result must be finite\n`. | 1 |

Expected failures do not expose a Python traceback.

## 6. User Documentation Content

The calculator's user-facing documentation contains:

1. Python 3.11+ and installation-free usage.
2. The command grammar and all four operation names.
3. At least one successful example with expected output for each operation.
4. The difference between usage errors and arithmetic errors, including exit codes.
5. Division-by-zero and finite-number behavior.
6. The non-goals of interactive expression evaluation and advanced calculator features.

Its examples and messages must agree with this specification.

## 7. Product Constraints

The runtime does not use `eval`, `exec`, network access, file persistence, subprocesses, or third-party imports. It has no hidden configuration and retains no user data between invocations.
