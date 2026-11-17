"""Command-line adapter for the calculator package.

This module owns argument parsing, operation selection, process exit codes,
stdout, and stderr. It imports and calls the arithmetic core; it never
evaluates input as code or builds a shell command.
"""

import argparse
import math
import sys

from . import operations as _operations

_OPERATION_NAMES = ("add", "subtract", "multiply", "divide")

_OPERATIONS = {
    "add": _operations.add,
    "subtract": _operations.subtract,
    "multiply": _operations.multiply,
    "divide": _operations.divide,
}


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


def main(argv=None):
    parser = argparse.ArgumentParser(prog="python -m calculator")
    parser.add_argument("operation", choices=_OPERATION_NAMES)
    parser.add_argument("left", type=_parse_number)
    parser.add_argument("right", type=_parse_number)

    args = parser.parse_args(argv)

    try:
        result = _OPERATIONS[args.operation](args.left, args.right)
    except (ZeroDivisionError, OverflowError, ValueError) as exc:
        print("error: {}".format(exc), file=sys.stderr)
        return 1

    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
