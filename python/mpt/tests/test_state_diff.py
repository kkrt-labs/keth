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
