from typing import List

from ethereum.cancun.fork_types import Account, Address
from ethereum.cancun.state import State, set_account, set_storage
from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U256
from hypothesis import assume, given
from hypothesis import strategies as st

from mpt.state_diff import StateDiff

# Reuse the strategies defined in test_mpt.py
from .test_mpt import account_st, address_st, storage_key_st, storage_value_st


class TestStateDiffs:
    @given(
        address=address_st,
        pre_account=account_st,
        post_account=account_st,
        storage_key=storage_key_st,
        pre_value=storage_value_st,
        post_value=storage_value_st,
    )
    def test_from_pre_post(
        self,
        address,
        pre_account,
        post_account,
        storage_key,
        pre_value,
        post_value,
    ):
        assume(pre_account != post_account)
        assume(pre_value != post_value)

        # Setup pre-state with account and storage
        pre_state = State()
        set_account(pre_state, address, pre_account)
        set_storage(pre_state, address, storage_key, pre_value)

        # Setup post-state with modified account and storage
        post_state = State()
        set_account(post_state, address, post_account)
        set_storage(post_state, address, storage_key, post_value)

        # Generate diff
        diff = StateDiff.from_pre_post(pre_state, post_state)

        # Verify account diff
        assert address in diff.account_diffs
        assert diff.account_diffs[address].account == post_account

        # Verify storage diff if values are different
        if pre_value != post_value:
            assert storage_key in diff.account_diffs[address].storage_updates
            assert (
                diff.account_diffs[address].storage_updates[storage_key] == post_value
            )

    @given(
        address=address_st,
        account=account_st,
        storage_key=storage_key_st,
        storage_value=storage_value_st,
    )
    def test_empty_diff(
        self,
        address: Address,
        account: Account,
        storage_key: Bytes32,
        storage_value: U256,
    ):
        """Test that an empty diff is created when pre and post states are identical."""
        pre_state = State()
        set_account(pre_state, address, account)
        set_storage(pre_state, address, storage_key, storage_value)

        # Generate diff between identical states
        diff = StateDiff.from_pre_post(pre_state, pre_state)

        # Verify no diffs are generated
        assert not diff.account_diffs

    @given(address=address_st, pre_account=account_st, post_account=account_st)
    def test_account_only_diff(self, address, pre_account, post_account):
        """Test a diff with only account changes (no storage changes)."""
        # Skip test if accounts are identical
        if pre_account == post_account:
            return

        pre_state = State()
        set_account(pre_state, address, pre_account)

        post_state = State()
        set_account(post_state, address, post_account)

        diff = StateDiff.from_pre_post(pre_state, post_state)

        # Verify account diff
        assert address in diff.account_diffs
        assert diff.account_diffs[address].account == post_account
        assert not diff.account_diffs[address].storage_updates

    @given(
        address=address_st,
        account=account_st,
        storage_key=storage_key_st,
        pre_value=storage_value_st,
        post_value=storage_value_st,
    )
    def test_storage_only_diff(
        self, address, account, storage_key, pre_value, post_value
    ):
        """Test a diff with only storage changes (no account changes)."""
        assume(pre_value != post_value)

        pre_state = State()
        set_account(pre_state, address, account)
        set_storage(pre_state, address, storage_key, pre_value)

        post_state = State()
        set_account(post_state, address, account)
        set_storage(post_state, address, storage_key, post_value)

        diff = StateDiff.from_pre_post(pre_state, post_state)

        # Verify storage diff
        assert address in diff.account_diffs
        assert diff.account_diffs[address].account == account
        assert storage_key in diff.account_diffs[address].storage_updates
        assert diff.account_diffs[address].storage_updates[storage_key] == post_value

    @given(
        address=address_st,
        account=account_st,
        storage_keys=st.lists(storage_key_st, min_size=1, max_size=3, unique=True),
    )
    def test_account_deletion(self, address, account, storage_keys):
        """Test deleting an account and its storage."""
        pre_state = State()
        set_account(pre_state, address, account)

        # Add some storage values
        for i, key in enumerate(storage_keys):
            set_storage(pre_state, address, key, U256(i + 1))

        # Post state doesn't have the account
        post_state = State()

        diff = StateDiff.from_pre_post(pre_state, post_state)

        # Verify account deletion
        assert address in diff.account_diffs
        assert diff.account_diffs[address].account is None

        # Verify all storage keys are included in the diff
        for key in storage_keys:
            assert key in diff.account_diffs[address].storage_updates
            assert diff.account_diffs[address].storage_updates[key] == U256(0)

    @given(
        address=address_st,
        account=account_st,
        modified_account=account_st,
        storage_keys=st.lists(storage_key_st, min_size=5, max_size=5, unique=True),
        storage_values=st.lists(storage_value_st, min_size=5, max_size=5),
    )
    def test_complex_diff(
        self,
        address: Address,
        account: Account,
        modified_account: Account,
        storage_keys: List[Bytes32],
        storage_values: List[U256],
    ):
        """Test a complex diff with multiple storage changes."""
        assume(account != modified_account)

        # Ensure we have the same number of keys and values
        storage_keys = storage_keys[: min(len(storage_keys), len(storage_values))]
        storage_values = storage_values[: len(storage_keys)]

        # Setup pre state
        pre_state = State()
        set_account(pre_state, address, account)

        for i, key in enumerate(storage_keys):
            set_storage(pre_state, address, key, storage_values[i])

        # Setup post state with some modifications
        post_state = State()
        set_account(post_state, address, modified_account)

        # Track what we expect to be in the diff
        expected_updates = {}

        # Modify some storage values, delete some
        for i, key in enumerate(storage_keys):
            if i % 3 == 0:  # Modify
                new_value = U256(
                    (storage_values[i]._number + 100) % U256.MAX_VALUE._number
                )
                set_storage(post_state, address, key, new_value)
                expected_updates[key] = new_value
            elif i % 3 == 1:  # Delete (set to 0)
                set_storage(post_state, address, key, U256(0))
                expected_updates[key] = U256(0)
            else:  # Keep the same - no need to add to expected_updates
                set_storage(post_state, address, key, storage_values[i])

        # Generate diff
        diff = StateDiff.from_pre_post(pre_state, post_state)

        # Verify account diff
        assert address in diff.account_diffs
        assert diff.account_diffs[address].account == modified_account

        assert diff.account_diffs[address].storage_updates == expected_updates
