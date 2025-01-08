import pytest
from hypothesis import given

from ethereum.cancun.vm.runtime import get_valid_jump_destinations
from ethereum_types.bytes import Bytes

pytestmark = pytest.mark.python_vm


class TestRuntime:
    @given(code=...)
    def test_get_valid_jump_destinations(self, cairo_run, code: Bytes):
        assert get_valid_jump_destinations(code) == cairo_run(
            "get_valid_jump_destinations", code
        )
