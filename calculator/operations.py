"""Pure arithmetic core for the calculator package.

Each function accepts finite ``int`` or ``float`` operands, performs
floating-point arithmetic, and returns a ``float``. Non-finite operands
raise ``ValueError``. A non-finite arithmetic result raises
``OverflowError`` with the message ``result must be finite``. Division
by zero raises ``ZeroDivisionError`` with the message ``cannot divide
by zero``.

These functions perform arithmetic only: they do not print, parse
command-line strings, exit the process, read files, access the network,
or retain state between calls.
"""

import math

__all__ = ["add", "subtract", "multiply", "divide"]


def _require_finite_operands(a, b):
    """Raise ``ValueError`` unless both operands are finite numbers."""
    if not math.isfinite(a) or not math.isfinite(b):
        raise ValueError("operands must be finite")


def _finite_result(value):
    """Return ``value`` as ``float``, rejecting a non-finite result."""
    if not math.isfinite(value):
        raise OverflowError("result must be finite")
    return float(value)


def add(a, b):
    """Return ``a + b`` as a float for finite operands."""
    _require_finite_operands(a, b)
    return _finite_result(float(a) + float(b))


def subtract(a, b):
    """Return ``a - b`` as a float for finite operands."""
    _require_finite_operands(a, b)
    return _finite_result(float(a) - float(b))


def multiply(a, b):
    """Return ``a * b`` as a float for finite operands."""
    _require_finite_operands(a, b)
    return _finite_result(float(a) * float(b))


def divide(a, b):
    """Return ``a / b`` as a float, rejecting a zero divisor."""
    _require_finite_operands(a, b)
    if b == 0:
        raise ZeroDivisionError("cannot divide by zero")
    return _finite_result(float(a) / float(b))
