# Simple Calculator: Architecture

## 1. Architectural Shape

The application is a local Python package with two boundaries:

1. A pure arithmetic core accepting and returning Python numbers.
2. A CLI adapter translating command-line arguments into one arithmetic call and translating the result or failure into terminal behavior.

There is no service, global application object, plugin system, persistence layer, or dependency-injection framework.

## 2. Runtime Modules

```text
calculator/
  __init__.py
  __main__.py
  operations.py
```

Responsibilities:

- `calculator/operations.py` owns arithmetic and finite-number/result validation.
- `calculator/__init__.py` exposes the four public arithmetic functions at the package root.
- `calculator/__main__.py` owns argument parsing, operation selection, process exit codes, stdout, and stderr.

Arithmetic does not depend on the CLI module. The CLI imports and calls arithmetic; arithmetic never imports the CLI.

## 3. Arithmetic Core

The arithmetic core exports:

```python
add(a, b)
subtract(a, b)
multiply(a, b)
divide(a, b)
```

Each function accepts valid finite `int` or `float` operands and returns a `float`. Other Python types are outside the public contract. Every operation validates finite inputs and a finite result. `divide` also rejects a zero divisor.

Arithmetic functions do not print, parse CLI strings, exit the process, read files, access the network, or retain state between calls.

One shared internal validation approach is preferable to four divergent implementations of finite-number rules.

## 4. CLI Data Flow

1. `argparse` reads an operation name and two positional operands.
2. Numeric conversion rejects malformed and non-finite operands as usage errors.
3. The adapter calls the selected arithmetic function exactly once. It does not use `eval`, a shell, or dynamic expression evaluation.
4. On success, the adapter writes `str(result)` plus one newline to stdout and returns exit code 0.
5. Expected arithmetic failures become one `error: <message>` line on stderr and exit code 1.
6. Usage failures return exit code 2 through `argparse` without an application traceback.
7. `--help` writes help to stdout and returns exit code 0.

## 5. Error Ownership

- Unknown operations, incorrect argument counts, and malformed or non-finite numeric tokens belong to argument validation.
- Non-finite operands and results passed to or produced by the API belong to the arithmetic core.
- Division by zero belongs to `divide`.
- The CLI translates expected core failures into documented terminal behavior.

Normal control flow does not use exceptions beyond these defined boundaries. Unexpected programming defects must not be presented as successful calculations or silently ignored.

## 6. Dependency Policy

The runtime uses Python standard-library facilities such as `argparse` and `math`. The product does not need a result wrapper, exception hierarchy, dependency container, plugin registry, parser framework, database abstraction, or numerical package.

## 7. Data and Security Boundaries

Runtime inputs are an operation name and two operands. Runtime outputs are stdout, stderr, and a process exit code. Nothing is persisted between invocations.

Input is data only. The application never evaluates it as source code and never builds a shell command from it.
