import re
from contextlib import contextmanager
from typing import Type

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
def assert_raises_exactly(expected_exception: Type[Exception], msg: str = None):
    """
    Context manager that verifies an exception of exactly the specified type is raised.
    Unlike pytest.raises, this doesn't allow subclass exceptions to match.

    Args:
        expected_exception: The exact exception type expected
        msg: Optional message to include in assertion error

    Example:
        with assert_raises_exactly(AssertionError):
            raise AssertionError()  # passes

        with assert_raises_exactly(Exception):
            raise AssertionError()  # fails - more specific exception
    """
    try:
        yield
    except Exception as e:
        if type(e) is not expected_exception:
            raise AssertionError(
                msg
                or f"Expected exactly {expected_exception.__name__}, but got {type(e).__name__}"
            )
    else:
        raise AssertionError(
            msg
            or f"Expected {expected_exception.__name__} to be raised, but no exception was raised"
        )
