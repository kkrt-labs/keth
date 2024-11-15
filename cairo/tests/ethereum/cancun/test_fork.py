from hypothesis import assume, given

from ethereum.base_types import Uint
from ethereum.cancun.fork import GAS_LIMIT_ADJUSTMENT_FACTOR, check_gas_limit


class TestFork:
    @given(gas_limit=..., parent_gas_limit=...)
    def test_check_gas_limit(self, cairo_run, gas_limit: Uint, parent_gas_limit: Uint):
        assume(
            int(parent_gas_limit) + int(parent_gas_limit) // GAS_LIMIT_ADJUSTMENT_FACTOR
            < 2**64
        )
        assert check_gas_limit(gas_limit, parent_gas_limit) == cairo_run(
            "check_gas_limit", gas_limit, parent_gas_limit
        )
