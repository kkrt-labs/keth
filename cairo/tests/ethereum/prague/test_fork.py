import dataclasses
from collections import defaultdict
from dataclasses import replace
from typing import Optional, Tuple

from eth_abi.abi import encode
from eth_account import Account as EthAccount
from eth_keys.datatypes import PrivateKey
from ethereum.prague.blocks import (
    Block,
    Header,
    Log,
    Receipt,
    Withdrawal,
    encode_receipt,
)
from ethereum.prague.fork import (
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
from ethereum.prague.fork_types import Account, Address, VersionedHash
from ethereum.prague.state import State, set_account
from ethereum.prague.transactions import (
    Access,
    AccessListTransaction,
    BlobTransaction,
    FeeMarketTransaction,
    LegacyTransaction,
    Transaction,
    calculate_intrinsic_cost,
    encode_transaction,
    signing_hash_155,
    signing_hash_1559,
    signing_hash_2930,
    signing_hash_4844,
    signing_hash_pre155,
)
from ethereum.prague.trie import Trie, root
from ethereum.prague.utils.address import to_address
from ethereum.prague.vm import BlockEnvironment, BlockOutput, TransactionEnvironment
from ethereum.prague.vm.gas import TARGET_BLOB_GAS_PER_BLOCK
from ethereum.crypto.hash import Hash32, keccak256
from ethereum.exceptions import EthereumException
from ethereum_rlp import rlp
from ethereum_types.bytes import Bytes, Bytes0, Bytes8, Bytes20, Bytes32
from ethereum_types.numeric import U64, U256, Uint
from hypothesis import assume, given, settings
from hypothesis import strategies as st
from hypothesis.strategies import composite, integers

from cairo_addons.testing.errors import strict_raises
from keth_types.types import EMPTY_BYTES_HASH, EMPTY_TRIE_HASH
from tests.utils.constants import (
    COINBASE,
    OMMER_HASH,
    OTHER,
    OWNER,
    TRANSACTION_GAS_LIMIT,
    signers,
)
from tests.utils.solidity import get_contract
from tests.utils.strategies import (
    BEACON_ROOTS_ACCOUNT,
    BEACON_ROOTS_ADDRESS,
    SYSTEM_ACCOUNT,
    SYSTEM_ADDRESS,
    account_strategy,
    address_zero,
    bounded_u256_strategy,
    bytes32,
    empty_block_output,
    empty_state,
    excess_blob_gas,
    small_bytes,
    uint,
)

MIN_BASE_FEE = 1_000


@composite
def apply_body_data(draw, excess_blob_gas_strategy=excess_blob_gas):
    """Creates test data for apply_body including ERC20 transfer transactions"""

    # Get ERC20 contract
    erc20 = get_contract("ERC20", "KethToken")
    amount = int(1e18)

    # Create base ERC20 transfer transactions
    raw_transactions = [
        erc20.transfer(OTHER, amount, signer=OWNER),
        erc20.transfer(OWNER, amount, signer=OTHER),
        erc20.transfer(OTHER, amount, signer=OWNER),
        erc20.approve(OWNER, 2**256 - 1, signer=OTHER),
        erc20.transferFrom(OTHER, OWNER, amount // 3, signer=OWNER),
    ]

    # Transform and sign transactions
    nonces = defaultdict(int)
    erc20_transactions = []
    chain_id = 1

    for tx in raw_transactions:
        signer = tx.pop("signer")

        # Add required transaction fields
        tx["gas"] = TRANSACTION_GAS_LIMIT
        tx["gasPrice"] = MIN_BASE_FEE
        tx["nonce"] = nonces[signer]
        tx["chainId"] = chain_id
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
    block_hashes = draw(st.lists(bytes32, max_size=256, unique=True))
    coinbase = Address(bytes.fromhex(COINBASE[2:]))
    block_number = draw(st.from_type(Uint))
    base_fee_per_gas = Uint(MIN_BASE_FEE)
    block_gas_limit = Uint(30_000_000)
    block_time = draw(st.from_type(U256))
    prev_randao = draw(bytes32)
    parent_beacon_block_root = draw(bytes32)
    excess_blob_gas = draw(excess_blob_gas_strategy)

    return {
        "block_hashes": block_hashes,
        "coinbase": coinbase,
        "block_number": block_number,
        "base_fee_per_gas": base_fee_per_gas,
        "block_gas_limit": block_gas_limit,
        "block_time": block_time,
        "prev_randao": prev_randao,
        "transactions": transactions,
        "chain_id": U64(chain_id),
        "parent_beacon_block_root": parent_beacon_block_root,
        "excess_blob_gas": excess_blob_gas,
    }


def get_blob_tx_with_tx_sender_in_state():
    chain_id = U64(1)
    # from ethereum tx with hash: 0x8686183fd3a0a2b22ee6616cea79ca95f2e1da3044132687858671115cb61ded
    tx = BlobTransaction(
        data=Bytes(b""),
        access_list=(),
        to=to_address(Uint(int("0xff00000000000000000000000000000000000480", 16))),
        gas=Uint(int("0x5208", 16)),
        max_priority_fee_per_gas=Uint(int("0x12a9e8880", 16)),
        max_fee_per_gas=Uint(int("0x37fdb9980", 16)),
        value=U256(int("0x0", 16)),
        nonce=U256(int("0x1bfec", 16)),
        chain_id=chain_id,
        blob_versioned_hashes=(
            VersionedHash(
                bytes.fromhex(
                    "012349ab976176f8e442ddf213adf04de969a2e698b5fe2b630d96563eacd977"
                )
            ),
            VersionedHash(
                bytes.fromhex(
                    "01b24f1b540c49ce5af19385c1e9b512a34f2d19115d21386ba90c9da85ae85c"
                )
            ),
            VersionedHash(
                bytes.fromhex(
                    "01247acd4e3b79241271ff98e449e7c4db539c92f08a89166192d8b79346cd4b"
                )
            ),
        ),
        max_fee_per_blob_gas=U256(int("0x111aace52", 16)),
        # Signature fields
        r=U256(
            int(
                "0x1acaed4cc56f5e0f8a53c87ce7257e460aa2df421271f39271e5d4cd8af21ee4", 16
            )
        ),
        s=U256(
            int(
                "0x35c0c6ab54af28f3ef37daec92e6c128a5415a9e15495d7f248027d9c8f5da03", 16
            )
        ),
        y_parity=U256(int("0x1", 16)),
    )

    # created to ensure the tx will pass check_transaction
    sender = to_address(Uint(int("0xdbbe3d8c2d2b22a2611c5a94a9a12c2fcd49eb29", 16)))
    sender_account = Account(
        balance=U256(int("0x1000000000000000000", 16)),
        nonce=U256(int("0x1bfec", 16)),
        code=bytearray(),
        storage_root=EMPTY_TRIE_HASH,
        code_hash=EMPTY_BYTES_HASH,
    )
    # Empty state
    state = State(
        _main_trie=Trie[Address, Optional[Account]](
            secured=True, default=None, _data=defaultdict(lambda: None, {})
        ),
        _storage_tries=defaultdict(lambda: None, {}),
        _snapshots=[
            (
                Trie[Address, Optional[Account]](
                    secured=True, default=None, _data=defaultdict(lambda: None, {})
                ),
                defaultdict(lambda: U256(0), {}),
            )
        ],
        created_accounts=set(),
    )
    set_account(state, sender, sender_account)
    env = BlockEnvironment(
        chain_id=chain_id,
        state=state,
        block_gas_limit=Uint(int("0x1000000", 16)),
        block_hashes=[],
        coinbase=address_zero,
        number=Uint(0),
        base_fee_per_gas=Uint(int("0x100000", 16)),
        time=U256(0),
        prev_randao=Bytes32(b"\x00" * 32),
        excess_blob_gas=U64(0),
        parent_beacon_block_root=Bytes32(b"\x00" * 32),
    )

    return tx, env, chain_id


@composite
def tx_with_small_data(draw, gas_strategy=uint, gas_price_strategy=uint):
    access_list = draw(st.lists(st.builds(Access)).map(tuple))

    addr = (
        st.integers(min_value=0, max_value=2**160 - 1)
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
        value=bounded_u256_strategy(max_value=2**128 - 1),
    )

    access_list_tx = st.builds(
        AccessListTransaction,
        data=st.just(Bytes(bytes.fromhex("6060"))),
        access_list=st.just(access_list),
        to=to,
        gas=gas_strategy,
        gas_price=gas_price_strategy,
        value=bounded_u256_strategy(max_value=2**128 - 1),
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
        value=bounded_u256_strategy(max_value=2**128 - 1),
    )

    blob_tx = st.builds(
        BlobTransaction,
        data=st.just(Bytes(bytes.fromhex("6060"))),
        access_list=st.just(access_list),
        to=addr,
        gas=gas_strategy,
        max_priority_fee_per_gas=st.just(max_priority_fee_per_gas),
        max_fee_per_gas=st.just(max_fee_per_gas),
        blob_versioned_hashes=st.lists(st.from_type(VersionedHash), max_size=3).map(
            tuple
        ),
        value=bounded_u256_strategy(max_value=2**128 - 1),
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
            number=uint,
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
            difficulty=st.one_of(uint, st.just(Uint(0))),
            ommers_hash=st.just(OMMER_HASH).map(Hash32),
            nonce=st.one_of(
                st.from_type(Bytes8),
                st.just(Bytes8(int(0).to_bytes(8, "big"))),
            ),
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
    account_strategy=account_strategy,
):
    block_env = draw(st.from_type(BlockEnvironment))
    # Values too high would cause taylor_exponential to run indefinitely.
    block_env.excess_blob_gas = draw(
        st.integers(0, 10 * int(TARGET_BLOB_GAS_PER_BLOCK)).map(U64)
    )
    state = block_env.state
    # Explicitly clean any snapshot in the state - as in the initial state of a tx, there are no snapshots.
    state._snapshots = []
    tx = draw(tx_strategy)
    account = draw(account_strategy)
    private_key = draw(st.from_type(PrivateKey))
    # the origin address is derived from the signature.
    expected_address = int(private_key.public_key.to_address(), 16)
    if draw(integers(0, 99)) < 80:
        # to ensure the account has enough balance and tx.gas > intrinsic_cost
        # also that the code is empty
        if calculate_intrinsic_cost(tx) > tx.gas:
            tx = dataclasses.replace(
                tx, gas=(calculate_intrinsic_cost(tx) + Uint(10000))
            )

        account_address = to_address(Uint(expected_address))
        if account_address in state._storage_tries:
            account_storage_root = root(state._storage_tries[account_address])
        else:
            account_storage_root = EMPTY_TRIE_HASH

        if hasattr(tx, "max_priority_fee_per_gas"):
            effective_gas_price = max(
                tx.max_priority_fee_per_gas, block_env.base_fee_per_gas
            )
        else:
            effective_gas_price = tx.gas_price

        set_account(
            state,
            to_address(Uint(expected_address)),
            Account(
                balance=U256(tx.value) * U256(effective_gas_price)
                + U256(block_env.excess_blob_gas)
                + U256(10000),
                nonce=account.nonce,
                code=bytes(),
                code_hash=EMPTY_BYTES_HASH,
                storage_root=account_storage_root,
            ),
        )
    # 2 * chain_id + 35 + v must be less than 2^64 for the signature of a legacy transaction to be valid
    chain_id = draw(st.integers(min_value=1, max_value=(2**64 - 37) // 2).map(U64))
    nonce = U256(account.nonce)
    # To avoid useless failures, set nonce of the transaction to the nonce of the sender account
    tx = (
        replace(tx, chain_id=chain_id, nonce=nonce)
        if not isinstance(tx, LegacyTransaction)
        else replace(tx, nonce=nonce)
    )

    pre_155 = draw(integers(0, 99)) < 50
    if isinstance(tx, LegacyTransaction):
        if pre_155:
            signature = private_key.sign_msg_hash(signing_hash_pre155(tx))
        else:
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
        if pre_155:
            v_or_y_parity["v"] = U256(signature.v)
        else:
            v_or_y_parity["v"] = U256(U64(2) * chain_id + U64(35) + U64(signature.v))
    else:
        v_or_y_parity["y_parity"] = U256(signature.v)
    tx = replace(tx, r=U256(signature.r), s=U256(signature.s), **v_or_y_parity)

    should_add_sender_to_state = draw(integers(0, 99)) < 80
    if should_add_sender_to_state:
        sender = Address(int(expected_address).to_bytes(20, "little"))
        set_account(state, sender, account)
    return tx, block_env, chain_id


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

    @given(headers=headers(), state=empty_state)
    def test_validate_header(
        self, cairo_run, headers: Tuple[Header, Header], state: State
    ):
        parent_header, header = headers
        blocks = [
            Block(header=parent_header, transactions=[], ommers=[], withdrawals=[])
        ]
        chain = BlockChain(blocks=blocks, state=state, chain_id=U64(1))
        try:
            cairo_run("validate_header", chain=chain, header=header)
        except Exception as e:
            with strict_raises(type(e)):
                validate_header(chain=chain, header=header)
            return

        validate_header(chain=chain, header=header)

    @given(gas_limit=..., parent_gas_limit=...)
    def test_check_gas_limit(self, cairo_run, gas_limit: Uint, parent_gas_limit: Uint):
        assume(
            parent_gas_limit + parent_gas_limit // GAS_LIMIT_ADJUSTMENT_FACTOR
            < Uint(2**128)
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

    @given(data=tx_with_sender_in_state(), index=uint, block_output=empty_block_output)
    def test_process_transaction(
        self,
        cairo_run,
        data: Tuple[Transaction, BlockEnvironment, TransactionEnvironment, U64],
        index: Uint,
        block_output: BlockOutput,
    ):
        tx, block_env, _ = data

        encoded_tx = encode_transaction(tx)

        try:
            returned_block_env_cairo, returned_block_output_cairo = cairo_run(
                "process_transaction", block_env, block_output, encoded_tx, index
            )
        except Exception as e:
            with strict_raises(type(e)):
                process_transaction(block_env, block_output, tx, index)
            return

        process_transaction(block_env, block_output, tx, index)

        assert returned_block_env_cairo == block_env
        assert returned_block_output_cairo == block_output

    @given(block_output=empty_block_output)
    def test_check_transaction(
        self,
        cairo_run,
        block_output: BlockOutput,
    ):
        tx, block_env, _ = get_blob_tx_with_tx_sender_in_state()

        try:
            block_env_cairo, output_cairo = cairo_run(
                "check_transaction",
                block_env=block_env,
                block_output=block_output,
                tx=tx,
            )
        except Exception as e:
            with strict_raises(type(e)):
                check_transaction(block_env, block_output, tx)
            return

        output = check_transaction(block_env, block_output, tx)

        assert block_env == block_env_cairo
        assert output == output_cairo

    @given(blocks=st.lists(st.builds(Block), max_size=300), empty_state=empty_state)
    def test_get_last_256_block_hashes(self, cairo_run, blocks, empty_state: State):
        chain = BlockChain(blocks=blocks, state=empty_state, chain_id=U64(1))

        py_result = get_last_256_block_hashes(chain)
        cairo_result = cairo_run("get_last_256_block_hashes", chain)

        assert py_result == cairo_result

    @given(header=...)
    def test_keccak256_header(self, cairo_run, header: Header):
        try:
            cairo_result = cairo_run("keccak256_header", header)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                keccak256(rlp.encode(header))
            return

        assert cairo_result == keccak256(rlp.encode(header))

    @given(data=apply_body_data(), withdrawals=...)
    @settings(max_examples=3)
    def test_apply_body(self, cairo_run, data, withdrawals: Tuple[Withdrawal, ...]):
        accounts, storage_tries = _create_erc20_data()
        # Create constant state
        state = State(
            _main_trie=Trie(
                secured=True,
                default=None,
                _data=defaultdict(lambda: None, accounts),
            ),
            _storage_tries=storage_tries,
            _snapshots=[],
            created_accounts=set(),
        )
        # Add the system address
        set_account(
            state,
            SYSTEM_ADDRESS,
            SYSTEM_ACCOUNT,
        )

        # Add the beacon roots contract
        set_account(
            state,
            BEACON_ROOTS_ADDRESS,
            BEACON_ROOTS_ACCOUNT,
        )

        block_env = BlockEnvironment(
            chain_id=data["chain_id"],
            state=state,
            block_gas_limit=data["block_gas_limit"],
            block_hashes=data["block_hashes"],
            coinbase=data["coinbase"],
            number=data["block_number"],
            base_fee_per_gas=data["base_fee_per_gas"],
            time=data["block_time"],
            prev_randao=data["prev_randao"],
            excess_blob_gas=data["excess_blob_gas"],
            parent_beacon_block_root=data["parent_beacon_block_root"],
        )

        transactions = data["transactions"]

        try:
            block_env_cairo, cairo_block_output = cairo_run(
                "apply_body", block_env, transactions, withdrawals
            )
        except Exception as e:
            with strict_raises(type(e)):
                apply_body(block_env, transactions, withdrawals)
            return

        output = apply_body(block_env, transactions, withdrawals)

        assert block_env_cairo == block_env
        assert cairo_block_output == output


def _create_erc20_data():
    """Helper to create the fixed ERC20 data structures"""
    erc20_contract = get_contract("ERC20", "KethToken")
    erc20_address = Address(bytes.fromhex(erc20_contract.address[2:]))

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

    storage_tries = defaultdict(
        lambda: Trie(secured=True, default=U256(0), _data=defaultdict(lambda: U256(0))),
        {
            erc20_address: Trie(
                secured=True,
                default=U256(0),
                _data=defaultdict(lambda: U256(0), storage_data),
            )
        },
    )

    erc20_storage_root = root(storage_tries[erc20_address])

    accounts = {
        erc20_address: Account(
            balance=U256(0),
            nonce=Uint(0),
            code=bytes(erc20_contract.bytecode_runtime),
            storage_root=erc20_storage_root,
            code_hash=keccak256(bytes(erc20_contract.bytecode_runtime)),
        ),
        Address(bytes.fromhex(OTHER[2:])): Account(
            balance=U256(int(1e18)),
            nonce=Uint(0),
            code=bytes(),
            storage_root=EMPTY_TRIE_HASH,
            code_hash=EMPTY_BYTES_HASH,
        ),
        Address(bytes.fromhex(OWNER[2:])): Account(
            balance=U256(int(1e18)),
            nonce=Uint(0),
            code=bytes(),
            storage_root=EMPTY_TRIE_HASH,
            code_hash=EMPTY_BYTES_HASH,
        ),
        Address(bytes.fromhex(COINBASE[2:])): Account(
            balance=U256(int(1e18)),
            nonce=Uint(0),
            code=bytes(),
            storage_root=EMPTY_TRIE_HASH,
            code_hash=EMPTY_BYTES_HASH,
        ),
    }

    return accounts, storage_tries


class TestEncodeReceipt:
    @given(tx=..., receipt=...)
    def test_encode_receipt(self, cairo_run, tx: Transaction, receipt: Receipt):
        cairo_result = cairo_run("encode_receipt", tx, receipt)
        assert encode_receipt(tx, receipt) == cairo_result
