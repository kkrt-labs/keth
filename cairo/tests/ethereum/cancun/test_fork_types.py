from ethereum.cancun.fork_types import EMPTY_ACCOUNT


class TestForkTypes:
    def test_account_default(self, cairo_run):
        assert EMPTY_ACCOUNT == cairo_run("EMPTY_ACCOUNT")
