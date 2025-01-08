import pytest

from ethereum.cancun.fork_types import EMPTY_ACCOUNT

pytestmark = pytest.mark.python_vm


class TestForkTypes:
    def test_account_default(self, cairo_run):
        assert EMPTY_ACCOUNT == cairo_run("EMPTY_ACCOUNT")
