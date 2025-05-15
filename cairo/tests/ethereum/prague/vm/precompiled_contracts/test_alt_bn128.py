from ethereum.prague.vm import Evm
from ethereum.prague.vm.exceptions import OutOfGasError
from ethereum.prague.vm.precompiled_contracts.alt_bn128 import (
    alt_bn128_add,
    alt_bn128_mul,
    alt_bn128_pairing_check,
)
from ethereum.crypto.alt_bn128 import ALT_BN128_PRIME, BNP
from ethereum_types.bytes import Bytes
from hypothesis import given
from hypothesis import strategies as st

from cairo_addons.testing.errors import strict_raises
from cairo_ec.curve import AltBn128
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
    """
    Strategy for generating test cases for the alt_bn128_add precompiled contract.
    Covers:
    - Valid points on the ALT_BN128 curve (including point at infinity).
    - Invalid inputs: coordinates >= ALT_BN128_PRIME or points not on the curve.
    """
    case_type = draw(
        st.sampled_from(
            [
                "both_valid",
                "first_infinity",
                "second_infinity",
                "both_infinity",
                "out_of_range",
                "invalid_p0",
                "invalid_p1",
            ]
        )
    )

    if case_type == "both_valid":
        p0 = AltBn128.random_point(retry=True)
        p1 = AltBn128.random_point(retry=True)
        return (
            p0.x.to_bytes(32, "big")
            + p0.y.to_bytes(32, "big")
            + p1.x.to_bytes(32, "big")
            + p1.y.to_bytes(32, "big")
        )

    elif case_type == "first_infinity":
        p0 = BNP.point_at_infinity()
        p1 = AltBn128.random_point(retry=True)
        return (
            p0.x.to_bytes(32, "big")
            + p0.y.to_bytes(32, "big")
            + p1.x.to_bytes(32, "big")
            + p1.y.to_bytes(32, "big")
        )

    elif case_type == "both_infinity":
        p0 = BNP.point_at_infinity()
        p1 = BNP.point_at_infinity()
        return (
            p0.x.to_bytes(32, "big")
            + p0.y.to_bytes(32, "big")
            + p1.x.to_bytes(32, "big")
            + p1.y.to_bytes(32, "big")
        )

    elif case_type == "second_infinity":
        p0 = AltBn128.random_point(retry=True)
        p1 = BNP.point_at_infinity()
        return (
            p0.x.to_bytes(32, "big")
            + p0.y.to_bytes(32, "big")
            + p1.x.to_bytes(32, "big")
            + p1.y.to_bytes(32, "big")
        )

    elif case_type == "out_of_range":
        # Generate coordinates, ensuring at least one is >= ALT_BN128_PRIME
        x0 = draw(st.integers(min_value=0, max_value=ALT_BN128_PRIME - 1))
        y0 = draw(st.integers(min_value=0, max_value=ALT_BN128_PRIME - 1))
        x1 = draw(st.integers(min_value=0, max_value=ALT_BN128_PRIME - 1))
        y1 = draw(st.integers(min_value=0, max_value=ALT_BN128_PRIME - 1))
        coord = draw(st.sampled_from(["x0", "y0", "x1", "y1"]))
        if coord == "x0":
            x0 = ALT_BN128_PRIME
        elif coord == "y0":
            y0 = ALT_BN128_PRIME
        elif coord == "x1":
            x1 = ALT_BN128_PRIME
        else:
            y1 = ALT_BN128_PRIME
        return (
            x0.to_bytes(32, "big")
            + y0.to_bytes(32, "big")
            + x1.to_bytes(32, "big")
            + y1.to_bytes(32, "big")
        )

    elif case_type == "invalid_p0":
        p0 = AltBn128.random_point(retry=False)
        p1 = AltBn128.random_point(retry=True)
        while AltBn128.is_on_curve(p0.x, p0.y):
            p0 = AltBn128.random_point(retry=False)
        return (
            p0.x.to_bytes(32, "big")
            + p0.y.to_bytes(32, "big")
            + p1.x.to_bytes(32, "big")
            + p1.y.to_bytes(32, "big")
        )

    elif case_type == "invalid_p1":
        p0 = AltBn128.random_point(retry=True)
        p1 = AltBn128.random_point(retry=False)
        while AltBn128.is_on_curve(p1.x, p1.y):
            p1 = AltBn128.random_point(retry=False)
        return (
            p0.x.to_bytes(32, "big")
            + p0.y.to_bytes(32, "big")
            + p1.x.to_bytes(32, "big")
            + p1.y.to_bytes(32, "big")
        )


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
