from typing import Tuple, Type

import pytest
from hypothesis import given
from starkware.cairo.common.dict import DictManager
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME
from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager

from ethereum.base_types import (
    U64,
    U256,
    Bytes,
    Bytes0,
    Bytes8,
    Bytes20,
    Bytes32,
    Bytes256,
    Uint,
)
from ethereum.cancun.blocks import Header, Log, Receipt, Withdrawal
from ethereum.cancun.fork_types import Account, Address, Bloom, Root, VersionedHash
from ethereum.cancun.transactions import Transaction
from tests.utils.args_gen import gen_arg as _gen_arg
from tests.utils.args_gen import to_cairo_type as _to_cairo_type
from tests.utils.serde import Serde
from tests.utils.strategies import uint128


@pytest.fixture(scope="module")
def segments():
    return MemorySegmentManager(memory=MemoryDict(), prime=DEFAULT_PRIME)


@pytest.fixture(scope="module")
def serde(cairo_program, segments):
    return Serde(segments, cairo_program)


@pytest.fixture(scope="module")
def gen_arg(segments):
    dict_manager = DictManager()
    return _gen_arg(dict_manager, segments)


@pytest.fixture(scope="module")
def to_cairo_type(cairo_program):
    def _factory(type_name: Type):
        return _to_cairo_type(cairo_program, type_name)

    return _factory


class TestSerde:

    class TestBaseTypes:

        @given(b=...)
        def test_bool(self, to_cairo_type, segments, serde, gen_arg, b: bool):
            base = segments.gen_arg([gen_arg(bool, b)])
            result = serde.serialize(to_cairo_type(bool), base, shift=0)
            assert result == b

        @given(n=...)
        def test_u64(self, to_cairo_type, segments, serde, gen_arg, n: U64):
            base = segments.gen_arg([gen_arg(U64, n)])
            result = serde.serialize(to_cairo_type(U64), base, shift=0)
            assert result == n

        @given(n=uint128)
        def test_u128(self, to_cairo_type, segments, serde, gen_arg, n):
            """
            This type is not used in the spec, but it's a good sanity check in
            Cairo where a lot of functions expect a < RC_BOUND value.
            """
            base = segments.gen_arg([gen_arg(int, n)])
            result = serde.serialize(to_cairo_type(int), base, shift=0)
            assert result == n

        @given(n=...)
        def test_uint(self, to_cairo_type, segments, serde, gen_arg, n: Uint):
            base = segments.gen_arg([gen_arg(Uint, n)])
            result = serde.serialize(to_cairo_type(Uint), base, shift=0)
            assert result == n

        @given(n=...)
        def test_u256(self, to_cairo_type, segments, serde, gen_arg, n: U256):
            base = segments.gen_arg([gen_arg(U256, n)])
            result = serde.serialize(to_cairo_type(U256), base, shift=0)
            assert result == n

        @given(bytes0=...)
        def test_bytes0(self, to_cairo_type, segments, serde, gen_arg, bytes0: Bytes0):
            base = segments.gen_arg([gen_arg(Bytes0, bytes0)])
            result = serde.serialize(to_cairo_type(Bytes0), base, shift=0)
            assert result == bytes0

        @given(bytes8=...)
        def test_bytes8(self, to_cairo_type, segments, serde, gen_arg, bytes8: Bytes8):
            base = segments.gen_arg([gen_arg(Bytes8, bytes8)])
            result = serde.serialize(to_cairo_type(Bytes8), base, shift=0)
            assert result == bytes8

        @given(bytes20=...)
        def test_bytes20(
            self, to_cairo_type, segments, serde, gen_arg, bytes20: Bytes20
        ):
            base = segments.gen_arg([gen_arg(Bytes20, bytes20)])
            result = serde.serialize(to_cairo_type(Bytes20), base, shift=0)
            assert result == bytes20

        @given(bytes32=...)
        def test_bytes32(
            self, to_cairo_type, segments, serde, gen_arg, bytes32: Bytes32
        ):
            base = segments.gen_arg([gen_arg(Bytes32, bytes32)])
            result = serde.serialize(to_cairo_type(Bytes32), base, shift=0)
            assert result == bytes32

        @given(bytes256=...)
        def test_bytes256(
            self, to_cairo_type, segments, serde, gen_arg, bytes256: Bytes256
        ):
            base = segments.gen_arg([gen_arg(Bytes256, bytes256)])
            result = serde.serialize(to_cairo_type(Bytes256), base, shift=0)
            assert result == bytes256

        @given(data=...)
        def test_bytes(self, to_cairo_type, segments, serde, gen_arg, data: Bytes):
            base = segments.gen_arg([gen_arg(Bytes, data)])
            result = serde.serialize(to_cairo_type(Bytes), base, shift=0)
            assert result == data

        @given(data=...)
        def test_tuple_bytes(
            self, to_cairo_type, segments, serde, gen_arg, data: Tuple[Bytes, ...]
        ):
            base = segments.gen_arg([gen_arg(Tuple[Bytes, ...], data)])
            result = serde.serialize(to_cairo_type(Tuple[Bytes, ...]), base, shift=0)
            assert result == data

        @given(bytes32=...)
        def test_tuple_bytes32(
            self, to_cairo_type, segments, serde, gen_arg, bytes32: Tuple[Bytes32, ...]
        ):
            base = segments.gen_arg([gen_arg(Tuple[Bytes32, ...], bytes32)])
            result = serde.serialize(to_cairo_type(Tuple[Bytes32, ...]), base, shift=0)
            assert result == bytes32

    class TestForkTypes:

        @given(address=...)
        def test_address(
            self, to_cairo_type, segments, serde, gen_arg, address: Address
        ):
            base = segments.gen_arg([gen_arg(Address, address)])
            result = serde.serialize(to_cairo_type(Address), base, shift=0)
            assert result == address

        @given(root=...)
        def test_root(self, to_cairo_type, segments, serde, gen_arg, root: Root):
            base = segments.gen_arg([gen_arg(Root, root)])
            result = serde.serialize(to_cairo_type(Root), base, shift=0)
            assert result == root

        @given(versioned_hash=...)
        def test_versioned_hash(
            self,
            to_cairo_type,
            segments,
            serde,
            gen_arg,
            versioned_hash: VersionedHash,
        ):
            base = segments.gen_arg([gen_arg(VersionedHash, versioned_hash)])
            result = serde.serialize(
                to_cairo_type(VersionedHash),
                base,
                shift=0,
            )
            assert result == versioned_hash

        @given(bloom=...)
        def test_bloom(self, to_cairo_type, segments, serde, gen_arg, bloom: Bloom):
            base = segments.gen_arg([gen_arg(Bloom, bloom)])
            result = serde.serialize(to_cairo_type(Bloom), base, shift=0)
            assert result == bloom

        @given(account=...)
        def test_account(
            self, to_cairo_type, segments, serde, gen_arg, account: Account
        ):
            base = segments.gen_arg([gen_arg(Account, account)])
            result = serde.serialize(
                to_cairo_type(Account),
                base,
                shift=0,
            )
            assert result == account

    class TestBlocks:

        @given(withdrawal=...)
        def test_withdrawal(
            self, to_cairo_type, segments, serde, gen_arg, withdrawal: Withdrawal
        ):
            base = segments.gen_arg([gen_arg(Withdrawal, withdrawal)])
            result = serde.serialize(to_cairo_type(Withdrawal), base, shift=0)
            assert result == withdrawal

        @given(withdrawals=...)
        def test_tuple_withdrawal(
            self,
            to_cairo_type,
            segments,
            serde,
            gen_arg,
            withdrawals: Tuple[Withdrawal, ...],
        ):
            base = segments.gen_arg([gen_arg(Tuple[Withdrawal, ...], withdrawals)])
            result = serde.serialize(
                to_cairo_type(Tuple[Withdrawal, ...]), base, shift=0
            )
            assert result == withdrawals

        @given(header=...)
        def test_header(self, to_cairo_type, segments, serde, gen_arg, header: Header):
            base = segments.gen_arg([gen_arg(Header, header)])
            result = serde.serialize(to_cairo_type(Header), base, shift=0)
            assert result == header

        @given(headers=...)
        def test_tuple_header(
            self, to_cairo_type, segments, serde, gen_arg, headers: Tuple[Header, ...]
        ):
            base = segments.gen_arg([gen_arg(Tuple[Header, ...], headers)])
            result = serde.serialize(to_cairo_type(Tuple[Header, ...]), base, shift=0)
            assert result == headers

        @given(log=...)
        def test_log(self, to_cairo_type, segments, serde, gen_arg, log: Log):
            base = segments.gen_arg([gen_arg(Log, log)])
            result = serde.serialize(to_cairo_type(Log), base, shift=0)
            assert result == log

        @given(logs=...)
        def test_tuple_log(
            self, to_cairo_type, segments, serde, gen_arg, logs: Tuple[Log, ...]
        ):
            base = segments.gen_arg([gen_arg(Tuple[Log, ...], logs)])
            result = serde.serialize(to_cairo_type(Tuple[Log, ...]), base, shift=0)
            assert result == logs

        @given(receipt=...)
        def test_receipt(
            self, to_cairo_type, segments, serde, gen_arg, receipt: Receipt
        ):
            base = segments.gen_arg([gen_arg(Receipt, receipt)])
            result = serde.serialize(to_cairo_type(Receipt), base, shift=0)
            assert result == receipt

    class TestTransactions:

        @given(transaction=...)
        def test_transaction(
            self, to_cairo_type, segments, serde, gen_arg, transaction: Transaction
        ):
            base = segments.gen_arg([gen_arg(Transaction, transaction)])
            result = serde.serialize(
                to_cairo_type(Transaction),
                base,
                shift=0,
            )
            assert result == transaction
