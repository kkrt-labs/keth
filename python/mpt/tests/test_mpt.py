from ethereum.cancun.fork_types import Account, Address, encode_account
from ethereum.cancun.state import State, get_account, set_account, set_storage
from ethereum.cancun.trie import bytes_to_nibble_list, nibble_list_to_compact
from ethereum.crypto.hash import Hash32, keccak256
from ethereum_rlp import rlp
from ethereum_types.numeric import U256, Uint
from hypothesis import given
from hypothesis import strategies as st

from mpt import EMPTY_TRIE_ROOT_HASH, AccountNode, StateTries

# Define Hypothesis strategies for generating test data
# Simple strategy for addresses - 20 bytes
address_st = st.binary(min_size=20, max_size=20).map(Address)

# Strategy for accounts
account_st = st.builds(
    Account,
    nonce=st.integers(min_value=0, max_value=2**64 - 1).map(Uint),
    balance=st.integers(min_value=0, max_value=2**128 - 1).map(U256),
    code=st.binary(min_size=0, max_size=100),
)

# Strategy for storage keys
storage_key_st = st.integers(min_value=1, max_value=2**256 - 1).map(
    lambda x: U256(x).to_be_bytes32()
)

# Strategy for storage values
storage_value_st = st.integers(min_value=1, max_value=2**256 - 1).map(U256)


class TestStateTries:
    def test_from_json(self, test_file_path):
        mpt = StateTries.from_json(test_file_path)
        assert mpt is not None

    def test_get(self, mpt_from_json):
        random_address = list(mpt_from_json.access_list.keys())[0]
        key = keccak256(random_address)

        result = mpt_from_json.get(key)
        rlp_account = AccountNode(*rlp.decode(result))

        assert rlp_account.to_account(
            mpt_from_json.codes.get(rlp_account.code_hash, b"")
        ) == get_account(mpt_from_json.to_state(), random_address)

    def test_delete(self, mpt_from_json, test_address):
        assert mpt_from_json.get(keccak256(test_address)) is not None

        mpt_from_json.delete(keccak256(test_address))

        assert mpt_from_json.get(keccak256(test_address)) is None

    def test_upsert(self, mpt_from_json, test_address, encoded_test_account):
        mpt_from_json.upsert(keccak256(test_address), encoded_test_account)

        assert mpt_from_json.get(keccak256(test_address)) == encoded_test_account

    def test_to_state_with_diff_testing(self, mpt_from_json, eels_state):
        state = mpt_from_json.to_state()
        assert state == eels_state

    @given(address=address_st, account=account_st)
    def test_to_state_from_simple_operations(self, empty_mpt, address, account):
        # Create an account with empty storage
        encoded_account = encode_account(account, EMPTY_TRIE_ROOT_HASH)

        # Add the account to the MPT
        empty_mpt.upsert_account(address, encoded_account, account.code)
        empty_mpt.access_list[address] = None

        # Convert to state and verify
        state = empty_mpt.to_state()
        assert get_account(state, address) == account

    @given(
        address=address_st,
        account=account_st,
        storage_keys=st.lists(storage_key_st, min_size=2, max_size=2, unique=True),
        storage_values=st.lists(storage_value_st, min_size=2, max_size=2),
    )
    def test_storage_operations(
        self, empty_mpt, address, account, storage_keys, storage_values
    ):
        """Test that storage operations work correctly with empty and existing storage roots."""
        # Create an account with empty storage
        encoded_account = encode_account(account, EMPTY_TRIE_ROOT_HASH)

        # Add the account to the MPT
        empty_mpt.upsert_account(address, encoded_account, account.code)

        empty_mpt.access_list[address] = storage_keys

        # Encode the storage values
        rlp_storage_values = [rlp.encode(value) for value in storage_values]

        # Add storage values
        empty_mpt.upsert_storage_key(address, storage_keys[0], rlp_storage_values[0])
        empty_mpt.upsert_storage_key(address, storage_keys[1], rlp_storage_values[1])

        # Verify both values were stored
        account_after = empty_mpt.get(keccak256(address))
        decoded = rlp.decode(account_after)
        storage_root = Hash32(decoded[2])

        retrieved_value1 = empty_mpt.get(keccak256(storage_keys[0]), storage_root)
        retrieved_value2 = empty_mpt.get(keccak256(storage_keys[1]), storage_root)

        assert retrieved_value1 == rlp_storage_values[0]
        assert retrieved_value2 == rlp_storage_values[1]

        # Now update the first value
        new_storage_value = rlp.encode(U256(1001))
        empty_mpt.upsert_storage_key(address, storage_keys[0], new_storage_value)

        # Verify the update worked
        account_updated = empty_mpt.get(keccak256(address))
        decoded = rlp.decode(account_updated)
        updated_storage_root = Hash32(decoded[2])

        updated_value = empty_mpt.get(keccak256(storage_keys[0]), updated_storage_root)
        assert updated_value == new_storage_value

    @given(
        address=address_st,
        account=account_st,
        storage_keys=st.lists(storage_key_st, min_size=5, max_size=5, unique=True),
        storage_values=st.lists(storage_value_st, min_size=5, max_size=5, unique=True),
    )
    def test_delete_storage_key(
        self, empty_mpt, address, account, storage_keys, storage_values
    ):
        """Test that branch node reductions work correctly during deletions."""
        # Create an account with empty storage
        encoded_account = encode_account(account, EMPTY_TRIE_ROOT_HASH)
        empty_mpt.upsert_account(address, encoded_account, account.code)

        # Set up access list before adding storage values
        empty_mpt.access_list[address] = storage_keys

        # Encode the storage values
        rlp_storage_values = [rlp.encode(value) for value in storage_values]

        # Add storage values to create branch nodes
        for i, storage_key in enumerate(storage_keys):
            empty_mpt.upsert_storage_key(address, storage_key, rlp_storage_values[i])

        # Now delete the storage keys one by one and verify after each deletion
        for storage_key in storage_keys:
            # Delete the key
            empty_mpt.delete_storage_key(address, storage_key)

            # Get the updated account and storage root
            account_after = empty_mpt.get(keccak256(address))
            rlp_account = AccountNode(*rlp.decode(account_after))
            storage_root = rlp_account.storage_root

            assert empty_mpt.get(keccak256(storage_key), storage_root) is None

    @given(
        address=address_st,
        account=account_st,
        storage_key=storage_key_st,
        storage_value=storage_value_st,
    )
    def test_state_diff_application(
        self, empty_mpt, address, account, storage_key, storage_value
    ):
        """Test applying a state diff to an MPT."""
        # Create two empty states
        original_state = State()
        modified_state = State()

        # Set up the states
        set_account(original_state, address, account)
        set_account(modified_state, address, account)
        set_storage(modified_state, address, storage_key, storage_value)

        # Add the account to the MPT
        empty_mpt.upsert_account(
            address, encode_account(account, EMPTY_TRIE_ROOT_HASH), account.code
        )
        empty_mpt.access_list[address] = [storage_key]

        # Generate a state diff
        from mpt.state_diff import StateDiff

        state_diff = StateDiff.from_pre_post(original_state, modified_state)

        empty_mpt.update_from_state_diff(state_diff)

        account_after = empty_mpt.get(keccak256(address))
        rlp_account = AccountNode(*rlp.decode(account_after))

        retrieved_value = empty_mpt.get(
            keccak256(storage_key), rlp_account.storage_root
        )

        assert retrieved_value == rlp.encode(storage_value)

    @given(address=address_st, account=account_st, storage_key=storage_key_st)
    def test_empty_storage_operations(self, empty_mpt, address, account, storage_key):
        """Test operations on empty storage."""
        # Create an account with empty storage
        encoded_account = encode_account(account, EMPTY_TRIE_ROOT_HASH)
        empty_mpt.upsert_account(address, encoded_account, account.code)

        # Set up access list
        empty_mpt.access_list[address] = [storage_key]

        # Try to delete a non-existent storage key
        empty_mpt.delete_storage_key(address, storage_key)

        # Verify account still exists
        assert empty_mpt.get(keccak256(address)) is not None

        # Try to get a non-existent storage key
        account_data = empty_mpt.get(keccak256(address))
        decoded = rlp.decode(account_data)
        storage_root = Hash32(decoded[2])

        value = empty_mpt.get(keccak256(storage_key), storage_root)
        assert value is None

    @given(address=address_st, account=account_st, storage_key=storage_key_st)
    def test_large_storage_values(self, empty_mpt, address, account, storage_key):
        """Test handling of large storage values."""
        # Create an account with empty storage
        encoded_account = encode_account(account, EMPTY_TRIE_ROOT_HASH)
        empty_mpt.upsert_account(address, encoded_account, account.code)

        empty_mpt.access_list[address] = [storage_key]

        # Use a large value
        large_value = rlp.encode(U256.MAX_VALUE)

        empty_mpt.upsert_storage_key(address, storage_key, large_value)

        account_after = empty_mpt.get(keccak256(address))
        decoded = rlp.decode(account_after)
        storage_root = Hash32(decoded[2])
        assert storage_root != EMPTY_TRIE_ROOT_HASH

        retrieved_value = empty_mpt.get(keccak256(storage_key), storage_root)
        assert retrieved_value == large_value

    def test_compact_encoding(self):
        path1 = bytes([1, 2, 3, 4])
        compact1 = nibble_list_to_compact(path1, True)  # Leaf node

        # Decode it back
        nibbles1 = bytes_to_nibble_list(compact1)
        first_nibble1 = compact1[0] >> 4
        if first_nibble1 in (1, 3):  # odd length
            decoded1 = nibbles1[1:]
        else:  # even length
            decoded1 = nibbles1[2:]

        assert decoded1 == path1

        # Test with an odd-length path
        path2 = bytes([1, 2, 3, 4, 5])
        compact2 = nibble_list_to_compact(path2, True)  # Leaf node

        # Decode it back
        nibbles2 = bytes_to_nibble_list(compact2)
        first_nibble2 = compact2[0] >> 4
        if first_nibble2 in (1, 3):  # odd length
            decoded2 = nibbles2[1:]
        else:  # even length
            decoded2 = nibbles2[2:]

        assert decoded2 == path2
