from hypothesis import strategies as st
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

from ethereum.base_types import U64, U256, Bytes8, Bytes32, Uint
from ethereum.cancun.blocks import Block, Header, Log, Receipt, Withdrawal
from ethereum.cancun.fork_types import Account, Address, Bloom, Root
from ethereum.cancun.trie import Trie
from ethereum.crypto.hash import Hash32

# Base types
uint20 = st.integers(min_value=0, max_value=2**20 - 1)
uint24 = st.integers(min_value=0, max_value=2**24 - 1)
uint64 = st.integers(min_value=0, max_value=2**64 - 1)
# The EELS uses a Uint type different from U64, but Reth uses U64.
# We use the same strategy for both.
uint = uint64
uint128 = st.integers(min_value=0, max_value=2**128 - 1)
felt = st.integers(min_value=0, max_value=DEFAULT_PRIME - 1)
uint256 = st.integers(min_value=0, max_value=2**256 - 1)

bytes0 = st.binary(min_size=0, max_size=0)
bytes8 = st.binary(min_size=8, max_size=8)
bytes20 = st.binary(min_size=20, max_size=20)
bytes32 = st.binary(min_size=32, max_size=32)
bytes256 = st.binary(min_size=256, max_size=256)

# Fork types
account = st.fixed_dictionaries(
    {
        "nonce": uint64.map(U64),
        "balance": uint256.map(U256),
        "code": st.binary(),
    }
).map(lambda x: Account(**x))

# Block types
withdrawal = st.fixed_dictionaries(
    {
        "index": uint64.map(U64),
        "validator_index": uint64.map(U64),
        "address": bytes20.map(Address),
        "amount": uint256.map(U256),
    }
).map(lambda x: Withdrawal(**x))

header = st.fixed_dictionaries(
    {
        "parent_hash": bytes32.map(Hash32),
        "ommers_hash": st.just(
            Hash32.fromhex(
                "1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347"
            )
        ),
        "coinbase": bytes20.map(Address),
        "state_root": bytes32.map(Root),
        "transactions_root": bytes32.map(Root),
        "receipt_root": bytes32.map(Root),
        "bloom": st.binary(min_size=256, max_size=256).map(Bloom),
        "difficulty": st.just(Uint(0x00)),
        "number": uint64.map(Uint),
        "gas_limit": uint64.map(Uint),
        "gas_used": uint64.map(Uint),
        "timestamp": uint64.map(U256),
        "extra_data": st.binary(max_size=32),
        "prev_randao": bytes32.map(Bytes32),
        "nonce": st.just(Bytes8.fromhex("0000000000000000")),
        "base_fee_per_gas": uint64.map(Uint),
        "withdrawals_root": bytes32.map(Root),
        "blob_gas_used": uint64.map(U64),
        "excess_blob_gas": uint64.map(U64),
        "parent_beacon_block_root": bytes32.map(Root),
    }
).map(lambda x: Header(**x))

block = st.fixed_dictionaries(
    {
        "header": header,
        # TODO: Add transactions
        "transactions": st.just(tuple()),
        "ommers": st.tuples(header),
        "withdrawals": st.tuples(withdrawal),
    }
).map(lambda x: Block(**x))

log = st.fixed_dictionaries(
    {
        "address": bytes20.map(Address),
        "topics": st.tuples(bytes32.map(Hash32)),
        "data": st.binary(),
    }
).map(lambda x: Log(**x))

receipt = st.fixed_dictionaries(
    {
        "succeeded": st.booleans(),
        "cumulative_gas_used": uint64.map(Uint),
        "bloom": st.binary(min_size=256, max_size=256).map(Bloom),
        "logs": st.tuples(log),
    }
).map(lambda x: Receipt(**x))

# Fork
state = st.lists(bytes20).flatmap(
    lambda addresses: st.fixed_dictionaries(
        {
            "_main_trie": st.builds(
                lambda data: Trie(secured=True, default=None, _data=data),
                data=st.fixed_dictionaries({address: account for address in addresses}),
            ),
            "_storage_tries": st.fixed_dictionaries(
                {
                    address: st.builds(
                        lambda data: Trie(secured=True, default=0, _data=data),
                        data=st.dictionaries(bytes32, uint256),
                    )
                    for address in addresses
                },
            ),
            "_snapshots": st.just([]),
            "created_accounts": st.just(set()),
        }
    )
)

# TODO: Below are wip or deprecated
block_chain = st.fixed_dictionaries(
    {
        "blocks": st.lists(block),
        "state": st.just(state),
        "chain_id": uint64,
    }
)

block_header = st.fixed_dictionaries(
    {
        "parent_hash": bytes32,
        "ommers_hash": st.just(
            bytes.fromhex(
                "1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347"
            )
        ),
        "coinbase": bytes20,
        "state_root": bytes32,
        "transactions_root": bytes32,
        "receipt_root": bytes32,
        "bloom": st.binary(min_size=256, max_size=256),
        "difficulty": st.just(0x00),
        "number": uint64,
        "gas_limit": uint64,
        "gas_used": uint64,
        "timestamp": uint64,
        "extra_data": st.binary(max_size=32),
        "prev_randao": bytes32,
        "nonce": st.just("0x0000000000000000"),
        "base_fee_per_gas": uint64,
        "withdrawals_root": bytes32,
        "blob_gas_used": uint64,
        "excess_blob_gas": uint64,
        "parent_beacon_block_root": bytes32,
    }
)
access_list_transaction = st.fixed_dictionaries(
    {
        "chain_id": uint64,
        "nonce": uint64,
        "gas_price": uint64,
        "gas": uint64,
        "to": bytes20,
        "value": uint64,
        "data": st.binary(),
        "access_list": st.lists(
            st.tuples(bytes20, st.lists(bytes32)), min_size=1, max_size=10
        ),
        "y_parity": uint64,
        "r": bytes32,
        "s": bytes32,
    }
)

# TODO: Add other transaction types
transaction = st.one_of(access_list_transaction)
