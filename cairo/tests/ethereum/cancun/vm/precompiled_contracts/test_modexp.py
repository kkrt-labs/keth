import hypothesis.strategies as st
from ethereum.cancun.vm import Evm
from ethereum.cancun.vm.precompiled_contracts.modexp import (
    complexity,
    gas_cost,
    iterations,
    modexp,
)
from ethereum_types.bytes import Bytes
from ethereum_types.numeric import U256, Uint
from hypothesis import assume, given
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

from cairo_addons.testing.errors import strict_raises
from tests.utils.args_gen import U384
from tests.utils.evm_builder import EvmBuilder


def get_u384_bits_little_endian(value: U384):
    value_int = value._number
    bits = []
    while value_int > 0:
        bit = value_int & 1
        bits.append(bit)
        value_int >>= 1

    return bits


class TestModexp:
    @given(
        base=st.binary(max_size=48),
        exp=st.binary(max_size=31),
        mod=st.binary(max_size=48),
        evm=EvmBuilder().with_gas_left().with_message().build(),
    )
    def test_modexp(self, cairo_run, evm: Evm, base: Bytes, exp: Bytes, mod: Bytes):
        base_len = len(base).to_bytes(32, "big")
        exp_len = len(exp).to_bytes(32, "big")
        mod_len = len(mod).to_bytes(32, "big")

        data = base_len + exp_len + mod_len + base + exp + mod
        evm.message.data = Bytes(data)

        try:
            evm_cairo = cairo_run("modexp", evm=evm)
        except Exception as e:
            with strict_raises(type(e)):
                modexp(evm)
            return

        modexp(evm)
        assert evm == evm_cairo

    @given(
        base_length=...,
        modulus_length=...,
    )
    def test_complexity(self, cairo_run, base_length: U256, modulus_length: U256):
        assume(complexity(base_length, modulus_length) < Uint(DEFAULT_PRIME))
        cairo_result = cairo_run("complexity", base_length, modulus_length)
        assert cairo_result == complexity(base_length, modulus_length)

    @given(
        exponent_length=st.integers(min_value=0, max_value=31).map(U256),
        exponent_head=st.integers(min_value=0, max_value=2**31 - 1).map(Uint),
    )
    def test_iterations(self, cairo_run, exponent_length: U256, exponent_head: Uint):
        cairo_result = cairo_run("iterations", exponent_length, exponent_head)
        assert cairo_result == iterations(exponent_length, exponent_head)

    @given(
        base_length=st.integers(min_value=0, max_value=32).map(U256),
        modulus_length=st.integers(min_value=0, max_value=32).map(U256),
        exponent_length=st.integers(min_value=0, max_value=32).map(U256),
        exponent_head=st.integers(min_value=0, max_value=2**248 - 1).map(Uint),
    )
    def test_gas_cost(
        self,
        cairo_run,
        base_length: U256,
        modulus_length: U256,
        exponent_length: U256,
        exponent_head: Uint,
    ):

        expected_gas_cost = gas_cost(
            base_length, modulus_length, exponent_length, exponent_head
        )

        cairo_result = cairo_run(
            "gas_cost", base_length, modulus_length, exponent_length, exponent_head
        )

        if expected_gas_cost > Uint(2**128 - 1):
            assert cairo_result == Uint(2**128 - 1)
        else:
            assert cairo_result == expected_gas_cost

    @given(value=...)
    def test_get_u384_bits_little(self, cairo_run, value: U384):
        (cairo_bits_ptr, cairo_bits_len) = cairo_run("get_u384_bits_little", value)

        python_bits = get_u384_bits_little_endian(value)
        cairo_bits = [cairo_bits_ptr[i] for i in range(cairo_bits_len)]
        assert python_bits == cairo_bits, f"Failed for value {value}"

    @given(value=...)
    def test_uint384_to_be_bytes(self, cairo_run, value: U384):
        int_value = value._number
        if int_value == 0:
            length = 1  # At least one byte for zero
        else:
            length = (int_value.bit_length() + 7) // 8

        cairo_result = cairo_run("U384_to_be_bytes", value, length)

        expected_bytes = int_value.to_bytes(length, "big")
        assert len(cairo_result) == length
        assert bytes(cairo_result) == expected_bytes
