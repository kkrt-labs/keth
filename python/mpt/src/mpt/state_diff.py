import logging
from typing import Dict, Optional

from ethereum.cancun.fork_types import EMPTY_ACCOUNT, Account, Address
from ethereum.cancun.state import State, get_account, get_storage
from ethereum.cancun.trie import Trie
from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U256

logger = logging.getLogger(__name__)


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

    def __repr__(self) -> str:
        result = []
        for address, account_diff in self.account_diffs.items():
            storage_updates_str = ", ".join(
                [
                    f"{key.hex()}: {value}"
                    for key, value in account_diff.storage_updates.items()
                ]
            )
            result.append(
                f"AccountDiff(address={address.hex()}, account={account_diff.account}, "
                f"storage_updates=[{storage_updates_str}])"
            )
        return "\n".join(result) if result else "StateDiff()"

    def __init__(self):
        self.account_diffs: Dict[Address, AccountDiff] = {}

    @staticmethod
    def from_pre_post(pre_state: State, post_state: State) -> "StateDiff":
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
        diff = StateDiff()

        pre_addresses = set(pre_state._main_trie._data.keys())
        post_addresses = set(post_state._main_trie._data.keys())

        logger.debug(
            f"Computing state diff: {len(pre_addresses)} pre addresses, {len(post_addresses)} post addresses"
        )

        # Find deleted accounts
        deletions = pre_addresses - post_addresses

        for address in deletions:
            account_diff = compute_account_diff(pre_state, post_state, address)
            if account_diff is not None:
                logger.debug(f"Adding deletion diff for address: 0x{address.hex()}")
                diff.account_diffs[address] = account_diff

        # addresses in post state are not in deletions by definition
        for address in post_addresses:
            account_diff = compute_account_diff(pre_state, post_state, address)
            if account_diff is not None:
                diff.account_diffs[address] = account_diff

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

    # Check if account changed
    account_modified = post_account != pre_account

    # Check if the account has storage in either state
    has_pre_storage = address in pre_state._storage_tries
    has_post_storage = address in post_state._storage_tries

    account_diff = AccountDiff(post_account)

    if not has_pre_storage and not has_post_storage:
        # If no storage in either state and account is empty, add account deletion
        if post_account == EMPTY_ACCOUNT:
            account_diff.account = None
        return account_diff

    if post_account == EMPTY_ACCOUNT and not has_post_storage:
        # Set account to None since it's deleted
        account_diff.account = None
        pre_storage = pre_state._storage_tries[address]
        for key in pre_storage._data.keys():
            account_diff.storage_updates[key] = U256(0)

    pre_storage = pre_state._storage_tries.get(
        address, Trie(secured=True, default=U256(0))
    )
    post_storage = post_state._storage_tries.get(
        address, Trie(secured=True, default=U256(0))
    )

    all_keys = set(pre_storage._data.keys()).union(set(post_storage._data.keys()))
    logger.debug(
        f"Account 0x{address.hex()} has storage in both states: comparing {len(all_keys)} keys"
    )

    for key in all_keys:
        pre_value = get_storage(pre_state, address, key)
        post_value = get_storage(post_state, address, key)

        if pre_value != post_value:
            account_diff.storage_updates[key] = post_value
            logger.debug(
                f"Storage change for 0x{address.hex()}, key 0x{key.hex()}: {pre_value} -> {post_value}"
            )

    logger.debug(
        f"Found {len(account_diff.storage_updates)} storage changes for account 0x{address.hex()}"
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
