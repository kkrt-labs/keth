import pytest
from hypothesis import given
from hypothesis import strategies as st
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
from ethereum.cancun.fork_types import Address, Bloom, Root, VersionedHash
from tests.utils.hints import gen_arg as _gen_arg
from tests.utils.serde import Serde
from tests.utils.serde import get_cairo_type as _get_cairo_type
from tests.utils.strategies import (
    account,
    block,
    bytes0,
    bytes8,
    bytes20,
    bytes32,
    bytes256,
    header,
    log,
    receipt,
    uint,
    uint64,
    uint128,
    uint256,
    withdrawal,
)


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
def get_cairo_type(cairo_program):
    def _factory(name):
        return _get_cairo_type(cairo_program, name)

    return _factory


class TestSerde:

    class TestBaseTypes:

        @given(b=st.booleans())
        def test_bool(self, get_cairo_type, serde, gen_arg, b):
            base = gen_arg([b])
            result = serde.serialize(
                get_cairo_type("ethereum.base_types.bool"), base, shift=0
            )
            # bool is a also int in Python
            assert result == int(b)

        @given(n=uint64.map(U64))
        def test_u64(self, get_cairo_type, serde, gen_arg, n):
            base = gen_arg([n])
            result = serde.serialize(
                get_cairo_type("ethereum.base_types.U64"), base, shift=0
            )
            assert result == n

        @given(n=uint128)
        def test_u128(self, get_cairo_type, serde, gen_arg, n):
            """
            This type is not used in the spec, but it's a good sanity check in
            Cairo where a lot of functions expect a < RC_BOUND value.
            """
            base = gen_arg([n])
            result = serde.serialize(
                get_cairo_type("ethereum.base_types.U128"), base, shift=0
            )
            assert result == n

        @given(n=uint.map(Uint))
        def test_uint(self, get_cairo_type, serde, gen_arg, n):
            base = gen_arg([n])
            result = serde.serialize(
                get_cairo_type("ethereum.base_types.Uint"), base, shift=0
            )
            assert result == n

        @given(n=uint256.map(U256))
        def test_u256(self, get_cairo_type, serde, gen_arg, n):
            base = gen_arg([n])
            result = serde.serialize(
                get_cairo_type("ethereum.base_types.U256"), base, shift=0
            )
            assert result == n

        @given(data=bytes0.map(Bytes0))
        def test_bytes0(self, get_cairo_type, serde, gen_arg, data):
            base = gen_arg([data])
            result = serde.serialize(
                get_cairo_type("ethereum.base_types.Bytes0"), base, shift=0
            )
            assert result == data

        @given(data=bytes8.map(Bytes8))
        def test_bytes8(self, get_cairo_type, serde, gen_arg, data):
            base = gen_arg([data])
            result = serde.serialize(
                get_cairo_type("ethereum.base_types.Bytes8"), base, shift=0
            )
            assert result == data

        @given(data=bytes20.map(Bytes20))
        def test_bytes20(self, get_cairo_type, serde, gen_arg, data):
            base = gen_arg([data])
            result = serde.serialize(
                get_cairo_type("ethereum.base_types.Bytes20"), base, shift=0
            )
            assert result == data

        @given(data=bytes32.map(Bytes32))
        def test_bytes32(self, get_cairo_type, serde, gen_arg, data):
            base = gen_arg([data])
            result = serde.serialize(
                get_cairo_type("ethereum.base_types.Bytes32"), base, shift=0
            )
            assert result == data

        @given(data=bytes256.map(Bytes256))
        def test_bytes256(self, get_cairo_type, serde, gen_arg, data):
            base = gen_arg([data])
            result = serde.serialize(
                get_cairo_type("ethereum.base_types.Bytes256"), base, shift=0
            )
            assert result == data

        @given(data=st.binary(min_size=0, max_size=100).map(Bytes))
        def test_bytes(self, get_cairo_type, serde, gen_arg, data):
            base = gen_arg([data])
            result = serde.serialize(
                get_cairo_type("ethereum.base_types.Bytes"), base, shift=0
            )
            assert result == data

        @given(data=st.tuples(st.binary(min_size=0, max_size=100).map(Bytes)))
        def test_tuple_bytes(self, get_cairo_type, serde, gen_arg, data):
            base = gen_arg([data])
            result = serde.serialize(
                get_cairo_type("ethereum.base_types.TupleBytes"), base, shift=0
            )
            assert result == data

        @given(data=st.tuples(bytes32.map(Bytes32)))
        def test_tuple_bytes32(self, get_cairo_type, serde, gen_arg, data):
            base = gen_arg([data])
            result = serde.serialize(
                get_cairo_type("ethereum.base_types.TupleBytes32"), base, shift=0
            )
            assert result == data

    class TestForkTypes:

        @given(data=bytes20.map(Address))
        def test_address(self, get_cairo_type, serde, gen_arg, data):
            base = gen_arg([data])
            result = serde.serialize(
                get_cairo_type("ethereum.cancun.fork_types.Address"), base, shift=0
            )
            assert result == data

        @given(data=bytes32.map(Root))
        def test_root(self, get_cairo_type, serde, gen_arg, data):
            base = gen_arg([data])
            result = serde.serialize(
                get_cairo_type("ethereum.cancun.fork_types.Root"), base, shift=0
            )
            assert result == data

        @given(data=bytes32.map(VersionedHash))
        def test_versioned_hash(self, get_cairo_type, serde, gen_arg, data):
            base = gen_arg([data])
            result = serde.serialize(
                get_cairo_type("ethereum.cancun.fork_types.VersionedHash"),
                base,
                shift=0,
            )
            assert result == data

        @given(data=bytes256.map(Bloom))
        def test_bloom(self, get_cairo_type, serde, gen_arg, data):
            base = gen_arg([data])
            result = serde.serialize(
                get_cairo_type("ethereum.cancun.fork_types.Bloom"), base, shift=0
            )
            assert result == data

        @given(account)
        def test_account(self, get_cairo_type, serde, gen_arg, account):
            base = gen_arg([account])
            result = serde.serialize(
                get_cairo_type("ethereum.cancun.fork_types.Account"),
                base,
                shift=0,
            )
            assert result == account

    class TestBlocks:

        @given(withdrawal)
        def test_withdrawal(self, get_cairo_type, serde, gen_arg, withdrawal):
            base = gen_arg([withdrawal])
            result = serde.serialize(
                get_cairo_type("ethereum.cancun.blocks.Withdrawal"), base, shift=0
            )
            assert result == withdrawal

        @given(st.tuples(withdrawal))
        def test_tuple_withdrawal(self, get_cairo_type, serde, gen_arg, data):
            base = gen_arg([data])
            result = serde.serialize(
                get_cairo_type("ethereum.cancun.blocks.TupleWithdrawal"), base, shift=0
            )
            assert result == data

        @given(header)
        def test_header(self, get_cairo_type, serde, gen_arg, header):
            base = gen_arg([header])
            result = serde.serialize(
                get_cairo_type("ethereum.cancun.blocks.Header"), base, shift=0
            )
            assert result == header

        @given(st.tuples(header))
        def test_tuple_header(self, get_cairo_type, serde, gen_arg, data):
            base = gen_arg([data])
            result = serde.serialize(
                get_cairo_type("ethereum.cancun.blocks.TupleHeader"), base, shift=0
            )
            assert result == data

        @given(log)
        def test_log(self, get_cairo_type, serde, gen_arg, log):
            base = gen_arg([log])
            result = serde.serialize(
                get_cairo_type("ethereum.cancun.blocks.Log"), base, shift=0
            )
            assert result == log

        @given(st.tuples(log))
        def test_tuple_log(self, get_cairo_type, serde, gen_arg, data):
            base = gen_arg([data])
            result = serde.serialize(
                get_cairo_type("ethereum.cancun.blocks.TupleLog"), base, shift=0
            )
            assert result == data

        @given(receipt)
        def test_receipt(self, get_cairo_type, serde, gen_arg, receipt):
            base = gen_arg([receipt])
            result = serde.serialize(
                get_cairo_type("ethereum.cancun.blocks.Receipt"), base, shift=0
            )
            assert result == receipt

        @given(block)
        def test_block(self, get_cairo_type, serde, gen_arg, block):
            base = gen_arg([block])
            result = serde.serialize(
                get_cairo_type("ethereum.cancun.blocks.Block"), base, shift=0
            )
            assert result == block
