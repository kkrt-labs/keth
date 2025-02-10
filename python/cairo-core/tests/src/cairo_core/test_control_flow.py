from string import ascii_letters

from hypothesis import given
from hypothesis import strategies as st

from cairo_addons.testing.errors import cairo_error


class TestControlFlow:
    @given(message=st.text(alphabet=ascii_letters, min_size=0, max_size=31))
    def test_raise(self, cairo_run, message):
        with cairo_error(message=message):
            cairo_run("raise", int.from_bytes(message.encode(), "big"))
