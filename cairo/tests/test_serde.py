from src.utils.uint256 import int_to_uint256
from tests.utils.models import Account, to_int


class TestSerde:

    def test_block(self, cairo_run, block):
        cairo_run("test_block", block=block)

    def test_account(self, cairo_run, account):
        result = cairo_run("test_account", account=account)
        # Storage needs to handle differently because of the hashing of the keys
        assert {
            k: int_to_uint256(to_int(v)) for k, v in result["storage"].items()
        } == account.storage
        result["storage"] = {}
        account.storage = {}

        assert Account.model_validate(result) == account

    def test_state(self, cairo_run, state):
        cairo_run("test_state", state=state)
