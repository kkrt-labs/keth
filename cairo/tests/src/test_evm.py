import pytest
from hypothesis import given
from hypothesis.strategies import integers


class TestIsValidJumpdest:
    @pytest.mark.parametrize(
        "cached_jumpdests, index, expected",
        [
            ({0x01: True, 0x10: True, 0x101: True}, 0x10, 1),
            ({0x01: True, 0x10: True, 0x101: True}, 0x101, 1),
        ],
    )
    def test_should_return_cached_valid_jumpdest(
        self, cairo_run, cached_jumpdests, index, expected
    ):
        assert (
            cairo_run(
                "test__is_valid_jumpdest",
                cached_jumpdests=cached_jumpdests,
                index=index,
            )
            == expected
        )

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
