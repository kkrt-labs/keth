from typing import Optional

from ethereum.cancun.fork_types import EMPTY_ACCOUNT, Account
from ethereum_types.numeric import U256, Uint
from hypothesis import example, given

from keth_types.types import EMPTY_BYTES_HASH, EMPTY_TRIE_HASH


class TestForkTypes:
    def test_account_default(self, cairo_run):
        assert EMPTY_ACCOUNT == cairo_run("EMPTY_ACCOUNT")

    @given(account_a=..., account_b=...)
    @example(
        account_a=Account(
            nonce=Uint(1),
            balance=U256(2**128),
            code=bytearray(),
            storage_root=EMPTY_TRIE_HASH,
            code_hash=EMPTY_BYTES_HASH,
        ),
        account_b=Account(
            nonce=Uint(1),
            balance=U256(2**129),
            code=bytearray(),
            storage_root=EMPTY_TRIE_HASH,
            code_hash=EMPTY_BYTES_HASH,
        ),
    )
    @example(
        account_a=EMPTY_ACCOUNT,
        account_b=EMPTY_ACCOUNT,
    )
    def test_account_eq(
        self, cairo_run, account_a: Optional[Account], account_b: Optional[Account]
    ):
        # Our Python Account__eq__ does not take into account the storage root.
        # Handle cases where account_a or account_b might be None or lack a storage root.
        a_storage_root = getattr(account_a, "storage_root", None)
        b_storage_root = getattr(account_b, "storage_root", None)
        assert (
            account_a == account_b and a_storage_root == b_storage_root
        ) == cairo_run("Account__eq__", account_a, account_b)
