from dataclasses import replace
from typing import Optional, Tuple

from eth_keys.datatypes import PrivateKey
from ethereum.cancun.blocks import Block, Header, Log
from ethereum.cancun.fork import (
    GAS_LIMIT_ADJUSTMENT_FACTOR,
    BlockChain,
    calculate_base_fee_per_gas,
    check_gas_limit,
    check_transaction,
    get_last_256_block_hashes,
    make_receipt,
    process_transaction,
    validate_header,
)
from ethereum.cancun.fork_types import Address
from ethereum.cancun.state import State, set_account
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
from ethereum.cancun.vm.gas import TARGET_BLOB_GAS_PER_BLOCK
from ethereum.exceptions import EthereumException
from ethereum_types.bytes import Bytes, Bytes20
from ethereum_types.numeric import U64, U256, Uint
from hypothesis import assume, given
from hypothesis import strategies as st
from hypothesis.strategies import composite, integers

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


@composite
def env_with_valid_gas_price(draw):
    env = draw(st.from_type(Environment))
    if env.gas_price < env.base_fee_per_gas:
        env = replace(
            env,
            # env.gas_price >= env.base_fee_per_gas is validated in `check_transaction`
            gas_price=draw(
                st.integers(
                    min_value=int(env.base_fee_per_gas), max_value=2**64 - 1
                ).map(Uint)
            ),
            # Values too high would cause taylor_exponential to run indefinitely.
            excess_blob_gas=draw(
                st.integers(0, 10 * int(TARGET_BLOB_GAS_PER_BLOCK)).map(U64)
            ),
        )
    return env


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

    @given(env=env_with_valid_gas_price(), tx=tx_without_code())
    def test_process_transaction(self, cairo_run, env: Environment, tx: Transaction):
        try:
            env_cairo, gas_cairo, logs_cairo = cairo_run("process_transaction", env, tx)
        except Exception as e:
            with strict_raises(type(e)):
                output_py = process_transaction(env, tx)
                # The Cairo Runner will raise if an exception is in the return values.
                if len(output_py) == 3:
                    raise output_py[2]
                assert env_cairo == env
                assert gas_cairo == output_py[0]
                assert logs_cairo == output_py[1]
            return

        gas_used, logs = process_transaction(env, tx)
        assert env_cairo == env
        assert gas_used == gas_cairo
        assert logs == logs_cairo

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

    @given(blocks=st.lists(st.builds(Block), max_size=300))
    def test_get_last_256_block_hashes(self, cairo_run, blocks):
        chain = BlockChain(blocks=blocks, state=State(), chain_id=U64(1))

        py_result = get_last_256_block_hashes(chain)
        cairo_result = cairo_run("get_last_256_block_hashes", chain)

        assert py_result == cairo_result
