from ethereum.cancun.vm import Evm
from ethereum.cancun.vm.exceptions import OutOfGasError
from ethereum.cancun.vm.precompiled_contracts.alt_bn128 import (
    ALT_BN128_PRIME,
    alt_bn128_add,
    alt_bn128_mul,
    alt_bn128_pairing_check,
)
from ethereum_types.bytes import Bytes
from hypothesis import given
from hypothesis import strategies as st

from cairo_addons.testing.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder


@st.composite
def pairing_check_strategy(draw):
    # ecpairing requires the data to be a multiple of 192 to run.
    # we test both cases.
    probability = draw(st.integers(min_value=0, max_value=100))
    base = draw(st.integers(min_value=0, max_value=192))
    if probability < 80:  # 80% chance of being True
        return draw(st.binary(min_size=0, max_size=base * 192))
    else:
        return draw(st.binary(min_size=0, max_size=base * 193))


@st.composite
def add_strategy(draw):
    # Check failure cases for:
    # - x0, y0, x1, y1 >= ALT_BN128_PRIME
    # - Point is not on curve
    # - Point at infinity

    x0 = draw(st.integers(min_value=0, max_value=ALT_BN128_PRIME))
    y0 = draw(st.integers(min_value=0, max_value=ALT_BN128_PRIME))
    x1 = draw(st.integers(min_value=0, max_value=ALT_BN128_PRIME))
    y1 = draw(st.integers(min_value=0, max_value=ALT_BN128_PRIME))

    error_case = draw(st.booleans())
    if error_case:
        error_case_type = draw(
            st.integers(min_value=0, max_value=8)
        )  # each has 5% chance being true
        if error_case_type == 0:
            x0 = ALT_BN128_PRIME + 1
        elif error_case_type == 1:
            y0 = ALT_BN128_PRIME + 1
        elif error_case_type == 2:
            x1 = ALT_BN128_PRIME + 1
        elif error_case_type == 3:
            y1 = ALT_BN128_PRIME + 1

        if error_case_type == 5:
            x0 = 0
            y0 = 0

        if error_case_type == 6:
            x1 = 0
            y1 = 0

        if error_case_type == 7:
            x0 = 1
            y0 = 2
            x1 = 3
            y1 = 4

    res = (
        x0.to_bytes(32, "big")
        + y0.to_bytes(32, "big")
        + x1.to_bytes(32, "big")
        + y1.to_bytes(32, "big")
    )
    return res


class TestAltbn128:
    @given(
        evm=EvmBuilder().with_gas_left().build(),
        data=pairing_check_strategy(),
    )
    def test_alt_bn128_pairing_check(self, cairo_run, evm: Evm, data: Bytes):
        evm.message.data = data

        try:
            evm_cairo = cairo_run("alt_bn128_pairing_check", evm=evm)
        except Exception as e:
            with strict_raises(type(e)):
                alt_bn128_pairing_check(evm)
            return

        alt_bn128_pairing_check(evm)
        assert evm == evm_cairo

    @given(evm=EvmBuilder().with_gas_left().build())
    def test_alt_bn128_pairing_check_invalid_input(self, cairo_run, evm: Evm):
        evm.message.data = (ALT_BN128_PRIME + 1).to_bytes(32, "big") * 6
        with strict_raises(OutOfGasError):
            cairo_run("alt_bn128_pairing_check", evm=evm)

    @given(
        evm=EvmBuilder().with_gas_left().build(),
        data=add_strategy(),
    )
    def test_alt_bn128_add(self, cairo_run, evm: Evm, data: Bytes):
        evm.message.data = data

        try:
            evm_cairo = cairo_run("alt_bn128_add", evm=evm)
        except Exception as e:
            with strict_raises(type(e)):
                alt_bn128_add(evm)
            return

        alt_bn128_add(evm)
        assert evm == evm_cairo

    @given(
        evm=EvmBuilder().with_gas_left().build(),
        data=add_strategy(),
    )
    def test_alt_bn128_mul(self, cairo_run, evm: Evm, data: Bytes):
        evm.message.data = data

        try:
            evm_cairo = cairo_run("alt_bn128_mul", evm=evm)
        except Exception as e:
            with strict_raises(type(e)):
                alt_bn128_mul(evm)
            return

        alt_bn128_mul(evm)
        assert evm == evm_cairo
