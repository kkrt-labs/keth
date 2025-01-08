import pytest
from hypothesis import given

from ethereum.cancun.fork_types import EMPTY_ACCOUNT, Account

pytestmark = pytest.mark.python_vm


class TestForkTypes:
    def test_account_default(self, cairo_run):
        assert EMPTY_ACCOUNT == cairo_run("EMPTY_ACCOUNT")

    @given(account_a=..., account_b=...)
    def test_account_eq(self, cairo_run, account_a: Account, account_b: Account):
        assert (account_a == account_b) == cairo_run(
            "Account__eq__", account_a, account_b
        )
