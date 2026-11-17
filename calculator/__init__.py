"""Public API for the calculator package.

Exposes the four arithmetic operations from the pure arithmetic core
(``calculator.operations``) at the package root, as required by
``TECHNICAL_SPEC.md`` section 2. The arithmetic module is authoritative;
this package init only re-exports its public functions.
"""

from .operations import add, divide, multiply, subtract

__all__ = ["add", "subtract", "multiply", "divide"]
