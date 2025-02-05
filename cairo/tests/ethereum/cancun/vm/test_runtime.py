from ethereum.cancun.vm.runtime import get_valid_jump_destinations
from ethereum_types.bytes import Bytes
from hypothesis import example, given

from tests.utils.solidity import get_contract


class TestRuntime:
    @given(code=...)
    @example(code=get_contract("Counter", "Counter").bytecode_runtime)
    @example(code=get_contract("ERC20", "KethToken").bytecode_runtime)
    def test_get_valid_jump_destinations(self, cairo_run, code: Bytes):

        cairo_result = cairo_run("get_valid_jump_destinations", code)
        assert get_valid_jump_destinations(code) == cairo_result
