from hypothesis import given

from ethereum.base_types import Uint
from ethereum.cancun.vm.gas import init_code_cost


class TestGas:
    @given(init_code_length=...)
    def test_init_code_cost(self, cairo_run, init_code_length: Uint):
        assert init_code_cost(init_code_length) == cairo_run(
            "init_code_cost", init_code_length
        )
