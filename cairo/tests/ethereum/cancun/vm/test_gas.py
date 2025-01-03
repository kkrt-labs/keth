import pytest
from ethereum_types.numeric import U256, Uint
from hypothesis import assume, given
from hypothesis import strategies as st

from ethereum.cancun.blocks import Header
from ethereum.cancun.transactions import BlobTransaction
from ethereum.cancun.vm.gas import (
    GAS_CALL_STIPEND,
    calculate_blob_gas_price,
    calculate_data_fee,
    calculate_excess_blob_gas,
    calculate_memory_gas_cost,
    calculate_message_call_gas,
    calculate_total_blob_gas,
    charge_gas,
    init_code_cost,
    max_message_call_gas,
)
from tests.utils.args_gen import Evm


class TestGas:
    @given(evm=..., amount=...)
    def test_charge_gas(self, cairo_run, evm: Evm, amount: Uint):
        try:
            cairo_result = cairo_run("charge_gas", evm, amount)
        except Exception as cairo_error:
            with pytest.raises(type(cairo_error)):
                charge_gas(evm, amount)
            return

        charge_gas(evm, amount)
        assert evm == cairo_result

    @given(size_in_bytes=...)
    def test_calculate_memory_gas_cost(self, cairo_run, size_in_bytes: Uint):
        assert calculate_memory_gas_cost(size_in_bytes) == cairo_run(
            "calculate_memory_gas_cost", size_in_bytes
        )

    @given(
        value=...,
        gas=...,
        gas_left=...,
        memory_cost=...,
        extra_gas=...,
        call_stipend=st.just(GAS_CALL_STIPEND),
    )
    def test_calculate_message_call_gas(
        self,
        cairo_run,
        value: U256,
        gas: Uint,
        gas_left: Uint,
        memory_cost: Uint,
        extra_gas: Uint,
        call_stipend,
    ):
        assert calculate_message_call_gas(
            value, gas, gas_left, memory_cost, extra_gas, call_stipend
        ) == cairo_run(
            "calculate_message_call_gas",
            value,
            gas,
            gas_left,
            memory_cost,
            extra_gas,
            call_stipend,
        )

    @given(gas=...)
    def test_max_message_call_gas(self, cairo_run, gas: Uint):
        assert max_message_call_gas(gas) == cairo_run("max_message_call_gas", gas)

    @given(init_code_length=...)
    def test_init_code_cost(self, cairo_run, init_code_length: Uint):
        assert init_code_cost(init_code_length) == cairo_run(
            "init_code_cost", init_code_length
        )

    @given(parent_header=...)
    def test_calculate_excess_blob_gas(self, cairo_run, parent_header: Header):
        assume(
            int(parent_header.excess_blob_gas) + int(parent_header.blob_gas_used)
            < 2**64
        )
        assert calculate_excess_blob_gas(parent_header) == cairo_run(
            "calculate_excess_blob_gas", parent_header
        )

    @given(tx=...)
    def test_calculate_total_blob_gas(self, cairo_run, tx: BlobTransaction):
        assume(len(tx.blob_versioned_hashes) > 0)
        assert calculate_total_blob_gas(tx) == cairo_run("calculate_total_blob_gas", tx)

    @given(excess_blob_gas=st.integers(min_value=0, max_value=100_000))
    def test_calculate_blob_gas_price(self, cairo_run, excess_blob_gas):
        assert calculate_blob_gas_price(excess_blob_gas) == cairo_run(
            "calculate_blob_gas_price", excess_blob_gas
        )

    @given(excess_blob_gas=st.integers(min_value=0, max_value=100_000), tx=...)
    def test_calculate_data_fee(self, cairo_run, excess_blob_gas, tx: BlobTransaction):
        assume(len(tx.blob_versioned_hashes) > 0)
        assert calculate_data_fee(excess_blob_gas, tx) == cairo_run(
            "calculate_data_fee", excess_blob_gas, tx
        )
