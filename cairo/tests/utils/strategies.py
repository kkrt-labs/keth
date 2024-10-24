from hypothesis import strategies as st

uint20 = st.integers(min_value=0, max_value=2**20 - 1)
uint24 = st.integers(min_value=0, max_value=2**24 - 1)
uint64 = st.integers(min_value=0, max_value=2**64 - 1)
uint128 = st.integers(min_value=0, max_value=2**128 - 1)
uint256 = st.integers(min_value=0, max_value=2**256 - 1)

bytes20 = st.binary(min_size=20, max_size=20)
bytes32 = st.binary(min_size=32, max_size=32)

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
