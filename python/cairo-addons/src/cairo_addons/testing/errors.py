import re
from contextlib import contextmanager
from typing import Optional, Type

import pytest


@contextmanager
def cairo_error(message=None):
    try:
        with pytest.raises(Exception) as e:
            yield e
        if message is None:
            return
        error = re.search(r"Error message: (.*)", str(e.value))
        error = error.group(1) if error else str(e.value)
        assert message in error, f"Expected {message}, got {error}"
    finally:
        pass


@contextmanager
def strict_raises(expected_exception: Type[Exception], match: Optional[str] = None):
    """
    Context manager that extends pytest.raises to enforce strict exception type matching.
    Unlike pytest.raises, this doesn't allow subclass exceptions to match.

    Args:
        expected_exception: The exact exception type expected
        match: Optional string pattern to match against the exception message

    Example:
        with strict_raises(ValueError, match="invalid value"):
            raise ValueError("invalid value")  # passes

        with strict_raises(Exception):
            raise ValueError()  # fails - more specific exception
    """
    with pytest.raises(Exception) as exc_info:
        yield exc_info

    if type(exc_info.value) is not expected_exception:
        raise AssertionError(
            f"Expected exactly {expected_exception.__name__}, but got {type(exc_info.value).__name__}"
        )

    if match is not None:
        error_msg = str(exc_info.value)
        assert match in error_msg, f"Expected '{match}' in '{error_msg}'"
