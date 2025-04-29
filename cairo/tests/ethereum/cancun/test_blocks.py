from typing import Tuple, Union

from ethereum.cancun.blocks import Header, LegacyTransaction, Log, Withdrawal
from ethereum_types.bytes import Bytes
from hypothesis import given

from tests.utils.hash_utils import (
    Header__hash__,
    Log__hash__,
    TupleLog__hash__,
    TupleUnionBytesLegacyTransaction__hash__,
    UnionBytesLegacyTransaction__hash__,
)


class TestUnionBytesLegacyTransaction:
    @given(tx=...)
    def test_UnionBytesLegacyTransaction__hash__(
        self, cairo_run, tx: Union[Bytes, LegacyTransaction]
    ):
        cairo_result = cairo_run("UnionBytesLegacyTransaction__hash__", tx)

        assert UnionBytesLegacyTransaction__hash__(tx) == cairo_result


class TestTupleUnionBytesLegacyTransaction:
    @given(tx=...)
    def test_TupleUnionBytesLegacyTransaction__hash__(
        self, cairo_run, tx: Tuple[Union[Bytes, LegacyTransaction], ...]
    ):
        cairo_result = cairo_run("TupleUnionBytesLegacyTransaction__hash__", tx)

        assert TupleUnionBytesLegacyTransaction__hash__(tx) == cairo_result


class TestLog:
    @given(log=...)
    def test_Log__hash__(self, cairo_run, log: Log):
        cairo_result = cairo_run("Log__hash__", log)

        assert Log__hash__(log) == cairo_result


class TestTupleLog:
    @given(log=...)
    def test_TupleLog__hash__(self, cairo_run, log: Tuple[Log, ...]):
        cairo_result = cairo_run("TupleLog__hash__", log)

        assert TupleLog__hash__(log) == cairo_result


class TestHeader:
    @given(header=...)
    def test_Header__hash__(self, cairo_run, header: Header):
        cairo_result = cairo_run("Header__hash__", header)

        assert Header__hash__(header) == cairo_result


class TestWithdrawal:
    @given(withdrawal=...)
    def test_Withdrawal__hash__(self, cairo_run, withdrawal: Withdrawal):
        cairo_run("Withdrawal__hash__", withdrawal)
