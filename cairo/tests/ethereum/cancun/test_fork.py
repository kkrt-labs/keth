import json
from collections import defaultdict
from dataclasses import replace
from pathlib import Path
from typing import Optional, Tuple

import pytest
from eth_abi.abi import encode
from eth_account import Account as EthAccount
from eth_keys.datatypes import PrivateKey
from ethereum.cancun.blocks import Block, Header, Log, Withdrawal
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
    state_transition,
    validate_header,
)
from ethereum.cancun.fork_types import Account, Address, VersionedHash
from ethereum.cancun.state import State, TransientStorage, set_account
from ethereum.cancun.transactions import (
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
from ethereum.cancun.trie import Trie
from ethereum.cancun.utils.address import to_address
from ethereum.cancun.vm import Environment
from ethereum.cancun.vm.gas import TARGET_BLOB_GAS_PER_BLOCK, calculate_excess_blob_gas
from ethereum.crypto.hash import Hash32, keccak256
from ethereum.exceptions import EthereumException
from ethereum.utils.hexadecimal import hex_to_bytes, hex_to_u256, hex_to_uint
from ethereum_rlp import rlp
from ethereum_spec_tools.evm_tools.loaders.fixture_loader import Load
from ethereum_types.bytes import Bytes, Bytes0, Bytes8, Bytes20, Bytes32
from ethereum_types.numeric import U64, U256, Uint
from hypothesis import assume, given, settings
from hypothesis import strategies as st
from hypothesis.strategies import composite, integers

from cairo_addons.testing.errors import strict_raises
from tests.ef_tests.helpers.load_state_tests import convert_defaultdict
from tests.ethereum.cancun.vm.test_interpreter import unimplemented_precompiles
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
    address,
    address_zero,
    bounded_u256_strategy,
    bytes32,
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
    env = Environment(
        caller=sender,
        block_hashes=[],
        origin=sender,
        coinbase=address_zero,
        number=Uint(0),
        gas_limit=Uint(int("0x1000000", 16)),
        gas_price=Uint(0),
        time=U256(0),
        prev_randao=Bytes32(b"\x00" * 32),
        state=state,
        chain_id=chain_id,
        traces=[],
        base_fee_per_gas=Uint(int("0x100000", 16)),
        excess_blob_gas=U64(0),
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
        transient_storage=TransientStorage(),
    )

    return tx, env, chain_id


@composite
def tx_with_small_data(draw, gas_strategy=uint, gas_price_strategy=uint):
    access_list = draw(
        st.lists(
            st.tuples(address, st.lists(bytes32, max_size=3).map(tuple)), max_size=3
        ).map(tuple)
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
    state = env.state
    tx = draw(tx_strategy)
    account = draw(account_strategy)
    private_key = draw(st.from_type(PrivateKey))
    expected_address = int(private_key.public_key.to_address(), 16)
    if draw(integers(0, 99)) < 80:
        # to ensure the account has enough balance and tx.gas > intrinsic_cost
        # also that the code is empty
        env.origin = to_address(Uint(expected_address))
        if calculate_intrinsic_cost(tx) > tx.gas:
            tx = replace(tx, gas=(calculate_intrinsic_cost(tx) + Uint(10000)))

        set_account(
            state,
            to_address(Uint(expected_address)),
            Account(
                balance=U256(tx.value) * U256(env.gas_price)
                + U256(env.excess_blob_gas)
                + U256(10000),
                nonce=account.nonce,
                code=bytes(),
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
    return tx, env, chain_id


# cspell:disable
def get_valid_chain_and_block():
    block = Block(
        header=Header(
            parent_hash=b"?N\x87\x0c\xec#\x95\x83\xccV\xa2Q\xa5J\x8a\x17\xe9`e\xb5\xe7:X\xa6\x89Z\x0e\xff\xd8\xcfC\x97",
            ommers_hash=b"\x1d\xccM\xe8\xde\xc7]z\xab\x85\xb5g\xb6\xcc\xd4\x1a\xd3\x12E\x1b\x94\x8at\x13\xf0\xa1B\xfd@\xd4\x93G",
            coinbase=b"\xba^\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
            state_root=b'\xb0\xb2N_\x0fU\x1c\xd4\x83%\x05q\xae\xb4X\xb7Hn\xfe\xa3\xe3\x7fB\x05"\x991 4\xd1\xb5\x1f',
            transactions_root=b" dj7\x13k\xa6@d\x9c\x06\xfe\xfc\x95\xa3\xc8\x91\x12v\x984w \xb9;)}-\xbe\xaf\x12\xdc",
            receipt_root=b"]r\x16g\xf3\xf4\x1cn\x8a^c\x0b,_%\x98U\xd26U\x13)\\O\xd0\xc5\xd0T\x98\xced\x89",
            bloom=b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
            difficulty=Uint(0),
            number=Uint(2),
            gas_limit=Uint(10000000000),
            gas_used=Uint(43104),
            timestamp=U256(2000),
            extra_data=b"B",
            prev_randao=b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00",
            nonce=b"\x00\x00\x00\x00\x00\x00\x00\x00",
            base_fee_per_gas=Uint(766),
            withdrawals_root=b"V\xe8\x1f\x17\x1b\xccU\xa6\xff\x83E\xe6\x92\xc0\xf8n[H\xe0\x1b\x99l\xad\xc0\x01b/\xb5\xe3c\xb4!",
            blob_gas_used=U64(0),
            excess_blob_gas=U64(0),
            parent_beacon_block_root=b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        ),
        transactions=(
            b"\x02\xf8e\x01\x02\x80\x82\x03\xe8\x83\x01\x86\xa0\x94\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\x80\x80\xc0\x01\xa0e4\x05\xd0\x88\x08[\xb3\x02\xf0\xe7L%\xf3\xf42rv\x9d\x87\xae\xed\xe9\xed\x9ft\x17G/\xcci\x98\xa0&\x8d\x08\x89X\x9c\xb9-\x18\xa5i\xc2\x8e\x85\x1b\xb3.\xda4\xea\xebq\r@D\xbe\x19\x9d\xb2\xf1\xd1\xee",
        ),
        ommers=(),
        withdrawals=(),
    )
    chain = BlockChain(
        blocks=[
            Block(
                header=Header(
                    parent_hash=b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
                    ommers_hash=b"\x1d\xccM\xe8\xde\xc7]z\xab\x85\xb5g\xb6\xcc\xd4\x1a\xd3\x12E\x1b\x94\x8at\x13\xf0\xa1B\xfd@\xd4\x93G",
                    coinbase=b"\xba^\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
                    state_root=b"/q\x1b\xa1\xae\xed\xb1\xd4\xf4|\x9f\x10\x1fw\x8b\xbcy\xe9\xaaF\xc3u\x0cC\xf6V)M\x9a\x8d\xef-",
                    transactions_root=b"V\xe8\x1f\x17\x1b\xccU\xa6\xff\x83E\xe6\x92\xc0\xf8n[H\xe0\x1b\x99l\xad\xc0\x01b/\xb5\xe3c\xb4!",
                    receipt_root=b"V\xe8\x1f\x17\x1b\xccU\xa6\xff\x83E\xe6\x92\xc0\xf8n[H\xe0\x1b\x99l\xad\xc0\x01b/\xb5\xe3c\xb4!",
                    bloom=b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
                    difficulty=Uint(0),
                    number=Uint(0),
                    gas_limit=Uint(10000000000),
                    gas_used=Uint(0),
                    timestamp=U256(950),
                    extra_data=b"B",
                    prev_randao=b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00",
                    nonce=b"\x00\x00\x00\x00\x00\x00\x00\x00",
                    base_fee_per_gas=Uint(1000),
                    withdrawals_root=b"V\xe8\x1f\x17\x1b\xccU\xa6\xff\x83E\xe6\x92\xc0\xf8n[H\xe0\x1b\x99l\xad\xc0\x01b/\xb5\xe3c\xb4!",
                    blob_gas_used=U64(0),
                    excess_blob_gas=U64(0),
                    parent_beacon_block_root=b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
                ),
                transactions=(),
                ommers=(),
                withdrawals=(),
            ),
            Block(
                header=Header(
                    parent_hash=b"\x9c\xea\xbd\x04a9\x0f5u3\x95\xad\x01m|\x0e\xd59n\xf6\x0f\xd0\x91C\xc7\xfbX\x95;\xe8U\x93",
                    ommers_hash=b"\x1d\xccM\xe8\xde\xc7]z\xab\x85\xb5g\xb6\xcc\xd4\x1a\xd3\x12E\x1b\x94\x8at\x13\xf0\xa1B\xfd@\xd4\x93G",
                    coinbase=b"\xba^\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
                    state_root=b"\x06T\xcex\xa1\xd3\xcd\x0b3.#\xc2\xf3^[\x1b<\x88\x82D\xebJv\x1e\xa4N/\x02\xee\xe7\x8c\xbc",
                    transactions_root=b"\xa2y\x9c\x8bh\xafk>A\xc9\xc76[\xc7\xe0%\x17s\x13pg\xa9k\xca[\xc6\xe3b\xea\xfd\xe6\x07",
                    receipt_root=b"]r\x16g\xf3\xf4\x1cn\x8a^c\x0b,_%\x98U\xd26U\x13)\\O\xd0\xc5\xd0T\x98\xced\x89",
                    bloom=b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
                    difficulty=Uint(0),
                    number=Uint(1),
                    gas_limit=Uint(10000000000),
                    gas_used=Uint(43104),
                    timestamp=U256(1950),
                    extra_data=b"B",
                    prev_randao=b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00",
                    nonce=b"\x00\x00\x00\x00\x00\x00\x00\x00",
                    base_fee_per_gas=Uint(875),
                    withdrawals_root=b"V\xe8\x1f\x17\x1b\xccU\xa6\xff\x83E\xe6\x92\xc0\xf8n[H\xe0\x1b\x99l\xad\xc0\x01b/\xb5\xe3c\xb4!",
                    blob_gas_used=U64(0),
                    excess_blob_gas=U64(0),
                    parent_beacon_block_root=b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
                ),
                transactions=(
                    b"\x02\xf8e\x01\x01\x80\x82\x03\xe8\x83\x01\x86\xa0\x94\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\x80\x80\xc0\x80\xa0\xf1a\xae\xf2\x8e\xd4\x0bO\xe5I\xde;\x06\xcb\x17cQu\x84~R\xa7\xf4\xb3\no\x8f\xcc\x06\xf8_\xf3\xa0Y\xff>+\xec\n\xbe\xc4\xa8\x01\xea\x951\x17\x07 \xf4\xe6I\xbb{\x8d\x94u\x08{\x8c\xdc\xa32\x024",
                ),
                ommers=(),
                withdrawals=(),
            ),
        ],
        state=State(
            _main_trie=Trie(
                secured=True,
                default=None,
                _data=defaultdict(
                    lambda: None,
                    {
                        b'\x00\x0f=\xf6\xd72\x80~\xf11\x9f\xb7\xb8\xbb\x85"\xd0\xbe\xac\x02': Account(
                            nonce=Uint(1),
                            balance=U256(0),
                            code=b"3s\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\x14`MW` 6\x14`$W__\xfd[_5\x80\x15`IWb\x00\x1f\xff\x81\x06\x90\x81T\x14`<W__\xfd[b\x00\x1f\xff\x01T_R` _\xf3[__\xfd[b\x00\x1f\xffB\x06B\x81U_5\x90b\x00\x1f\xff\x01U\x00",
                        ),
                        b"\xaa\xaa\xaa\xaa\xaa\xaa\xaa\xaa\xaa\xaa\xaa\xaa\xaa\xaa\xaa\xaa\xaa\xaa\xaa\xaa": Account(
                            nonce=Uint(1), balance=U256(1099511627776), code=b""
                        ),
                        b"\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc": Account(
                            nonce=Uint(1), balance=U256(1099511627776), code=b"BCU\x00"
                        ),
                        b"\xd0-r\xe0g\xe7qXDN\xf2\x02\x0f\xf2\xd3%\xf9)\xb3c": Account(
                            nonce=Uint(2), balance=U256(18446744073671835616), code=b""
                        ),
                    },
                ),
            ),
            _storage_tries={
                b'\x00\x0f=\xf6\xd72\x80~\xf11\x9f\xb7\xb8\xbb\x85"\xd0\xbe\xac\x02': Trie(
                    secured=True,
                    default=U256(0),
                    _data=defaultdict(
                        lambda: U256(0),
                        {
                            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x03\xb6": U256(
                                950
                            ),
                            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x07\x9e": U256(
                                1950
                            ),
                        },
                    ),
                ),
                b"\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc": Trie(
                    secured=True,
                    default=U256(0),
                    _data=defaultdict(
                        lambda: U256(0),
                        {
                            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01": U256(
                                1950
                            )
                        },
                    ),
                ),
            },
            _snapshots=[],
            created_accounts=set(),
        ),
        chain_id=U64(1),
    )
    return chain, block


@pytest.fixture
def zkpi_fixture(zkpi_path):
    with open(zkpi_path, "r") as f:
        fixture = json.load(f)

    load = Load("Cancun", "cancun")
    block = Block(
        header=load.json_to_header(fixture["newBlockParameters"]["blockHeader"]),
        transactions=tuple(
            (
                LegacyTransaction(
                    nonce=hex_to_u256(tx["nonce"]),
                    gas_price=hex_to_uint(tx["gasPrice"]),
                    gas=hex_to_uint(tx["gas"]),
                    to=Address(hex_to_bytes(tx["to"])) if tx["to"] else Bytes0(),
                    value=hex_to_u256(tx["value"]),
                    data=Bytes(hex_to_bytes(tx["data"])),
                    v=hex_to_u256(tx["v"]),
                    r=hex_to_u256(tx["r"]),
                    s=hex_to_u256(tx["s"]),
                )
                if isinstance(tx, dict)
                else Bytes(hex_to_bytes(tx))
            )  # Non-legacy txs are hex strings
            for tx in fixture["newBlockParameters"]["transactions"]
        ),
        ommers=(),
        withdrawals=tuple(
            Withdrawal(
                index=U64(int(w["index"], 16)),
                validator_index=U64(int(w["validatorIndex"], 16)),
                address=Address(hex_to_bytes(w["address"])),
                amount=U256(int(w["amount"], 16)),
            )
            for w in fixture["newBlockParameters"]["withdrawals"]
        ),
    )
    blocks = [
        Block(
            header=load.json_to_header(ancestor),
            transactions=(),
            ommers=(),
            withdrawals=(),
        )
        for ancestor in fixture["ancestors"]
    ]
    chain = BlockChain(
        blocks=blocks,
        state=convert_defaultdict(load.json_to_state(fixture["pre"])),
        chain_id=U64(fixture["chainId"]),
    )

    # TODO: Remove when we have a working partial MPT
    state_root = apply_body(
        chain.state,
        get_last_256_block_hashes(chain),
        block.header.coinbase,
        block.header.number,
        block.header.base_fee_per_gas,
        block.header.gas_limit,
        block.header.timestamp,
        block.header.prev_randao,
        block.transactions,
        chain.chain_id,
        block.withdrawals,
        block.header.parent_beacon_block_root,
        calculate_excess_blob_gas(chain.blocks[-1].header),
    ).state_root
    block = Block(
        header=load.json_to_header(
            {
                **fixture["newBlockParameters"]["blockHeader"],
                "stateRoot": "0x" + state_root.hex(),
            }
        ),
        transactions=tuple(
            (
                LegacyTransaction(
                    nonce=hex_to_u256(tx["nonce"]),
                    gas_price=hex_to_uint(tx["gasPrice"]),
                    gas=hex_to_uint(tx["gas"]),
                    to=Address(hex_to_bytes(tx["to"])) if tx["to"] else Bytes0(),
                    value=hex_to_u256(tx["value"]),
                    data=Bytes(hex_to_bytes(tx["data"])),
                    v=hex_to_u256(tx["v"]),
                    r=hex_to_u256(tx["r"]),
                    s=hex_to_u256(tx["s"]),
                )
                if isinstance(tx, dict)
                else Bytes(hex_to_bytes(tx))
            )  # Non-legacy txs are hex strings
            for tx in fixture["newBlockParameters"]["transactions"]
        ),
        ommers=(),
        withdrawals=tuple(
            Withdrawal(
                index=U64(int(w["index"], 16)),
                validator_index=U64(int(w["validatorIndex"], 16)),
                address=Address(hex_to_bytes(w["address"])),
                amount=U256(int(w["amount"], 16)),
            )
            for w in fixture["newBlockParameters"]["withdrawals"]
        ),
    )
    chain = BlockChain(
        blocks=blocks,
        state=convert_defaultdict(load.json_to_state(fixture["pre"])),
        chain_id=U64(fixture["chainId"]),
    )
    # Safety check
    state_transition(chain, block)
    # Reset state to the original state
    chain = BlockChain(
        blocks=blocks[:-1],
        state=convert_defaultdict(load.json_to_state(fixture["pre"])),
        chain_id=U64(fixture["chainId"]),
    )
    return chain, block


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

    @given(data=tx_with_sender_in_state())
    def test_process_transaction(
        self, cairo_run, data: Tuple[Transaction, Environment, U64]
    ):
        # The Cairo Runner will raise if an exception is in the return values OR if
        # an assert expression fails (e.g. InvalidBlock)
        tx, env, _ = data
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

    def test_check_transaction(
        self,
        cairo_run,
    ):
        tx, env, chain_id = get_blob_tx_with_tx_sender_in_state()
        gas_available = Uint(int("0x1000000", 16))
        base_fee_per_gas = Uint(int("0x100000", 16))
        excess_blob_gas = U64(0)
        try:
            cairo_state, cairo_result = cairo_run(
                "check_transaction",
                env.state,
                tx,
                gas_available,
                chain_id,
                base_fee_per_gas,
                excess_blob_gas,
            )
        except Exception as e:
            with strict_raises(type(e)):
                check_transaction(
                    env.state,
                    tx,
                    gas_available,
                    chain_id,
                    base_fee_per_gas,
                    excess_blob_gas,
                )
            return

        assert cairo_result == check_transaction(
            env.state, tx, gas_available, chain_id, base_fee_per_gas, excess_blob_gas
        )
        assert cairo_state == env.state

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
    def test_apply_body(
        self,
        cairo_run,
        data,
        withdrawals: Tuple[Withdrawal, ...],
    ):
        accounts, storage_tries = _create_erc20_data()
        # Create constant state
        state = State(
            _main_trie=Trie(
                secured=True,
                default=None,
                _data=defaultdict(lambda: None, accounts),
            ),
            _storage_tries=dict(storage_tries),
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

        kwargs = {**data, "withdrawals": withdrawals, "state": state}

        try:
            cairo_state, cairo_result = cairo_run("apply_body", **kwargs)
        except Exception as e:
            with strict_raises(type(e)):
                apply_body(**kwargs)
            return

        output = apply_body(**kwargs)

        assert cairo_result == output
        assert cairo_state == state

    def test_state_transition(self, cairo_run):
        chain, block = get_valid_chain_and_block()
        try:
            cairo_chain = cairo_run("state_transition", chain, block)
        except Exception as cairo_e:
            with strict_raises(type(cairo_e)):
                state_transition(chain, block)
            return

        state_transition(chain, block)

        assert len(chain.blocks) == len(cairo_chain.blocks)
        assert all(a == b for a, b in zip(chain.blocks, cairo_chain.blocks))
        assert chain.state == cairo_chain.state
        assert chain.chain_id == cairo_chain.chain_id

    @pytest.mark.parametrize(
        "zkpi_path",
        list(Path("data/1/eels").glob("*.json")),
        ids=lambda x: x.stem,
    )
    def test_state_transition_zkpi(self, cairo_run, zkpi_fixture):
        chain, block = zkpi_fixture
        cairo_chain = cairo_run("state_transition", chain, block)
        state_transition(chain, block)

        assert len(chain.blocks) == len(cairo_chain.blocks)
        assert all(a == b for a, b in zip(chain.blocks, cairo_chain.blocks))
        assert chain.state == cairo_chain.state
        assert chain.chain_id == cairo_chain.chain_id


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
        erc20_address: Trie(
            secured=True,
            default=U256(0),
            _data=defaultdict(lambda: U256(0), storage_data),
        )
    }

    return accounts, storage_tries
