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


def map_to_python_exception(e: Exception) -> None:
    """
    Maps a generic Exception (potentially from Cairo) to a specific Python exception
    based on its string representation.

    The error string is expected to follow one of these patterns:
    1. An arbitrary error string.
    2. The name of a Python exception class (e.g., "ValueError").
    3. The name of a Python exception class followed by a message (e.g., "ValueError: error message").

    Args:
        e: The exception instance caught.

    Raises:
        A specific Python exception (if mapped and is an Exception subclass),
        AssertionError for specific Cairo assertion messages, or a generic Exception,
        preserving the original exception as the cause.
    """
    original_error_str = str(e)

    # Extract the core message, handling the "Error message: " prefix if present
    match = re.search(r"Error message: (.*)", original_error_str)
    error_content = match.group(1) if match else original_error_str

    parts = error_content.split(": ", 1)
    potential_type_name = parts[0]
    try:
        potential_type_name_int = int(potential_type_name)
        potential_type_name = (
            potential_type_name_int.to_bytes(31, "big").lstrip(b"\x00").decode()
        )
    except (ValueError, UnicodeDecodeError):
        pass

    message = parts[1] if len(parts) > 1 else None
    if message is not None:
        try:
            message_int = int(message)
            message = message_int.to_bytes(31, "big").lstrip(b"\x00").decode()
        except (ValueError, UnicodeDecodeError):
            pass

    exception_class = find_exception_class(potential_type_name)

    if (
        exception_class
        and isinstance(exception_class, type)
        and issubclass(exception_class, Exception)
    ):
        if message:
            raise exception_class(message) from e
        else:
            raise exception_class() from e

    try:
        error_content_decoded = (
            int(error_content).to_bytes(31, "big").lstrip(b"\x00").decode()
        )
    except Exception:
        error_content_decoded = error_content

    if (
        "An ASSERT_EQ instruction failed" in original_error_str
        or "AssertionError" in error_content
    ):
        raise AssertionError(error_content_decoded) from e

    raise Exception(error_content_decoded) from e


def find_exception_class(name: str) -> Optional[Type[Exception]]:
    """Looks up an exception class by name in predefined modules."""
    import ethereum.exceptions as eth_exceptions
    import ethereum_rlp.exceptions as rlp_exceptions

    builtin_exc = __builtins__.get(name)
    if isinstance(builtin_exc, type) and issubclass(builtin_exc, BaseException):
        return builtin_exc

    for module in [eth_exceptions, rlp_exceptions]:
        custom_exc = getattr(module, name, None)
        if isinstance(custom_exc, type) and issubclass(custom_exc, Exception):
            return custom_exc

    return None
