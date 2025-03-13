from ethereum.cancun.fork_types import Account
from ethereum.cancun.state import State, set_account, set_storage
from ethereum_types.numeric import U256, Uint

from mpt.state_diff import StateDiff

from .test_mpt import ADDRESSES, STORAGE_KEYS, TEST_ACCOUNT


class TestStateDiffs:
    def test_from_pre_post(self):
        pre_state = State()

        pre_account = Account(
            balance=TEST_ACCOUNT.balance,
            nonce=Uint(1),
            code=TEST_ACCOUNT.code,
        )
        pre_address = ADDRESSES[0]
        set_account(pre_state, pre_address, pre_account)

        pre_storage_key = STORAGE_KEYS[0]
        pre_storage_value = U256(1)
        set_storage(pre_state, pre_address, pre_storage_key, pre_storage_value)

        pre_address2 = ADDRESSES[1]
        pre_account2 = Account(
            balance=U256(2000), nonce=Uint(2), code=bytes.fromhex("abcdef")
        )
        set_account(pre_state, pre_address2, pre_account2)
        pre_storage_key2 = STORAGE_KEYS[1]
        pre_storage_value2 = U256(2)
        set_storage(pre_state, pre_address2, pre_storage_key2, pre_storage_value2)

        post_state = State()

        new_post_account = Account(
            balance=U256(2000), nonce=Uint(2), code=bytes.fromhex("abcdef")
        )
        new_post_address = ADDRESSES[2]
        set_account(post_state, new_post_address, new_post_account)
        new_storage_key = STORAGE_KEYS[2]
        new_storage_value = U256(3)
        set_storage(
            post_state,
            new_post_address,
            new_storage_key,
            new_storage_value,
        )

        modified_post_account = Account(
            balance=U256(3000), nonce=Uint(3), code=TEST_ACCOUNT.code
        )
        set_account(post_state, pre_address, modified_post_account)

        new_post_storage_key = STORAGE_KEYS[3]
        new_post_storage_value = U256(4)
        set_storage(
            post_state,
            pre_address,
            new_post_storage_key,
            new_post_storage_value,
        )

        post_storage_key = STORAGE_KEYS[0]
        post_storage_value = U256(5)
        set_storage(post_state, pre_address, post_storage_key, post_storage_value)

        diff = StateDiff.from_pre_post(pre_state, post_state)

        assert diff.account_diffs[new_post_address].account == new_post_account
        assert diff.account_diffs[pre_address].account == modified_post_account
        assert (
            pre_address2 in diff.account_diffs
            and diff.account_diffs[pre_address2].account is None
        )
        assert diff.account_diffs[pre_address].storage_updates == {
            post_storage_key: post_storage_value,
            new_post_storage_key: new_post_storage_value,
        }
        assert diff.account_diffs[new_post_address].storage_updates == {
            new_storage_key: new_storage_value
        }
        assert (
            pre_address2 in diff.account_diffs
            and pre_storage_key2 in diff.account_diffs[pre_address2].storage_updates
        )
        assert diff.account_diffs[pre_address2].storage_updates[
            pre_storage_key2
        ] == U256(0)

    def test_empty_diff(self):
        """Test that an empty diff is created when pre and post states are identical."""
        state = State()
        set_account(state, ADDRESSES[0], TEST_ACCOUNT)
        set_storage(state, ADDRESSES[0], STORAGE_KEYS[0], U256(1))

        diff = StateDiff.from_pre_post(state, state)

        assert not diff.account_diffs

    def test_account_only_diff(self):
        """Test a diff with only account changes (no storage changes)."""
        pre_state = State()

        for i in range(3):
            account = Account(
                nonce=Uint(i),
                balance=U256(1000 * (i + 1)),
                code=bytes.fromhex("deadbeef" + "00" * i),
            )
            set_account(pre_state, ADDRESSES[i], account)

        post_state = State()

        modified_account = Account(
            nonce=Uint(5), balance=U256(5000), code=bytes.fromhex("deadbeef00")
        )
        set_account(post_state, ADDRESSES[0], modified_account)

        new_account = Account(
            nonce=Uint(10), balance=U256(10000), code=bytes.fromhex("abcdef")
        )
        set_account(post_state, ADDRESSES[3], new_account)

        original_account = Account(
            nonce=Uint(1), balance=U256(2000), code=bytes.fromhex("deadbeef00")
        )
        set_account(post_state, ADDRESSES[1], original_account)

        diff = StateDiff.from_pre_post(pre_state, post_state)

        assert diff.account_diffs[ADDRESSES[0]].account == modified_account
        assert diff.account_diffs[ADDRESSES[3]].account == new_account
        assert (
            ADDRESSES[2] in diff.account_diffs
            and diff.account_diffs[ADDRESSES[2]].account is None
        )
        assert not diff.account_diffs[ADDRESSES[0]].storage_updates

    def test_storage_only_diff(self):
        """Test a diff with only storage changes (no account changes)."""
        pre_state = State()

        set_account(pre_state, ADDRESSES[0], TEST_ACCOUNT)
        set_storage(pre_state, ADDRESSES[0], STORAGE_KEYS[0], U256(1))
        set_storage(pre_state, ADDRESSES[0], STORAGE_KEYS[1], U256(2))

        post_state = State()
        set_account(post_state, ADDRESSES[0], TEST_ACCOUNT)
        set_storage(post_state, ADDRESSES[0], STORAGE_KEYS[0], U256(100))
        set_storage(post_state, ADDRESSES[0], STORAGE_KEYS[2], U256(3))

        diff = StateDiff.from_pre_post(pre_state, post_state)

        assert ADDRESSES[0] in diff.account_diffs
        assert diff.account_diffs[ADDRESSES[0]].account == TEST_ACCOUNT
        assert diff.account_diffs[ADDRESSES[0]].storage_updates == {
            STORAGE_KEYS[0]: U256(100),
            STORAGE_KEYS[2]: U256(3),
            STORAGE_KEYS[1]: U256(0),  # Deleted storage is now represented as zero
        }

    def test_complex_diff(self):
        """Test a complex diff with multiple accounts and storage changes."""
        pre_state = State()

        # Set up accounts in pre-state
        for i in range(4):
            account = Account(
                nonce=Uint(i),
                balance=U256(1000 * (i + 1)),
                code=bytes.fromhex("deadbeef" + "00" * i),
            )
            set_account(pre_state, ADDRESSES[i], account)

        # Explicitly set storage for each account
        # Account 0
        set_storage(pre_state, ADDRESSES[0], STORAGE_KEYS[0], U256(1))
        set_storage(pre_state, ADDRESSES[0], STORAGE_KEYS[1], U256(2))

        # Account 1
        set_storage(pre_state, ADDRESSES[1], STORAGE_KEYS[2], U256(3))
        set_storage(pre_state, ADDRESSES[1], STORAGE_KEYS[3], U256(4))

        # Account 2 - explicitly set both keys we'll work with
        set_storage(pre_state, ADDRESSES[2], STORAGE_KEYS[4], U256(5))
        set_storage(
            pre_state, ADDRESSES[2], STORAGE_KEYS[0], U256(6)
        )  # This will be updated
        set_storage(
            pre_state, ADDRESSES[2], STORAGE_KEYS[1], U256(7)
        )  # This will be deleted

        # Account 3
        set_storage(pre_state, ADDRESSES[3], STORAGE_KEYS[2], U256(8))
        set_storage(pre_state, ADDRESSES[3], STORAGE_KEYS[3], U256(9))

        post_state = State()

        # 1. Keep one account unchanged
        unchanged_account = Account(
            nonce=Uint(0),
            balance=U256(1000),
            code=bytes.fromhex("deadbeef"),
        )
        set_account(post_state, ADDRESSES[0], unchanged_account)
        # Keep its storage unchanged
        set_storage(post_state, ADDRESSES[0], STORAGE_KEYS[0], U256(1))
        set_storage(post_state, ADDRESSES[0], STORAGE_KEYS[1], U256(2))

        # 2. Modify account details but keep storage
        modified_account = Account(
            nonce=Uint(10),
            balance=U256(5000),
            code=bytes.fromhex("deadbeef00"),
        )
        set_account(post_state, ADDRESSES[1], modified_account)
        # Keep storage the same
        set_storage(post_state, ADDRESSES[1], STORAGE_KEYS[2], U256(3))
        set_storage(post_state, ADDRESSES[1], STORAGE_KEYS[3], U256(4))

        # 3. Keep account details but modify storage
        same_account = Account(
            nonce=Uint(2),
            balance=U256(3000),
            code=bytes.fromhex("deadbeef0000"),
        )
        set_account(post_state, ADDRESSES[2], same_account)

        # Modify storage: update one value, add one new value, omit one value to delete it
        set_storage(
            post_state, ADDRESSES[2], STORAGE_KEYS[4], U256(100)
        )  # Update existing key
        set_storage(
            post_state, ADDRESSES[2], STORAGE_KEYS[0], U256(200)
        )  # Update existing key
        # Deliberately omit STORAGE_KEYS[1] to cause a deletion

        # 4. Add a completely new account with storage
        new_account = Account(
            nonce=Uint(50),
            balance=U256(9999),
            code=bytes.fromhex("abcdef"),
        )
        set_account(post_state, ADDRESSES[4], new_account)
        set_storage(post_state, ADDRESSES[4], STORAGE_KEYS[1], U256(888))
        set_storage(post_state, ADDRESSES[4], STORAGE_KEYS[3], U256(999))

        # 5. Delete account 3 entirely
        # (Don't add ADDRESSES[3] to post_state)

        # Generate the diff
        diff = StateDiff.from_pre_post(pre_state, post_state)

        # Verify account updates
        assert ADDRESSES[0] not in diff.account_diffs  # No changes
        assert diff.account_diffs[ADDRESSES[1]].account == modified_account
        assert ADDRESSES[2] in diff.account_diffs  # Account with storage changes
        assert diff.account_diffs[ADDRESSES[4]].account == new_account

        # Verify account deletions
        assert ADDRESSES[3] in diff.account_diffs
        assert diff.account_diffs[ADDRESSES[3]].account is None

        # Verify storage updates
        assert diff.account_diffs[ADDRESSES[2]].storage_updates == {
            STORAGE_KEYS[4]: U256(100),  # Updated value
            STORAGE_KEYS[0]: U256(200),  # Updated value
            STORAGE_KEYS[1]: U256(0),  # Deleted value (now represented as zero)
        }
        assert diff.account_diffs[ADDRESSES[4]].storage_updates == {
            STORAGE_KEYS[1]: U256(888),
            STORAGE_KEYS[3]: U256(999),
        }

        # Verify deleted account's storage is also deleted
        assert ADDRESSES[3] in diff.account_diffs
        assert diff.account_diffs[ADDRESSES[3]].account is None
        # Storage for deleted account should be set to zero
        assert STORAGE_KEYS[2] in diff.account_diffs[ADDRESSES[3]].storage_updates
        assert STORAGE_KEYS[3] in diff.account_diffs[ADDRESSES[3]].storage_updates
        assert diff.account_diffs[ADDRESSES[3]].storage_updates[
            STORAGE_KEYS[2]
        ] == U256(0)
        assert diff.account_diffs[ADDRESSES[3]].storage_updates[
            STORAGE_KEYS[3]
        ] == U256(0)

    def test_account_creation_with_immediate_storage(self):
        """Test creating an account and immediately adding storage."""
        pre_state = State()
        # No accounts in pre-state

        post_state = State()
        # Create a new account with storage
        new_account = Account(nonce=Uint(1), balance=U256(1000), code=b"")
        set_account(post_state, ADDRESSES[0], new_account)
        # Immediately set storage
        set_storage(post_state, ADDRESSES[0], STORAGE_KEYS[0], U256(123))
        set_storage(post_state, ADDRESSES[0], STORAGE_KEYS[1], U256(456))

        diff = StateDiff.from_pre_post(pre_state, post_state)

        # Verify the account was created
        assert ADDRESSES[0] in diff.account_diffs
        assert diff.account_diffs[ADDRESSES[0]].account == new_account

        # Verify the storage was created
        assert len(diff.account_diffs[ADDRESSES[0]].storage_updates) == 2
        assert diff.account_diffs[ADDRESSES[0]].storage_updates[
            STORAGE_KEYS[0]
        ] == U256(123)
        assert diff.account_diffs[ADDRESSES[0]].storage_updates[
            STORAGE_KEYS[1]
        ] == U256(456)

    def test_account_recreated_with_storage(self):
        """Test deleting and recreating an account with different storage."""
        pre_state = State()

        # Create initial account with storage
        account1 = Account(nonce=Uint(1), balance=U256(1000), code=b"code1")
        set_account(pre_state, ADDRESSES[0], account1)
        set_storage(pre_state, ADDRESSES[0], STORAGE_KEYS[0], U256(100))
        set_storage(pre_state, ADDRESSES[0], STORAGE_KEYS[1], U256(200))

        post_state = State()
        # Create a different account at the same address with different storage
        account2 = Account(nonce=Uint(1), balance=U256(2000), code=b"code2")
        set_account(post_state, ADDRESSES[0], account2)
        set_storage(post_state, ADDRESSES[0], STORAGE_KEYS[0], U256(300))  # Changed
        set_storage(post_state, ADDRESSES[0], STORAGE_KEYS[2], U256(400))  # New key

        diff = StateDiff.from_pre_post(pre_state, post_state)

        # Verify account change
        assert ADDRESSES[0] in diff.account_diffs
        assert diff.account_diffs[ADDRESSES[0]].account == account2

        # Verify storage changes
        assert diff.account_diffs[ADDRESSES[0]].storage_updates[
            STORAGE_KEYS[0]
        ] == U256(300)
        assert diff.account_diffs[ADDRESSES[0]].storage_updates[
            STORAGE_KEYS[1]
        ] == U256(
            0
        )  # Should be deleted
        assert diff.account_diffs[ADDRESSES[0]].storage_updates[
            STORAGE_KEYS[2]
        ] == U256(400)

    def test_deleted_account_with_zero_storage(self):
        """Test deleting an account that has zero storage values."""
        pre_state = State()

        # Create account with explicit zero storage
        account = Account(nonce=Uint(1), balance=U256(1000), code=b"code")
        set_account(pre_state, ADDRESSES[0], account)
        set_storage(pre_state, ADDRESSES[0], STORAGE_KEYS[0], U256(1))
        set_storage(pre_state, ADDRESSES[0], STORAGE_KEYS[1], U256(100))

        post_state = State()
        # Account doesn't exist in post state (deleted)

        diff = StateDiff.from_pre_post(pre_state, post_state)

        # Verify account deletion
        assert ADDRESSES[0] in diff.account_diffs
        assert diff.account_diffs[ADDRESSES[0]].account is None

        # Verify all storage is marked for deletion (including the zero value)
        assert STORAGE_KEYS[0] in diff.account_diffs[ADDRESSES[0]].storage_updates
        assert STORAGE_KEYS[1] in diff.account_diffs[ADDRESSES[0]].storage_updates
        assert diff.account_diffs[ADDRESSES[0]].storage_updates[
            STORAGE_KEYS[0]
        ] == U256(0)
        assert diff.account_diffs[ADDRESSES[0]].storage_updates[
            STORAGE_KEYS[1]
        ] == U256(0)

    def test_large_storage_changes(self):
        """Test with many storage changes to ensure all are captured."""
        pre_state = State()
        account = Account(nonce=Uint(1), balance=U256(1000), code=b"code")
        set_account(pre_state, ADDRESSES[0], account)

        # Create many storage entries
        for i in range(20):
            key = bytes.fromhex(f"{i:064}")  # Create unique keys
            set_storage(pre_state, ADDRESSES[0], key, U256(i))

        post_state = State()
        set_account(post_state, ADDRESSES[0], account)

        # Modify some, delete some, keep some, add some
        for i in range(30):
            key = bytes.fromhex(f"{i:064}")
            if i < 5:  # Keep these the same
                set_storage(post_state, ADDRESSES[0], key, U256(i))
            elif i < 10:  # Modify these
                set_storage(post_state, ADDRESSES[0], key, U256(i + 100))
            elif i < 15:  # Delete these (don't set)
                pass
            elif i < 20:  # Set to zero
                set_storage(post_state, ADDRESSES[0], key, U256(0))
            else:  # Add new ones
                set_storage(post_state, ADDRESSES[0], key, U256(i + 200))

        diff = StateDiff.from_pre_post(pre_state, post_state)

        # Verify no account change
        assert ADDRESSES[0] in diff.account_diffs

        # Verify correct number of storage changes
        # 5 modified + 5 deleted + 5 set to zero + 10 new = 25 changes
        assert len(diff.account_diffs[ADDRESSES[0]].storage_updates) == 25

        for i in range(30):
            key = bytes.fromhex(f"{i:064}")
            if i < 5:  # Unchanged, shouldn't be in diff
                assert key not in diff.account_diffs[ADDRESSES[0]].storage_updates
            elif i < 10:  # Modified
                assert diff.account_diffs[ADDRESSES[0]].storage_updates[key] == U256(
                    i + 100
                )
            elif i < 15:  # Deleted
                assert diff.account_diffs[ADDRESSES[0]].storage_updates[key] == U256(0)
            elif i < 20:  # Set to zero
                assert diff.account_diffs[ADDRESSES[0]].storage_updates[key] == U256(0)
            else:  # New
                assert diff.account_diffs[ADDRESSES[0]].storage_updates[key] == U256(
                    i + 200
                )

    def test_empty_storage_in_pre_state(self):
        """Test handling accounts with empty storage in pre state."""
        pre_state = State()

        # Create account with no storage
        account = Account(nonce=Uint(1), balance=U256(1000), code=b"code")
        set_account(pre_state, ADDRESSES[0], account)
        set_storage(pre_state, ADDRESSES[0], STORAGE_KEYS[1], U256(10))

        post_state = State()
        # Same account
        set_account(post_state, ADDRESSES[0], account)
        # Add storage
        set_storage(post_state, ADDRESSES[0], STORAGE_KEYS[0], U256(100))

        diff = StateDiff.from_pre_post(pre_state, post_state)

        # Verify storage additions
        assert ADDRESSES[0] in diff.account_diffs
        assert diff.account_diffs[ADDRESSES[0]].storage_updates[
            STORAGE_KEYS[0]
        ] == U256(100)
        assert diff.account_diffs[ADDRESSES[0]].storage_updates[
            STORAGE_KEYS[1]
        ] == U256(0)

    def test_empty_storage_in_post_state(self):
        """Test handling accounts where all storage is removed."""
        pre_state = State()

        # Create account with storage
        account = Account(nonce=Uint(1), balance=U256(1000), code=b"code")
        set_account(pre_state, ADDRESSES[0], account)
        set_storage(pre_state, ADDRESSES[0], STORAGE_KEYS[0], U256(100))
        set_storage(pre_state, ADDRESSES[0], STORAGE_KEYS[1], U256(200))

        post_state = State()
        # Same account, but no storage
        set_account(post_state, ADDRESSES[0], account)

        diff = StateDiff.from_pre_post(pre_state, post_state)

        # Verify all storage is deleted
        assert ADDRESSES[0] in diff.account_diffs
        assert diff.account_diffs[ADDRESSES[0]].storage_updates[
            STORAGE_KEYS[0]
        ] == U256(0)
        assert diff.account_diffs[ADDRESSES[0]].storage_updates[
            STORAGE_KEYS[1]
        ] == U256(0)

    def test_account_deleted_then_new_account_same_address(self):
        """Test deleting an account and creating a new one at the same address in a different transaction."""
        # This simulates what might happen across multiple blocks

        # Step 1: Create and delete an account
        pre_state1 = State()
        account1 = Account(nonce=Uint(1), balance=U256(1000), code=b"code1")
        set_account(pre_state1, ADDRESSES[0], account1)
        set_storage(pre_state1, ADDRESSES[0], STORAGE_KEYS[0], U256(100))

        post_state1 = State()
        # Account is deleted

        diff1 = StateDiff.from_pre_post(pre_state1, post_state1)
        assert ADDRESSES[0] in diff1.account_diffs
        assert diff1.account_diffs[ADDRESSES[0]].account is None

        # Step 2: Create a new account at the same address
        pre_state2 = post_state1  # Start from previous post state

        post_state2 = State()
        account2 = Account(nonce=Uint(2), balance=U256(2000), code=b"code2")
        set_account(post_state2, ADDRESSES[0], account2)
        set_storage(post_state2, ADDRESSES[0], STORAGE_KEYS[1], U256(200))

        diff2 = StateDiff.from_pre_post(pre_state2, post_state2)

        # Verify new account is created
        assert ADDRESSES[0] in diff2.account_diffs
        assert diff2.account_diffs[ADDRESSES[0]].account == account2

        # Verify only the new storage is present
        assert STORAGE_KEYS[1] in diff2.account_diffs[ADDRESSES[0]].storage_updates
        assert diff2.account_diffs[ADDRESSES[0]].storage_updates[
            STORAGE_KEYS[1]
        ] == U256(200)
        # The old storage key shouldn't be in the diff since it wasn't in pre_state2
        assert STORAGE_KEYS[0] not in diff2.account_diffs[ADDRESSES[0]].storage_updates
