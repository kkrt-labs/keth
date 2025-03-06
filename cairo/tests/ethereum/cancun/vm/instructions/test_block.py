from typing import Tuple

from ethereum.cancun.blocks import Log
from ethereum.cancun.state import TransientStorage
from ethereum.cancun.vm import Environment, Evm
from ethereum.cancun.vm.instructions.block import (
    block_hash,
    chain_id,
    coinbase,
    gas_limit,
    number,
    prev_randao,
    timestamp,
)
from ethereum.exceptions import EthereumException
from ethereum_types.numeric import U64, Uint
from hypothesis import given
from hypothesis import strategies as st

from cairo_addons.testing.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder, address_zero
from tests.utils.strategies import (
    BLOCK_HASHES_LIST,
    address,
    bytes32,
    empty_state,
    uint,
    uint64,
    uint256,
)

# Specific environment strategy with minimal items:
# block_hashes, coinbase, number, gas_limit, time, prev_randao, chain_id are
# strategies, the rest:
#   * Empty state
#   * Empty transient storage
#   * Empty block versioned hashes
#   * Excess blob gas is 0
#   * Caller and origin are address_zero
#   * Gas price is 0
#   * Base fee per gas is 0
environment_extra_lite = st.integers(
    max_value=2**64 - 1
).flatmap(  # Generate block number first
    lambda number: st.builds(
        Environment,
        caller=st.just(address_zero),
        block_hashes=st.lists(
            st.sampled_from(BLOCK_HASHES_LIST),
            min_size=min(number, 256),  # number or 256 if number is greater
            max_size=min(number, 256),
        ),
        origin=st.just(address_zero),
        coinbase=address,
        number=st.just(Uint(number)),  # Use the same number
        base_fee_per_gas=st.just(Uint(0)),
        gas_limit=uint,
        gas_price=st.just(Uint(0)),
        time=uint256,
        prev_randao=bytes32,
        state=empty_state,
        chain_id=uint64,
        excess_blob_gas=st.just(U64(0)),
        blob_versioned_hashes=st.just(()),
        transient_storage=st.just(TransientStorage()),
    )
)

block_tests_strategy = (
    EvmBuilder().with_stack().with_gas_left().with_env(environment_extra_lite).build()
)


class TestBlock:
    @given(block_tests_strategy)
    def test_block_hash(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("block_hash", evm)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                block_hash(evm)
            return

        block_hash(evm)
        assert evm == cairo_result

    @given(evm=block_tests_strategy)
    def test_coinbase(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("coinbase", evm)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                coinbase(evm)
            return

        coinbase(evm)
        assert evm == cairo_result

    @given(evm=block_tests_strategy)
    def test_timestamp(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("timestamp", evm)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                timestamp(evm)
            return

        timestamp(evm)
        assert evm == cairo_result

    @given(evm=block_tests_strategy)
    def test_number(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("number", evm)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                number(evm)
            return

        number(evm)
        assert evm == cairo_result

    @given(evm=block_tests_strategy)
    def test_prev_randao(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("prev_randao", evm)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                prev_randao(evm)
            return

        prev_randao(evm)
        assert evm == cairo_result

    @given(evm=block_tests_strategy)
    def test_gas_limit(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("gas_limit", evm)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                gas_limit(evm)
            return

        gas_limit(evm)
        assert evm == cairo_result

    @given(evm=block_tests_strategy)
    def test_chain_id(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("chain_id", evm)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                chain_id(evm)
            return

        chain_id(evm)
        assert evm == cairo_result


class TestUtils:
    @given(logs=..., new_logs=...)
    def test_append_logs(
        self, cairo_run, logs: Tuple[Log, ...], new_logs: Tuple[Log, ...]
    ):
        try:
            cairo_result = cairo_run("_append_logs", logs, new_logs)
        except EthereumException as cairo_error:
            with strict_raises(type(cairo_error)):
                logs += new_logs
            return

        logs += new_logs
        assert logs == cairo_result
