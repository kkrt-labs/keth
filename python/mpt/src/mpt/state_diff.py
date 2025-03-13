import logging
from typing import Dict, Optional

from ethereum.cancun.fork_types import Account, Address
from ethereum.cancun.state import State, get_account, get_storage
from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U256

# Set up logger
logger = logging.getLogger("mpt.state_diff")


class AccountDiff:
    """
    A class that contains the differences for a single account, including its storage changes.
    If account is None, it represents a deletion.
    """

    account: Optional[Account]
    storage_updates: Dict[Bytes32, U256]

    def __init__(self, account: Optional[Account] = None):
        self.account: Optional[Account] = account
        self.storage_updates: Dict[Bytes32, U256] = {}


class StateDiff:
    """
    A class that contains the differences between two states.
    """

    account_diffs: Dict[Address, AccountDiff]

    def __init__(self):
        self.account_diffs: Dict[Address, AccountDiff] = {}

    @classmethod
    def from_pre_post(cls, pre_state: State, post_state: State) -> "StateDiff":
        """
        Compute a state diff between two states: a pre_state and a post_state.

        Parameters
        ----------
        pre_state : State
            The state before executing a block
        post_state : State
            The state after executing a block

        Returns
        -------
        StateDiff
            A StateDiff object containing:
            - 'account_diffs': Dict[Address, AccountDiff] - Accounts that were added, modified or deleted with their storage changes
        """
        return compute_state_diff(pre_state, post_state)


def compute_state_diff(pre_state: State, post_state: State) -> StateDiff:
    """
    Compute the difference between pre_state and post_state.

    Parameters
    ----------
    pre_state : State
        The state before executing a block
    post_state : State
        The state after executing a block

    Returns
    -------
    StateDiff
        A StateDiff object containing:
        - 'account_diffs': Dict[Address, AccountDiff] - Accounts that were added, modified or deleted with their storage changes
    """

    diff = StateDiff()

    pre_addresses = set(pre_state._main_trie._data.keys())
    post_addresses = set(post_state._main_trie._data.keys())

    logger.debug(
        f"Computing state diff: {len(pre_addresses)} pre addresses, {len(post_addresses)} post addresses"
    )

    # Find deleted accounts
    deletions = pre_addresses - post_addresses
    if deletions:
        logger.error(
            "Warning: Since EIP-6780, we should not see any accounts marked for deletion at the level of the block"
        )
        logger.debug(f"Found {len(deletions)} accounts marked for deletion")
        for address in deletions:
            logger.debug(
                f"Address marked for deletion (not in post state): 0x{address.hex()}"
            )
            # Process deleted account
            account_diff = compute_account_diff(pre_state, post_state, address)
            if account_diff is not None:
                logger.debug(f"Adding deletion diff for address: 0x{address.hex()}")
                diff.account_diffs[address] = account_diff

    # Find added or modified accounts
    modified_count = 0
    for address in post_addresses:
        # Process added or modified account
        account_diff = compute_account_diff(pre_state, post_state, address)
        if account_diff is not None:
            modified_count += 1
            if address not in pre_addresses:
                logger.debug(f"Account added (not in pre state): 0x{address.hex()}")
            else:
                logger.debug(f"Account modified: 0x{address.hex()}")
            diff.account_diffs[address] = account_diff

    logger.debug(f"Found {modified_count} accounts added or modified")
    logger.debug(f"Total account diffs: {len(diff.account_diffs)}")

    return diff


def compute_account_diff(
    pre_state: State,
    post_state: State,
    address: Address,
) -> Optional[AccountDiff]:
    """
    Process account and storage changes.

    Parameters
    ----------
    pre_state : State
        The state before executing a block
    post_state : State
        The state after executing a block
    address : Address
        The address of the account

    Returns
    -------
    Optional[AccountDiff]
        An AccountDiff object if there were any changes, None otherwise
    """
    pre_account = get_account(pre_state, address)
    post_account = get_account(post_state, address)

    # Log account details
    if pre_account is None:
        logger.debug(f"Pre-account for 0x{address.hex()} is None")
    else:
        logger.debug(
            f"Pre-account for 0x{address.hex()}: nonce={pre_account.nonce}, "
            f"balance={pre_account.balance}, "
            f"code_length={len(pre_account.code)}"
        )

    if post_account is None:
        logger.debug(
            f"Post-account for 0x{address.hex()} is None (marked for deletion)"
        )
    else:
        logger.debug(
            f"Post-account for 0x{address.hex()}: nonce={post_account.nonce}, "
            f"balance={post_account.balance}, "
            f"code_length={len(post_account.code)}"
        )

    # Check if account changed
    account_modified = post_account != pre_account
    if account_modified:
        logger.debug(
            f"Account 0x{address.hex()} modified: {pre_account} -> {post_account}"
        )

    # Create account diff if account was modified
    account_diff = AccountDiff(post_account) if account_modified else None

    # Check if the account has storage in either state
    has_pre_storage = address in pre_state._storage_tries
    has_post_storage = address in post_state._storage_tries

    if has_pre_storage:
        logger.debug(
            f"Account 0x{address.hex()} has pre-storage entries: {len(pre_state._storage_tries[address]._data)}"
        )
    if has_post_storage:
        logger.debug(
            f"Account 0x{address.hex()} has post-storage entries: {len(post_state._storage_tries[address]._data)}"
        )

    # If no storage in either state, return account diff (if any)
    if not has_pre_storage and not has_post_storage:
        if account_diff is not None:
            logger.debug(
                f"Account 0x{address.hex()} has no storage changes, only account state change"
            )
        return account_diff

    # Create account diff if it doesn't exist yet but we have storage to process
    if account_diff is None:
        logger.debug(
            f"Creating account diff for 0x{address.hex()} due to storage changes"
        )
        account_diff = AccountDiff(post_account)

    # If account is deleted or storage only in pre state, set all pre-storage to zero
    if post_account is None or (has_pre_storage and not has_post_storage):
        if has_pre_storage:
            pre_storage = pre_state._storage_tries[address]
            storage_changes = 0
            for key, value in pre_storage._data.items():
                if value != U256(0):  # Only record non-zero values being set to zero
                    account_diff.storage_updates[key] = U256(0)
                    storage_changes += 1
            logger.debug(
                f"Account 0x{address.hex()} {'deleted' if post_account is None else 'lost storage'}: "
                f"zeroing {storage_changes} storage entries"
            )

    # If storage only in post state, add all post-storage
    elif not has_pre_storage and has_post_storage:
        post_storage = post_state._storage_tries[address]
        logger.debug(
            f"Account 0x{address.hex()} gained storage: adding {len(post_storage._data)} entries"
        )
        for key, value in post_storage._data.items():
            account_diff.storage_updates[key] = value

    # Both states have storage, compare them
    elif has_pre_storage and has_post_storage:
        pre_storage = pre_state._storage_tries[address]
        post_storage = post_state._storage_tries[address]

        all_keys = set(pre_storage._data.keys()).union(set(post_storage._data.keys()))
        logger.debug(
            f"Account 0x{address.hex()} has storage in both states: comparing {len(all_keys)} keys"
        )

        storage_changes = 0
        for key in all_keys:
            pre_value = get_storage(pre_state, address, key)
            post_value = get_storage(post_state, address, key)

            if pre_value != post_value:
                account_diff.storage_updates[key] = post_value
                storage_changes += 1
                logger.debug(
                    f"Storage change for 0x{address.hex()}, key 0x{key.hex()}: {pre_value} -> {post_value}"
                )

        logger.debug(
            f"Found {storage_changes} storage changes for account 0x{address.hex()}"
        )

    # Return account diff if there were any changes, None otherwise
    if account_modified or len(account_diff.storage_updates) > 0:
        logger.debug(
            f"Returning account diff for 0x{address.hex()} with "
            f"{'account deletion' if post_account is None else 'account changes'} and "
            f"{len(account_diff.storage_updates)} storage updates"
        )
        return account_diff
    else:
        logger.debug(f"No changes for account 0x{address.hex()}, returning None")
        return None
