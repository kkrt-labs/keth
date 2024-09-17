import re
from contextlib import contextmanager

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
        assert message == error, f"Expected {message}, got {error}"
    finally:
        pass
