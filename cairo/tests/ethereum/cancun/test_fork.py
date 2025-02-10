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
from ethereum.crypto.hash import Hash32, keccak256
from ethereum.exceptions import EthereumException
from ethereum_rlp import rlp
from ethereum_types.bytes import Bytes, Bytes0, Bytes8, Bytes20
from ethereum_types.numeric import U64, U256, Uint
from hypothesis import assume, given
from hypothesis import strategies as st
from hypothesis.strategies import composite, integers

from cairo_addons.testing.errors import strict_raises
from tests.ethereum.cancun.vm.test_interpreter import unimplemented_precompiles
from tests.utils.constants import OMMER_HASH
from tests.utils.errors import strict_raises
from tests.utils.strategies import (
    account_strategy,
    address,
    bytes32,
    small_bytes,
    state,
    uint,
)

MIN_BASE_FEE = 1_000


@composite
def tx_with_small_data(draw, gas_strategy=uint, gas_price_strategy=uint):
    # Generate access list
    access_list_entries = draw(
        st.lists(st.tuples(address, st.lists(bytes32, max_size=2)), max_size=3)
    )
    access_list = tuple(
        (addr, tuple(storage_keys)) for addr, storage_keys in access_list_entries
    )

    addr = (
        st.integers(min_value=0, max_value=2**160 - 1)
        .filter(lambda x: x not in unimplemented_precompiles)
        .map(lambda x: Bytes20(x.to_bytes(20, "little")))
        .map(Address)
    )

    to = st.one_of(addr, st.just(Bytes0()))

    # Define strategies for each transaction type
    legacy_tx = st.builds(
        LegacyTransaction,
        data=st.just(Bytes(bytes.fromhex("6060"))),
        to=to,
        gas=gas_strategy,
        gas_price=gas_price_strategy,
    )

    access_list_tx = st.builds(
        AccessListTransaction,
        data=st.just(Bytes(bytes.fromhex("6060"))),
        access_list=st.just(access_list),
        to=to,
        gas=gas_strategy,
        gas_price=gas_price_strategy,
    )

    base_fee_per_gas = draw(gas_price_strategy)
    max_priority_fee_per_gas = draw(gas_price_strategy)
    max_fee_per_gas = max_priority_fee_per_gas + base_fee_per_gas

    fee_market_tx = st.builds(
        FeeMarketTransaction,
        data=st.just(Bytes(bytes.fromhex("6060"))),
        access_list=st.just(access_list),
        to=to,
        gas=gas_strategy,
        max_priority_fee_per_gas=st.just(max_priority_fee_per_gas),
        max_fee_per_gas=st.just(max_fee_per_gas),
    )

    blob_tx = st.builds(
        BlobTransaction,
        data=st.just(Bytes(bytes.fromhex("6060"))),
        access_list=st.just(access_list),
        to=addr,
        gas=gas_strategy,
        max_priority_fee_per_gas=st.just(max_priority_fee_per_gas),
        max_fee_per_gas=st.just(max_fee_per_gas),
    )

    # Choose one transaction type
    tx = draw(st.one_of(legacy_tx, access_list_tx, fee_market_tx, blob_tx))

    return tx


@composite
def headers(draw):
    # Gas limit is in the order of magnitude of millions today,
    # 2**32 is a safe upper bound and 21_000 is the minimum amount of gas in a transaction.
    gas_limit = draw(st.integers(min_value=21_000, max_value=2**32 - 1).map(Uint))
    parent_header = draw(
        st.builds(
            Header,
            difficulty=uint,
            nonce=st.from_type(Bytes8),
            ommers_hash=st.just(OMMER_HASH).map(Hash32),
            gas_limit=st.just(gas_limit),
            gas_used=st.one_of(uint, st.just(gas_limit // Uint(2))),
            # Base fee per gas is in the order of magnitude of the GWEI today which is 10^9,
            # 2**48 is a safe upper bound with good slack.
            base_fee_per_gas=st.integers(min_value=0, max_value=2**48 - 1).map(Uint),
            prev_randao=bytes32,
            withdrawals_root=bytes32,
            parent_beacon_block_root=bytes32,
            transactions_root=bytes32,
            receipt_root=bytes32,
            parent_hash=bytes32,
        )
    )
    correct_base_fee = calculate_base_fee_per_gas(
        parent_header.gas_limit,
        parent_header.gas_limit,
        parent_header.gas_used,
        parent_header.base_fee_per_gas,
    )
    header = draw(
        st.builds(
            Header,
            parent_hash=st.one_of(
                st.just(keccak256(rlp.encode(parent_header))), st.from_type(Hash32)
            ),
            gas_limit=st.just(parent_header.gas_limit),
            gas_used=st.one_of(uint, st.just(parent_header.gas_limit // Uint(2))),
            base_fee_per_gas=st.one_of(
                st.just(correct_base_fee),
                st.integers(min_value=0, max_value=2**48 - 1).map(Uint),
            ),
            extra_data=st.one_of(small_bytes, bytes32.map(Bytes)),
            difficulty=uint,
            ommers_hash=st.just(OMMER_HASH).map(Hash32),
            nonce=st.from_type(Bytes8),
            number=st.one_of(
                st.just(parent_header.number + Uint(1)),
                uint,
            ),
            prev_randao=bytes32,
            withdrawals_root=bytes32,
            parent_beacon_block_root=bytes32,
            transactions_root=bytes32,
            receipt_root=bytes32,
        )
    )
    return parent_header, header


@composite
def tx_with_sender_in_state(
    draw,
    # We need to set a high tx gas so that tx.gas > intrinsic cost and base_fee < gas_price
    tx_strategy=tx_with_small_data(
        gas_strategy=st.integers(min_value=2**16, max_value=2**26 - 1).map(Uint),
        gas_price_strategy=st.integers(
            min_value=MIN_BASE_FEE - 1, max_value=2**64
        ).map(Uint),
    ),
    state_strategy=state,
    account_strategy=account_strategy,
):
    state = draw(state_strategy)
    account = draw(account_strategy)
    # 2 * chain_id + 35 + v must be less than 2^64 for the signature of a legacy transaction to be valid
    chain_id = draw(st.integers(min_value=1, max_value=(2**64 - 37) // 2).map(U64))
    tx = draw(tx_strategy)
    nonce = U256(account.nonce)
    # To avoid useless failures, set nonce of the transaction to the nonce of the sender account
    tx = (
        replace(tx, chain_id=chain_id, nonce=nonce)
        if not isinstance(tx, LegacyTransaction)
        else replace(tx, nonce=nonce)
    )
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
        v_or_y_parity["v"] = U256(U64(2) * chain_id + U64(35) + U64(signature.v))
    else:
        v_or_y_parity["y_parity"] = U256(signature.v)
    tx = replace(tx, r=U256(signature.r), s=U256(signature.s), **v_or_y_parity)

    should_add_sender_to_state = draw(integers(0, 99)) < 80
    if should_add_sender_to_state:
        sender = Address(int(expected_address).to_bytes(20, "little"))
        set_account(state, sender, account)
    return tx, state, chain_id


@composite
def env_with_valid_gas_price(draw):
    env = draw(st.from_type(Environment))
    if env.gas_price < env.base_fee_per_gas:
        env.gas_price = draw(
            st.integers(min_value=int(env.base_fee_per_gas), max_value=2**64 - 1).map(
                Uint
            )
        )
    # Values too high would cause taylor_exponential to run indefinitely.
    env.excess_blob_gas = draw(
        st.integers(0, 10 * int(TARGET_BLOB_GAS_PER_BLOCK)).map(U64)
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

    @given(headers=headers())
    def test_validate_header(self, cairo_run, headers: Tuple[Header, Header]):
        parent_header, header = headers
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

    @given(env=env_with_valid_gas_price(), data=tx_with_sender_in_state())
    def test_process_transaction(
        self, cairo_run, env: Environment, data: Tuple[Transaction, State, U64]
    ):
        # The Cairo Runner will raise if an exception is in the return values OR if
        # an assert expression fails (e.g. InvalidBlock)
        tx, __, _ = data
        try:
            env_cairo, cairo_result = cairo_run("process_transaction", env, tx)
        except Exception as cairo_e:
            # 1. Handle exceptions thrown
            try:
                output_py = process_transaction(env, tx)
            except Exception as thrown_exception:
                assert type(cairo_e) is type(thrown_exception)
                return

            # 2. Handle exceptions in return values
            # Never reached with the current strategy and 300 examples
            # For that, it would be necessary to send a tx with correct data
            # that would raise inside execute_code
            with strict_raises(type(cairo_e)):
                if len(output_py) == 3:
                    raise output_py[2]
            return

        gas_used, logs, error = process_transaction(env, tx)
        assert env_cairo == env
        assert gas_used == cairo_result[0]
        assert logs == cairo_result[1]
        assert error == cairo_result[2]

    @given(
        data=tx_with_sender_in_state(),
        gas_available=...,
        base_fee_per_gas=...,
        excess_blob_gas=...,
    )
    def test_check_transaction(
        self,
        cairo_run_py,
        data,
        gas_available: Uint,
        base_fee_per_gas: Uint,
        excess_blob_gas: U64,
    ):
        tx, state, chain_id = data
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
