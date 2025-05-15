from typing import Tuple

from ethereum.prague.blocks import Log
from ethereum.prague.state import TransientStorage
from ethereum.prague.vm import BlockEnvironment, Evm, TransactionEnvironment
from ethereum.prague.vm.instructions.block import (
    block_hash,
    chain_id,
    coinbase,
    gas_limit,
    number,
    prev_randao,
    timestamp,
)
from ethereum.crypto.hash import Hash32
from ethereum.exceptions import EthereumException
from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U64, Uint
from hypothesis import given
from hypothesis import strategies as st

from cairo_addons.testing.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder
from tests.utils.message_builder import MessageBuilder
from tests.utils.strategies import (
    BLOCK_HASHES_LIST,
    address,
    address_zero,
    bytes32,
    empty_state,
    uint,
    uint64,
    uint256,
)

# Strategies for BlockEnvironment and TransactionEnvironment with minimal items.
#
# block_env_extra_lite:
# Fields like block_hashes, coinbase, number, gas_limit, time, prev_randao, chain_id
# use specific strategies (some dependent on 'number', others general like `address` or `uint`).
# Other fields (base_fee_per_gas, state, excess_blob_gas, parent_beacon_block_root)
# are set to specific default/empty values (e.g., 0, empty_state, Hash32(zero_bytes)).
#
# tx_env_extra_lite:
# All fields (origin, gas_price, blob_versioned_hashes, transient_storage, gas,
# access_list_addresses, access_list_storage_keys, index_in_block, tx_hash, traces)
# are set to specific default/empty values (e.g., address_zero, 0, empty tuple/set/list, None).

block_env_extra_lite = st.integers(
    min_value=0, max_value=2**64 - 1
).flatmap(  # Generate block number first
    lambda number: st.builds(
        BlockEnvironment,
        chain_id=uint64,
        state=empty_state,
        block_gas_limit=uint,
        block_hashes=st.lists(
            st.sampled_from(BLOCK_HASHES_LIST),
            min_size=min(number, 256),
            max_size=min(number, 256),
        ),
        coinbase=address,
        number=st.just(Uint(number)),
        base_fee_per_gas=st.just(Uint(0)),
        time=uint256,
        prev_randao=bytes32,
        excess_blob_gas=st.just(U64(0)),
        parent_beacon_block_root=st.just(Hash32(Bytes32(b"\x00" * 32))),
    )
)

tx_env_extra_lite = st.builds(
    TransactionEnvironment,
    origin=st.just(address_zero),
    gas_price=st.just(Uint(0)),
    blob_versioned_hashes=st.just(tuple()),
    transient_storage=st.just(TransientStorage()),
    gas=st.just(Uint(0)),
    access_list_addresses=st.just(set()),
    access_list_storage_keys=st.just(set()),
    index_in_block=st.just(None),
    tx_hash=st.just(None),
)

block_tests_strategy = (
    EvmBuilder()
    .with_stack()
    .with_gas_left()
    .with_message(
        MessageBuilder()
        .with_block_env(block_env_extra_lite)
        .with_tx_env(tx_env_extra_lite)
        .build()
    )
    .build()
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
