import hypothesis.strategies as st
from ethereum.prague.vm import Evm
from ethereum.prague.vm.precompiled_contracts.modexp import (
    complexity,
    gas_cost,
    iterations,
    modexp,
)
from ethereum_types.bytes import Bytes
from ethereum_types.numeric import U256, Uint
from hypothesis import given

from cairo_addons.testing.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder


class TestModexp:
    @given(
        base=st.binary(max_size=48),
        exp=st.binary(max_size=48),
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
        expected = complexity(base_length, modulus_length)
        cairo_result = cairo_run("complexity", base_length, modulus_length)
        if expected > Uint(2**128 - 1):
            assert cairo_result == Uint(2**128 - 1)
        else:
            assert cairo_result == expected

    @given(
        exponent_length=st.integers(min_value=0, max_value=48).map(U256),
        exponent_head=...,
    )
    def test_iterations(self, cairo_run, exponent_length: U256, exponent_head: U256):
        cairo_result = cairo_run("iterations", exponent_length, exponent_head)
        assert cairo_result == iterations(exponent_length, exponent_head)

    @given(
        base_length=st.integers(min_value=0, max_value=48).map(U256),
        modulus_length=st.integers(min_value=0, max_value=48).map(U256),
        exponent_length=st.integers(min_value=0, max_value=48).map(U256),
        exponent_head=...,
    )
    def test_gas_cost(
        self,
        cairo_run,
        base_length: U256,
        modulus_length: U256,
        exponent_length: U256,
        exponent_head: U256,
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
