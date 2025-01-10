from ethereum_types.bytes import Bytes
from hypothesis import given

from ethereum.cancun.vm.runtime import get_valid_jump_destinations


class TestRuntime:
    @given(code=...)
    def test_get_valid_jump_destinations(self, cairo_run, code: Bytes):
        assert get_valid_jump_destinations(code) == cairo_run(
            "get_valid_jump_destinations", code
        )
