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
        if error:
            error = error.group(1)
            try:
                error = int(error).to_bytes(31, "big").lstrip(b"\x00").decode()
            except Exception:
                pass
        else:
            error = str(e.value)
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


def map_to_python_exception(e: Exception):
    import ethereum.exceptions as eth_exceptions
    import ethereum_rlp.exceptions as rlp_exceptions

    error_str = str(e)

    # Throw a specialized python exception from the error message, if possible
    error = re.search(r"Error message: (.*)", error_str)
    error_type = error.group(1) if error else error_str
    error_msg = None
    exception_class = None
    try:
        # Case 1: error_type is a short string, e.g. raise('ValueError')
        error_type = int(error_type).to_bytes(31, "big").lstrip(b"\x00").decode()
        # Raise in case we have raise_ValueError('ShortStr'), i.e. len(ValueError) + len(ShortStr) < 31
        if " " in error_type:
            raise Exception(f"Unexpected space in short string: {error_type}")
    except Exception:
        try:
            # Case 2: error_type comes with a message, e.g. raise_ValueError('NonEmptyBytesValue')
            new_error_type, error_msg_encoded = error_type.split(": ", 1)
            error_msg = (
                (int(error_msg_encoded).to_bytes(31, "big").lstrip(b"\x00").decode())
                if error_msg_encoded.isdigit()
                else error_msg_encoded
            )
            # Get the exception class from python's builtins or ethereum's exceptions
            exception_class = __builtins__.get(
                new_error_type,
                getattr(eth_exceptions, new_error_type, None)
                or getattr(rlp_exceptions, new_error_type, None),
            )
        except Exception:
            # Get the exception class from python's builtins or ethereum's exceptions
            exception_class = __builtins__.get(
                error_type,
                getattr(eth_exceptions, error_type, None)
                or getattr(rlp_exceptions, error_type, None),
            )

    if (
        "An ASSERT_EQ instruction failed" in error_type
        or "AssertionError" in error_type
    ):
        raise AssertionError(error_str) from e

    if isinstance(exception_class, type) and issubclass(exception_class, Exception):
        raise exception_class(error_msg) from e

    # Fallback to generic exception
    raise Exception(error_type) from e
