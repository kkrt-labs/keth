from typing import Tuple, Type, Union, get_origin

import pytest
from hypothesis import assume, given, settings
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
from tests.utils.args_gen import _cairo_struct_to_python_type
from tests.utils.args_gen import gen_arg as _gen_arg
from tests.utils.args_gen import to_cairo_type as _to_cairo_type
from tests.utils.serde import Serde


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


value_types = {
    v for v in _cairo_struct_to_python_type.values() if get_origin(v) is not tuple
}

tuple_types = {
    v for v in _cairo_struct_to_python_type.values() if get_origin(v) is tuple
}


class TestSerde:

    @given(b=...)
    @settings(max_examples=50 * len(value_types))
    def test_type(
        self,
        to_cairo_type,
        segments,
        serde,
        gen_arg,
        b: Union[
            bool,
            U64,
            Uint,
            U256,
            Bytes0,
            Bytes8,
            Bytes20,
            Bytes32,
            Bytes256,
            Bytes,
            Address,
            Root,
            VersionedHash,
            Bloom,
            Account,
            Transaction,
            Receipt,
        ],
    ):
        base = segments.gen_arg([gen_arg(type(b), b)])
        result = serde.serialize(to_cairo_type(type(b)), base, shift=0)
        assert result == b

    @given(b=...)
    @settings(max_examples=50 * len(tuple_types))
    def test_tuple_type(
        self,
        to_cairo_type,
        segments,
        serde,
        gen_arg,
        b: Union[
            Tuple[Bytes32, ...],
            Tuple[Bytes, ...],
            Tuple[Header, ...],
            Tuple[Withdrawal, ...],
            Tuple[Log, ...],
            Tuple[VersionedHash, ...],
        ],
    ):
        assume(len(b) > 0)
        type_ = Tuple[type(b[0]), ...]
        base = segments.gen_arg([gen_arg(type_, b)])
        result = serde.serialize(to_cairo_type(type_), base, shift=0)
        assert result == b
