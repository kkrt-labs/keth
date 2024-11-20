from typing import Any, Tuple, Type, Union

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


def get_type(instance: Any) -> Type:
    if not isinstance(instance, tuple):
        return type(instance)

    # Empty tuple
    if not instance:
        return tuple

    # Get all element types
    elem_types = [get_type(x) for x in instance]

    # If all elements are the same type, use ellipsis
    if all(t == elem_types[0] for t in elem_types):
        return Tuple[elem_types[0], ...]

    # Otherwise return tuple of exact types
    return Tuple[tuple(elem_types)]


def no_empty_tuples(value: Any) -> bool:
    """Recursively check that no tuples (including nested ones) are empty."""
    if not isinstance(value, tuple):
        return True

    if not value:  # Empty tuple
        return False

    # Check each element recursively if it's a tuple
    return all(no_empty_tuples(x) if isinstance(x, tuple) else True for x in value)


class TestSerde:
    @given(b=...)
    @settings(max_examples=50 * len(_cairo_struct_to_python_type))
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
            Tuple[Bytes32, ...],
            Tuple[Bytes, ...],
            Tuple[Header, ...],
            Tuple[Withdrawal, ...],
            Tuple[Log, ...],
            Tuple[VersionedHash, ...],
            Tuple[Address, Tuple[Bytes32, ...]],
            Tuple[Tuple[Address, Tuple[Bytes32, ...]], ...],
        ],
    ):
        assume(no_empty_tuples(b))
        type_ = get_type(b)
        base = segments.gen_arg([gen_arg(type_, b)])
        result = serde.serialize(to_cairo_type(type_), base, shift=0)
        assert result == b
