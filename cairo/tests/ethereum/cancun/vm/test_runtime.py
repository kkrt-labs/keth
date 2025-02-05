from ethereum.cancun.vm.runtime import get_valid_jump_destinations
from ethereum_types.bytes import Bytes
from hypothesis import given


class TestRuntime:
    @given(code=contract_code_strategy())
    def test_get_valid_jump_destinations(self, cairo_run, code: Bytes):

        cairo_result = cairo_run("get_valid_jump_destinations", code)
        assert get_valid_jump_destinations(code) == cairo_result
