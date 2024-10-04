from src.utils.uint256 import int_to_uint256
from tests.utils.models import Account, Block, to_int


class TestSerde:

    def test_block(self, cairo_run, block):
        result = cairo_run("test_block", block=block)
        assert Block.model_validate(result) == block

    def test_state(self, cairo_run, state):
        result = cairo_run("test_state", state=state)
        assert [int(key, 16) for key in result["accounts"].keys()] == list(
            state.accounts.keys()
        )
        for result, account in zip(
            result["accounts"].values(), state.accounts.values()
        ):
            # Storage needs to be handled differently because of the hashing of the keys
            assert {
                k: int_to_uint256(to_int(v))
                for k, v in result["storage"].items()
                if v is not None
            } == account.storage
            result["storage"] = {}
            account.storage = {}
            assert Account.model_validate(result) == account
