"""Command-line adapter for the calculator package.

Parses one operation name and two numeric operands, calls the selected
arithmetic function from ``calculator.operations`` exactly once, and
translates the result or failure into documented terminal behavior:

- Success: ``str(result)`` plus one newline on stdout, exit code 0.
- Expected arithmetic failure (``ZeroDivisionError``, ``OverflowError``):
  one ``error: <message>`` line on stderr, exit code 1.
- Usage failure: ``argparse`` usage/error output, exit code 2.

Operands are treated exclusively as values; this adapter never uses
``eval``, builds a shell command, or dynamically evaluates input.
"""

import argparse
import math
import sys

from .operations import add, divide, multiply, subtract

OPERATIONS = {
    "add": add,
    "subtract": subtract,
    "multiply": multiply,
    "divide": divide,
}


def _finite_operand(token):
    """Convert a command-line token to a finite ``float`` operand.

    Malformed numeric tokens and tokens resolving to NaN or either
    infinity are usage errors (``argparse`` exits with code 2).
    """
    try:
        value = float(token)
    except ValueError:
        raise argparse.ArgumentTypeError(
            f"{token!r} is not a valid number"
        ) from None
    if not math.isfinite(value):
        raise argparse.ArgumentTypeError(
            f"operand must be finite (got {token!r})"
        )
    return value


def _normalize_operands(tokens):
    """Present negative operand tokens to argparse as positionals.

    ``argparse`` treats ``-``-prefixed tokens that do not match its
    negative-number heuristic (for example ``-1e2`` or ``-inf``) as
    unknown options. The CLI grammar has no options besides
    ``-h``/``--help``, so once the operation name is read, any later
    ``-``-prefixed token is an operand value; an explicit ``--``
    terminator makes argparse treat the remaining tokens as positionals.
    """
    if not tokens or tokens[0] not in OPERATIONS:
        return tokens
    if any(
        token.startswith("-") and token not in ("-h", "--help")
        for token in tokens[1:]
    ):
        return [tokens[0], "--", *tokens[1:]]
    return tokens


def main(argv=None):
    """Run one calculation and return the process exit code."""
    parser = argparse.ArgumentParser(
        prog="calculator",
        description="Perform one arithmetic operation on two numbers.",
    )
    parser.add_argument(
        "operation",
        choices=list(OPERATIONS),
        help="arithmetic operation to perform",
    )
    parser.add_argument(
        "left",
        type=_finite_operand,
        help="first operand (finite number)",
    )
    parser.add_argument(
        "right",
        type=_finite_operand,
        help="second operand (finite number)",
    )
    if argv is None:
        argv = sys.argv[1:]
    args = parser.parse_args(_normalize_operands(list(argv)))

    operation = OPERATIONS[args.operation]
    try:
        result = operation(args.left, args.right)
    except (ZeroDivisionError, OverflowError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    print(result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
