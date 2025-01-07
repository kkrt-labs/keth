import pytest
from hypothesis import given
from hypothesis.strategies import integers

pytestmark = pytest.mark.python_vm


class TestIsValidJumpdest:
    # 1000000 is the default value for the init_evm test helper
    @given(amount=integers(min_value=0, max_value=1000000))
    def test_should_return_gas_left(self, cairo_run, amount):
        gas_left, stopped = cairo_run("test__charge_gas", amount=amount)
        assert gas_left == 1000000 - amount
        assert stopped == 0

    # 1000000 is the default value for the init_evm test helper
    @given(amount=integers(min_value=1000001, max_value=2**248 - 1))
    def test_should_return_not_enough_gas(self, cairo_run, amount):
        gas_left, stopped = cairo_run("test__charge_gas", amount=amount)
        assert gas_left == 0
        assert stopped == 1
