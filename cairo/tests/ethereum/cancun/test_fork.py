from collections import defaultdict
from dataclasses import replace
from typing import Optional, Tuple

from eth_abi.abi import encode
from eth_account import Account as EthAccount
from eth_keys.datatypes import PrivateKey
from ethereum.cancun.blocks import Block, Header, Log
from ethereum.cancun.fork import (
    GAS_LIMIT_ADJUSTMENT_FACTOR,
    BlockChain,
    apply_body,
    calculate_base_fee_per_gas,
    check_gas_limit,
    check_transaction,
    get_last_256_block_hashes,
    make_receipt,
    process_transaction,
    validate_header,
)
from ethereum.cancun.fork_types import Account, Address
from ethereum.cancun.state import State, set_account
from ethereum.cancun.transactions import (
    AccessListTransaction,
    BlobTransaction,
    FeeMarketTransaction,
    LegacyTransaction,
    Transaction,
    encode_transaction,
    signing_hash_155,
    signing_hash_1559,
    signing_hash_2930,
    signing_hash_4844,
)
from ethereum.cancun.trie import copy_trie
from ethereum.cancun.vm import Environment
from ethereum.cancun.vm.gas import TARGET_BLOB_GAS_PER_BLOCK
from ethereum.exceptions import EthereumException
from ethereum_types.bytes import Bytes, Bytes0, Bytes20
from ethereum_types.numeric import U64, U256, Uint
from hypothesis import assume, given
from hypothesis import strategies as st
from hypothesis.strategies import composite, integers

from tests.ethereum.cancun.vm.test_interpreter import unimplemented_precompiles
from tests.utils.args_gen import Environment
from tests.utils.constants import COINBASE, OTHER, OWNER, TRANSACTION_GAS_LIMIT, signers
from tests.utils.errors import strict_raises
from tests.utils.strategies import account_strategy, address, bytes32, state, uint

MIN_BASE_FEE = 1_000


@composite
def apply_body_data(draw, excess_blob_gas_strategy=excess_blob_gas):
    """Creates test data for apply_body including ERC20 transfer transactions"""
    state = draw(erc20_state)

    # Get ERC20 contract
    erc20 = get_contract("ERC20", "KethToken")
    amount = int(1e18)

    # Create base ERC20 transfer transactions
    raw_transactions = [
        erc20.transfer(OWNER, amount, signer=OTHER),
        erc20.transfer(OTHER, amount, signer=OWNER),
        erc20.transfer(OTHER, amount, signer=OWNER),
        erc20.approve(OWNER, 2**256 - 1, signer=OTHER),
        erc20.transferFrom(OTHER, OWNER, amount // 3, signer=OWNER),
    ]

    # Transform and sign transactions
    nonces = defaultdict(int)
    erc20_transactions = []

    for tx in raw_transactions:
        signer = tx.pop("signer")

        # Add required transaction fields
        tx["gas"] = TRANSACTION_GAS_LIMIT
        tx["gasPrice"] = MIN_BASE_FEE
        tx["nonce"] = nonces[signer]
        nonces[signer] += 1

        # Sign transaction
        signed_tx = EthAccount.sign_transaction(tx, signers[signer])

        # Create LegacyTransaction with signed values
        legacy_tx = LegacyTransaction(
            nonce=U256(tx["nonce"]),
            gas_price=Uint(tx["gasPrice"]),
            gas=Uint(tx["gas"]),
            to=Address(bytes.fromhex(erc20.address[2:])),
            value=U256(tx.get("value", 0)),
            data=Bytes(bytes.fromhex(tx["data"][2:])),
            v=U256(signed_tx.v),
            r=U256(signed_tx.r),
            s=U256(signed_tx.s),
        )
        erc20_transactions.append(legacy_tx)

    # Convert transactions to RLP format
    transactions = tuple(encode_transaction(tx) for tx in erc20_transactions)

    # Rest of the test data generation
    block_hashes = draw(st.lists(bytes32, max_size=256))
    coinbase = Address(bytes.fromhex(COINBASE[2:]))
    block_number = draw(st.from_type(Uint))
    base_fee_per_gas = Uint(MIN_BASE_FEE)
    block_gas_limit = Uint(30_000_000)
    block_time = draw(st.from_type(U256))
    prev_randao = draw(bytes32)
    parent_beacon_block_root = draw(bytes32)
    excess_blob_gas = draw(excess_blob_gas_strategy)
    chain_id = draw(uint64)

    return {
        "state": state,
        "block_hashes": block_hashes,
        "coinbase": coinbase,
        "block_number": block_number,
        "base_fee_per_gas": base_fee_per_gas,
        "block_gas_limit": block_gas_limit,
        "block_time": block_time,
        "prev_randao": prev_randao,
        "transactions": transactions,
        "chain_id": chain_id,
        "parent_beacon_block_root": parent_beacon_block_root,
        "excess_blob_gas": excess_blob_gas,
    }


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

    should_add_sender_to_state = draw(integers(0, 99)) < probabilities
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

    @reproduce_failure("6.124.3", b"AXicY3BkQEAACrcBhw==")
    @given(data=apply_body_data())
    def test_apply_body(
        self,
        cairo_run_py,
        data,
    ):
        accounts, storage_tries = _create_erc20_data()
        # Create constant state
        state = State(
            _main_trie=Trie(
                secured=True,
                default=None,
                _data=dict(accounts),
            ),
            _storage_tries=dict(storage_tries),
            _snapshots=[
                (
                    Trie(
                        secured=True,
                        default=None,
                        _data=dict(accounts),
                    ),
                    {k: copy_trie(v) for k, v in storage_tries.items()},
                )
            ],
            created_accounts=set(),
        )

        withdrawals = ()  # Empty withdrawals for now
        kwargs = {**data, "withdrawals": withdrawals, "state": state}

        try:
            # TODO: Use cairo_run and Rust CairoVM
            cairo_state, cairo_result = cairo_run_py("apply_body", **kwargs)
        except Exception as e:
            # If Cairo implementation raises an error, Python implementation should too
            with strict_raises(type(e)):
                apply_body(**kwargs)
            return
        dummy_root = Hash32(int(0).to_bytes(32, "big"))
        assert cairo_result.transactions_root == dummy_root
        assert cairo_result.receipt_root == dummy_root
        assert cairo_result.state_root == dummy_root
        assert cairo_result.withdrawals_root == dummy_root

        output = apply_body(**kwargs)

        assert cairo_result.block_gas_used == output.block_gas_used
        assert cairo_result.blob_gas_used == output.blob_gas_used
        assert cairo_result.block_logs_bloom == output.block_logs_bloom
        assert cairo_state == data["state"]


def _create_erc20_data():
    """Helper to create the fixed ERC20 data structures"""
    erc20_contract = get_contract("ERC20", "KethToken")
    erc20_address = Address(bytes.fromhex(erc20_contract.address[2:]))

    accounts = {
        erc20_address: Account(
            balance=U256(0),
            nonce=Uint(0),
            code=bytes(erc20_contract.bytecode_runtime),
        ),
        Address(bytes.fromhex(OTHER[2:])): Account(
            balance=U256(int(1e18)), nonce=Uint(0), code=bytes()
        ),
        Address(bytes.fromhex(OWNER[2:])): Account(
            balance=U256(int(1e18)), nonce=Uint(0), code=bytes()
        ),
        Address(bytes.fromhex(COINBASE[2:])): Account(
            balance=U256(int(1e18)), nonce=Uint(0), code=bytes()
        ),
    }

    storage_data = {
        Bytes32(U256(0).to_be_bytes32()): U256.from_be_bytes(
            b"KethToken".ljust(31, b"\x00") + bytes([len(b"KethToken") * 2])
        ),
        Bytes32(U256(1).to_be_bytes32()): U256.from_be_bytes(
            b"KETH".ljust(31, b"\x00") + bytes([len(b"KETH") * 2])
        ),
        Bytes32(U256(2).to_be_bytes32()): U256(int(1e18)),
        Bytes32(keccak256(encode(["address", "uint8"], [OWNER[2:], 3]))): U256(
            int(1e18)
        ),
    }

    storage_tries = {
        erc20_address: Trie(secured=True, default=U256(0), _data=dict(storage_data))
    }

    return accounts, storage_tries
