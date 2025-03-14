import json

from ethereum.cancun.fork_types import Account, Address, encode_account
from ethereum.cancun.state import get_account
from ethereum.cancun.trie import bytes_to_nibble_list, nibble_list_to_compact
from ethereum.crypto.hash import Hash32, keccak256
from ethereum_rlp import rlp
from ethereum_spec_tools.evm_tools.loaders.fixture_loader import Load
from ethereum_types.bytes import Bytes, Bytes32
from ethereum_types.numeric import U256, Uint

from mpt import EMPTY_TRIE_ROOT_HASH, EthereumState

# A set of encoded storage keys and values for testing
STORAGE_KEYS: list[Bytes32] = [U256(i).to_be_bytes32() for i in range(1, 6)]
KECCAK_STORAGE_KEYS: list[Bytes32] = [Bytes32(keccak256(key)) for key in STORAGE_KEYS]

STORAGE_VALUES: list[U256] = [U256(i) for i in range(1, 6)]
RLP_STORAGE_VALUES: list[Bytes] = [rlp.encode(value) for value in STORAGE_VALUES]

ADDRESSES: list[Address] = [
    Address(bytes.fromhex(f"000000000000000000000000000000000000000{i:x}"))
    for i in range(1, 6)
]

# Standard test account
TEST_ACCOUNT = Account(
    nonce=Uint(10), balance=U256(1000), code=bytes.fromhex("deadbeef")
)


class TestEthereumState:
    def test_from_json(self):
        mpt = EthereumState.from_json("data/1/inputs/22009357.json")
        assert mpt is not None

    def test_get(self):
        mpt = EthereumState.from_json("data/1/inputs/22009357.json")

        random_address = list(mpt.access_list.keys())[0]

        key = keccak256(random_address)

        result = mpt.get(key)

        assert result is not None

    def test_delete(self):
        mpt = EthereumState.from_json("data/1/inputs/22009357.json")

        # Using an address from the JSON file that we know exists
        test_address = Address(
            bytes.fromhex("30325619135da691a6932b13a19b8928527f8456")
        )

        assert mpt.get(keccak256(test_address)) is not None

        mpt.delete(keccak256(test_address))

        assert mpt.get(keccak256(test_address)) is None

    def test_upsert(self):
        mpt = EthereumState.from_json("data/1/inputs/22009357.json")

        encoded_account = encode_account(TEST_ACCOUNT, EMPTY_TRIE_ROOT_HASH)

        # Using an address from the JSON file
        test_address = Address(
            bytes.fromhex("30325619135da691a6932b13a19b8928527f8456")
        )

        mpt.upsert(keccak256(test_address), encoded_account)

        assert mpt.get(keccak256(test_address)) == encoded_account

    def test_to_state(self):
        mpt = EthereumState.from_json("data/1/inputs/22009357.json")

        state = mpt.to_state()

        assert state is not None

    def test_to_state_with_diff_testing(self):
        mpt = EthereumState.from_json("data/1/inputs/22009357.json")

        with open("data/1/eels/22009357.json", "r") as f:
            fixture = json.load(f)

        state = mpt.to_state()

        load = Load("Cancun", "cancun")
        expected_state = load.json_to_state(fixture["pre"])

        assert state == expected_state

    def test_to_state_from_simple_operations(self):
        mpt = EthereumState.create_empty()

        encoded_account = encode_account(TEST_ACCOUNT, EMPTY_TRIE_ROOT_HASH)

        mpt.upsert_account(ADDRESSES[0], encoded_account, TEST_ACCOUNT.code)
        mpt.access_list[ADDRESSES[0]] = None

        state = mpt.to_state()

        assert get_account(state, ADDRESSES[0]) == TEST_ACCOUNT

    def test_storage_operations(self):
        """Test that storage operations work correctly with empty and existing storage roots."""
        mpt = EthereumState.create_empty()

        # Create an account with empty storage
        encoded_account = encode_account(TEST_ACCOUNT, EMPTY_TRIE_ROOT_HASH)

        mpt.upsert_account(ADDRESSES[0], encoded_account, TEST_ACCOUNT.code)
        mpt.access_list[ADDRESSES[0]] = [KECCAK_STORAGE_KEYS[0], KECCAK_STORAGE_KEYS[1]]

        # Add a storage value
        mpt.upsert_storage_key(
            ADDRESSES[0], KECCAK_STORAGE_KEYS[0], RLP_STORAGE_VALUES[0]
        )

        # Add another storage value
        mpt.upsert_storage_key(
            ADDRESSES[0], KECCAK_STORAGE_KEYS[1], RLP_STORAGE_VALUES[1]
        )

        # Verify both values were stored
        account_after = mpt.get(keccak256(ADDRESSES[0]))
        decoded = rlp.decode(account_after)
        storage_root = Hash32(decoded[2])

        retrieved_value1 = mpt.get(keccak256(KECCAK_STORAGE_KEYS[0]), storage_root)
        retrieved_value2 = mpt.get(keccak256(KECCAK_STORAGE_KEYS[1]), storage_root)

        assert retrieved_value1 == RLP_STORAGE_VALUES[0]
        assert retrieved_value2 == RLP_STORAGE_VALUES[1]

        # Now update the first value
        new_storage_value = rlp.encode(U256(1001))
        mpt.upsert_storage_key(ADDRESSES[0], KECCAK_STORAGE_KEYS[0], new_storage_value)

        # Verify the update worked
        account_updated = mpt.get(keccak256(ADDRESSES[0]))
        decoded = rlp.decode(account_updated)
        updated_storage_root = Hash32(decoded[2])

        updated_value = mpt.get(keccak256(KECCAK_STORAGE_KEYS[0]), updated_storage_root)
        assert updated_value == new_storage_value

    def test_branch_node_reduction(self):
        """Test that branch node reductions work correctly during deletions."""
        mpt = EthereumState.create_empty()

        # Create an account with empty storage
        encoded_account = encode_account(TEST_ACCOUNT, EMPTY_TRIE_ROOT_HASH)
        mpt.upsert_account(ADDRESSES[0], encoded_account, TEST_ACCOUNT.code)

        # Use the first 5 storage keys and values
        access_list_keys = KECCAK_STORAGE_KEYS[:5]

        # Add storage values to create branch nodes
        for i, storage_key in enumerate(access_list_keys):
            mpt.upsert_storage_key(ADDRESSES[0], storage_key, RLP_STORAGE_VALUES[i])

        mpt.access_list[ADDRESSES[0]] = access_list_keys

        # Now delete the storage keys one by one
        for i, storage_key in enumerate(access_list_keys):
            mpt.delete_storage_key(ADDRESSES[0], storage_key)

            # After each deletion, verify that the remaining keys still work
            account_after = mpt.get(keccak256(ADDRESSES[0]))
            decoded = rlp.decode(account_after)
            storage_root = Hash32(decoded[2])

            # Check that deleted keys are gone
            for j in range(i + 1):
                value = mpt.get(keccak256(access_list_keys[j]), storage_root)
                assert value is None

            # Check that remaining keys still work
            for j in range(i + 1, len(access_list_keys)):
                value = mpt.get(keccak256(access_list_keys[j]), storage_root)
                assert value is not None

    def test_state_diff_application(self):
        """Test applying a state diff to an MPT."""
        # Create two empty MPTs
        original_mpt = EthereumState.create_empty()
        modified_mpt = EthereumState.create_empty()

        # Add an account to both
        encoded_account = encode_account(TEST_ACCOUNT, EMPTY_TRIE_ROOT_HASH)

        original_mpt.upsert_account(ADDRESSES[0], encoded_account, TEST_ACCOUNT.code)
        modified_mpt.upsert_account(ADDRESSES[0], encoded_account, TEST_ACCOUNT.code)

        # Add a storage value to the modified MPT
        modified_mpt.upsert_storage_key(
            ADDRESSES[0], KECCAK_STORAGE_KEYS[0], RLP_STORAGE_VALUES[0]
        )

        # Add the access list entries
        original_mpt.access_list[ADDRESSES[0]] = [KECCAK_STORAGE_KEYS[0]]
        modified_mpt.access_list[ADDRESSES[0]] = [KECCAK_STORAGE_KEYS[0]]

        # Convert to state objects
        original_state = original_mpt.to_state()
        modified_state = modified_mpt.to_state()

        # Generate a state diff
        from mpt.state_diff import StateDiff

        state_diff = StateDiff.from_pre_post(original_state, modified_state)

        # Apply the state diff to the original MPT
        original_mpt.update_from_state_diff(state_diff)

        # Verify the storage value was added to the original MPT
        account_after = original_mpt.get(keccak256(ADDRESSES[0]))
        decoded = rlp.decode(account_after)
        storage_root = Hash32(decoded[2])

        retrieved_value = original_mpt.get(
            keccak256(KECCAK_STORAGE_KEYS[0]), storage_root
        )
        assert retrieved_value == RLP_STORAGE_VALUES[0]

    def test_empty_storage_operations(self):
        """Test operations on empty storage."""
        mpt = EthereumState.create_empty()

        # Create an account with empty storage
        encoded_account = encode_account(TEST_ACCOUNT, EMPTY_TRIE_ROOT_HASH)
        mpt.upsert_account(ADDRESSES[0], encoded_account, TEST_ACCOUNT.code)

        # Try to delete a non-existent storage key
        mpt.delete_storage_key(ADDRESSES[0], KECCAK_STORAGE_KEYS[0])

        # Verify account still exists
        assert mpt.get(keccak256(ADDRESSES[0])) is not None

        # Try to get a non-existent storage key
        account = mpt.get(keccak256(ADDRESSES[0]))
        decoded = rlp.decode(account)
        storage_root = Hash32(decoded[2])

        value = mpt.get(keccak256(KECCAK_STORAGE_KEYS[0]), storage_root)
        assert value is None

    def RLP_test_large_storage_values(self):
        """Test handling of large storage values."""
        mpt = EthereumState.create_empty()

        # Create an account
        encoded_account = encode_account(TEST_ACCOUNT, EMPTY_TRIE_ROOT_HASH)
        mpt.upsert_account(ADDRESSES[0], encoded_account, TEST_ACCOUNT.code)

        large_value = rlp.encode(U256.MAX_VALUE)

        mpt.upsert_storage_key(ADDRESSES[0], KECCAK_STORAGE_KEYS[0], large_value)

        account_after = mpt.get(keccak256(ADDRESSES[0]))
        decoded = rlp.decode(account_after)
        storage_root = Hash32(decoded[2])
        assert storage_root is not EMPTY_TRIE_ROOT_HASH

        retrieved_value = mpt.get(keccak256(KECCAK_STORAGE_KEYS[0]), storage_root)
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
