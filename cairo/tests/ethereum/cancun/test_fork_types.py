from hypothesis import given

from ethereum.base_types import Bytes
from ethereum.cancun.fork_types import Account, encode_account


class TestForkTypes:
    class TestEncodeAccount:

        @given(raw_account_data=..., storage_root=...)
        def test_encode_account(
            self, cairo_run, raw_account_data: Account, storage_root: Bytes
        ):
            assert encode_account(raw_account_data, storage_root) == cairo_run(
                "encode_account", raw_account_data, storage_root
            )
