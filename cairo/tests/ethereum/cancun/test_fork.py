from dataclasses import replace
from typing import Optional, Tuple

from eth_keys.datatypes import PrivateKey
from ethereum_types.bytes import Bytes, Bytes20
from ethereum_types.numeric import U64, U256, Uint
from hypothesis import assume, given, settings
from hypothesis import strategies as st
from hypothesis.strategies import composite, integers

from ethereum.cancun.blocks import Header, Log
from ethereum.cancun.fork import (
    GAS_LIMIT_ADJUSTMENT_FACTOR,
    calculate_base_fee_per_gas,
    check_gas_limit,
    check_transaction,
    make_receipt,
    process_transaction,
    validate_header,
)
from ethereum.cancun.fork_types import Address
from ethereum.cancun.state import set_account
from ethereum.cancun.transactions import (
    AccessListTransaction,
    BlobTransaction,
    FeeMarketTransaction,
    LegacyTransaction,
    Transaction,
    signing_hash_155,
    signing_hash_1559,
    signing_hash_2930,
    signing_hash_4844,
)
from ethereum.cancun.vm import Environment
from ethereum.exceptions import EthereumException
from tests.ethereum.cancun.vm.test_interpreter import unimplemented_precompiles
from tests.utils.errors import strict_raises
from tests.utils.strategies import account_strategy, address, bytes32, state


@composite
def tx_without_code(draw):
    # Generate access list
    access_list_entries = draw(
        st.lists(st.tuples(address, st.lists(bytes32, max_size=2)), max_size=3)
    )
    access_list = tuple(
        (addr, tuple(storage_keys)) for addr, storage_keys in access_list_entries
    )

    to = (
        st.integers(min_value=0, max_value=2**160 - 1)
        .filter(lambda x: x not in unimplemented_precompiles)
        .map(lambda x: Bytes20(x.to_bytes(20, "little")))
        .map(Address)
    )

    # Define strategies for each transaction type
    legacy_tx = st.builds(
        LegacyTransaction, data=st.just(Bytes(bytes.fromhex("6060"))), to=to
    )

    access_list_tx = st.builds(
        AccessListTransaction,
        data=st.just(Bytes(bytes.fromhex("6060"))),
        access_list=st.just(access_list),
        to=to,
    )

    fee_market_tx = st.builds(
        FeeMarketTransaction,
        data=st.just(Bytes(bytes.fromhex("6060"))),
        access_list=st.just(access_list),
        to=to,
    )

    blob_tx = st.builds(
        BlobTransaction,
        data=st.just(Bytes(bytes.fromhex("6060"))),
        access_list=st.just(access_list),
        to=to,
    )

    # Choose one transaction type
    tx = draw(st.one_of(legacy_tx, access_list_tx, fee_market_tx, blob_tx))

    return tx


@composite
def tx_with_sender_in_state(
    draw, state_strategy=state, account_strategy=account_strategy
):
    state = draw(state_strategy)
    chain_id = draw(st.from_type(U64))
    tx = draw(st.from_type(Transaction))
    private_key = draw(st.from_type(PrivateKey))
    expected_address = int(private_key.public_key.to_address(), 16)
    if isinstance(tx, LegacyTransaction):
        signature = private_key.sign_msg_hash(signing_hash_155(tx, chain_id))
    elif isinstance(tx, AccessListTransaction):
        signature = private_key.sign_msg_hash(signing_hash_2930(tx))
    elif isinstance(tx, FeeMarketTransaction):
        signature = private_key.sign_msg_hash(signing_hash_1559(tx))
    elif isinstance(tx, BlobTransaction):
        signature = private_key.sign_msg_hash(signing_hash_4844(tx))
    else:
        raise ValueError(f"Unsupported transaction type: {type(tx)}")

    # Overwrite r and s with valid values
    v_or_y_parity = {}
    if isinstance(tx, LegacyTransaction):
        v_or_y_parity["v"] = U256(signature.v)
    else:
        v_or_y_parity["y_parity"] = U256(signature.v)
    tx = replace(tx, r=U256(signature.r), s=U256(signature.s), **v_or_y_parity)

    should_add_sender_to_state = draw(integers(0, 99)) < 80
    if should_add_sender_to_state:
        sender = Address(int(expected_address).to_bytes(20, "little"))
        account = draw(account_strategy)
        set_account(state, sender, account)
        return tx, state
    else:
        return tx, state


class TestFork:
    @given(
        block_gas_limit=...,
        parent_gas_limit=...,
        parent_gas_used=...,
        parent_base_fee_per_gas=...,
    )
    def test_calculate_base_fee_per_gas(
        self,
        cairo_run,
        block_gas_limit: Uint,
        parent_gas_limit: Uint,
        parent_gas_used: Uint,
        parent_base_fee_per_gas: Uint,
    ):
        try:
            cairo_result = cairo_run(
                "calculate_base_fee_per_gas",
                block_gas_limit,
                parent_gas_limit,
                parent_gas_used,
                parent_base_fee_per_gas,
            )
        except Exception as e:
            with strict_raises(type(e)):
                calculate_base_fee_per_gas(
                    block_gas_limit,
                    parent_gas_limit,
                    parent_gas_used,
                    parent_base_fee_per_gas,
                )
            return

        assert cairo_result == calculate_base_fee_per_gas(
            block_gas_limit,
            parent_gas_limit,
            parent_gas_used,
            parent_base_fee_per_gas,
        )

    @given(header=..., parent_header=...)
    def test_validate_header(self, cairo_run, header: Header, parent_header: Header):
        try:
            cairo_run("validate_header", header, parent_header)
        except Exception as e:
            with strict_raises(type(e)):
                validate_header(header, parent_header)
            return

        validate_header(header, parent_header)

    @given(gas_limit=..., parent_gas_limit=...)
    def test_check_gas_limit(self, cairo_run, gas_limit: Uint, parent_gas_limit: Uint):
        assume(
            parent_gas_limit + parent_gas_limit // GAS_LIMIT_ADJUSTMENT_FACTOR
            < Uint(2**64)
        )
        assert check_gas_limit(gas_limit, parent_gas_limit) == cairo_run(
            "check_gas_limit", gas_limit, parent_gas_limit
        )

    @given(tx=..., error=..., cumulative_gas_used=..., logs=...)
    def test_make_receipt(
        self,
        cairo_run,
        tx: Transaction,
        error: Optional[EthereumException],
        cumulative_gas_used: Uint,
        logs: Tuple[Log, ...],
    ):
        assert make_receipt(tx, error, cumulative_gas_used, logs) == cairo_run(
            "make_receipt", tx, error, cumulative_gas_used, logs
        )

    @given(env=..., tx=tx_without_code())
    @settings(max_examples=100)
    def test_process_transaction(self, cairo_run, env: Environment, tx: Transaction):
        try:
            gas_used_cairo, logs_cairo, error_cairo = cairo_run(
                "process_transaction", env, tx
            )
        except Exception as e:
            with strict_raises(type(e)):
                process_transaction(env, tx)
            return

        gas_used, logs, error = process_transaction(env, tx)
        assert gas_used_cairo == gas_used
        assert logs_cairo == logs
        assert error_cairo == error

    @given(
        data=tx_with_sender_in_state(),
        gas_available=...,
        chain_id=...,
        base_fee_per_gas=...,
        excess_blob_gas=...,
    )
    def test_check_transaction(
        self,
        cairo_run_py,
        data,
        gas_available: Uint,
        chain_id: U64,
        base_fee_per_gas: Uint,
        excess_blob_gas: U64,
    ):
        tx, state = data
        try:
            cairo_state, cairo_result = cairo_run_py(
                "check_transaction",
                state,
                tx,
                gas_available,
                chain_id,
                base_fee_per_gas,
                excess_blob_gas,
            )
        except Exception as e:
            with strict_raises(type(e)):
                check_transaction(
                    state,
                    tx,
                    gas_available,
                    chain_id,
                    base_fee_per_gas,
                    excess_blob_gas,
                )
            return

        assert cairo_result == check_transaction(
            state, tx, gas_available, chain_id, base_fee_per_gas, excess_blob_gas
        )
        assert cairo_state == state
