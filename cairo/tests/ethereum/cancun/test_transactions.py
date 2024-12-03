from typing import Union

from hypothesis import given

from ethereum.base_types import Bytes0
from ethereum.cancun.fork_types import Address
from ethereum.cancun.transactions import LegacyTransaction
from ethereum.rlp import encode


class TestTransactions:
    @given(to=...)
    def test_encode_to(self, cairo_run, to: Union[Bytes0, Address]):
        assert encode(to) == cairo_run("encode_to", to)

    @given(tx=...)
    def test_encode_legacy_transaction(self, cairo_run, tx: LegacyTransaction):
        assert encode(tx) == cairo_run("encode_legacy_transaction", tx)
