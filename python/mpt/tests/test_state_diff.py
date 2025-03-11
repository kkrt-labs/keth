from ethereum.cancun.fork_types import Account, Address
from ethereum.cancun.state import State, set_account, set_storage
from ethereum_types.numeric import U256, Uint

from mpt.state_diff import StateDiff


class TestStateDiffs:
    def test_from_pre_post(self):
        # Pre state
        pre_state = State()

        ## Add two accounts to the state
        pre_account = Account(
            balance=U256(1000),
            nonce=Uint(1),
            code=bytes.fromhex("0123456789abcdef"),
        )
        pre_address = Address(bytes.fromhex("0000000000000000000000000000000000000001"))
        set_account(pre_state, pre_address, pre_account)

        ## Add storage to the account
        pre_storage_key = U256(1).to_be_bytes32()
        pre_storage_value = U256(1000)
        set_storage(pre_state, pre_address, pre_storage_key, pre_storage_value)

        ## Add another account to the state
        pre_address2 = Address(
            bytes.fromhex("0000000000000000000000000000000000000002")
        )
        pre_account2 = Account(balance=U256(2000), nonce=Uint(2), code=b"")
        set_account(pre_state, pre_address2, pre_account2)
        pre_storage_key2 = U256(2).to_be_bytes32()
        pre_storage_value2 = U256(2000)
        set_storage(pre_state, pre_address2, pre_storage_key2, pre_storage_value2)

        # Post state
        post_state = State()

        ## Add one new account to the state
        new_post_account = Account(balance=U256(2000), nonce=Uint(2), code=b"")
        new_post_address = Address(
            bytes.fromhex("0000000000000000000000000000000000000003")
        )
        set_account(post_state, new_post_address, new_post_account)
        new_storage_key = U256(3).to_be_bytes32()
        new_storage_value = U256(1000)
        set_storage(
            post_state,
            new_post_address,
            new_storage_key,
            new_storage_value,
        )
        ## Modify one account in the state
        modified_post_account = Account(balance=U256(3000), nonce=Uint(3), code=b"")
        set_account(post_state, pre_address, modified_post_account)
        # Add new storage to the account
        new_post_storage_key = U256(3).to_be_bytes32()
        new_post_storage_value = U256(1000)
        set_storage(
            post_state,
            pre_address,
            new_post_storage_key,
            new_post_storage_value,
        )

        ## Modify storage of the account
        post_storage_key = U256(1).to_be_bytes32()
        post_storage_value = U256(2000)
        set_storage(post_state, pre_address, post_storage_key, post_storage_value)

        ## Compute the state diff
        diff = StateDiff.from_pre_post(pre_state, post_state)

        ## Assert the diff is correct
        assert diff.updates[new_post_address] == new_post_account
        assert diff.updates[pre_address] == modified_post_account
        assert diff.deletions == {pre_address2}
        assert diff.storage_updates[pre_address] == {
            post_storage_key: post_storage_value,
            new_post_storage_key: new_post_storage_value,
        }
        assert diff.storage_updates[new_post_address] == {
            new_storage_key: new_storage_value
        }
        assert diff.storage_deletions[pre_address2] == {pre_storage_key2}
