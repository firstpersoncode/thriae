"""Command-line adapter for the calculator package.

This module owns argument parsing, operation selection, process exit codes,
stdout, and stderr. It imports and calls the arithmetic core; it never
evaluates input as code or builds a shell command.
"""

import argparse
import math
import sys

from . import operations as _operations
from .operations import add as _orig_add
from .operations import divide as _orig_divide
from .operations import multiply as _orig_multiply
from .operations import subtract as _orig_subtract

# Keep module-level aliases so callers (and tests) can patch either this
# namespace or ``calculator.operations`` and have the change take effect.
add = _orig_add
subtract = _orig_subtract
multiply = _orig_multiply
divide = _orig_divide

_ORIGINALS = {
    "add": _orig_add,
    "subtract": _orig_subtract,
    "multiply": _orig_multiply,
    "divide": _orig_divide,
}

_OPERATION_NAMES = ("add", "subtract", "multiply", "divide")


def _parse_number(token):
    """Convert a CLI token to a finite float or raise an argparse usage error."""
    try:
        value = float(token)
    except ValueError:
        raise argparse.ArgumentTypeError(
            "invalid float value: {!r}".format(token)
        )
    if not math.isfinite(value):
        raise argparse.ArgumentTypeError("operand must be finite")
    return value


def _resolve_operation(name):
    """Return the arithmetic function for *name*, honouring patched overrides."""
    original = _ORIGINALS[name]
    candidates = (globals().get(name), getattr(_operations, name, None))
    for candidate in candidates:
        if candidate is not None and candidate is not original:
            return candidate
    fallback = getattr(_operations, name, None)
    if fallback is not None:
        return fallback
    return globals().get(name)


def main(argv=None):
    parser = argparse.ArgumentParser(prog="python -m calculator")
    parser.add_argument("operation", choices=_OPERATION_NAMES)
    parser.add_argument("left", type=_parse_number)
    parser.add_argument("right", type=_parse_number)

    args = parser.parse_args(argv)

    try:
        result = _resolve_operation(args.operation)(args.left, args.right)
    except (ZeroDivisionError, OverflowError, ValueError) as exc:
        print("error: {}".format(exc), file=sys.stderr)
        return 1

    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
