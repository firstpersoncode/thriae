"""Pure arithmetic core with finite-number validation.

This module owns arithmetic and finite-number/result validation. It does not
depend on the CLI, perform I/O, or retain state.
"""

import math


def _validate_operand(value):
    """Raise ValueError unless value is a finite int or float."""
    if not isinstance(value, (int, float)):
        raise ValueError("operand must be finite")
    if not math.isfinite(value):
        raise ValueError("operand must be finite")


def _validate_result(value):
    """Raise OverflowError unless value is finite."""
    if not math.isfinite(value):
        raise OverflowError("result must be finite")


def add(a, b):
    _validate_operand(a)
    _validate_operand(b)
    result = float(a) + float(b)
    _validate_result(result)
    return result


def subtract(a, b):
    _validate_operand(a)
    _validate_operand(b)
    result = float(a) - float(b)
    _validate_result(result)
    return result


def multiply(a, b):
    _validate_operand(a)
    _validate_operand(b)
    result = float(a) * float(b)
    _validate_result(result)
    return result


def divide(a, b):
    _validate_operand(a)
    _validate_operand(b)
    if b == 0:
        raise ZeroDivisionError("cannot divide by zero")
    result = float(a) / float(b)
    _validate_result(result)
    return result
