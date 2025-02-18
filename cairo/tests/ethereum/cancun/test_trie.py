from collections import defaultdict
from typing import Mapping, Optional, Tuple, Union

import pytest
from ethereum.cancun.blocks import Receipt, Withdrawal
from ethereum.cancun.fork_types import Account, Address, Root
from ethereum.cancun.state import EMPTY_TRIE_ROOT
from ethereum.cancun.transactions import LegacyTransaction
from ethereum.cancun.trie import (
    BranchNode,
    ExtensionNode,
    InternalNode,
    LeafNode,
    Node,
    Trie,
    _prepare_trie,
    bytes_to_nibble_list,
    common_prefix_length,
    copy_trie,
    encode_internal_node,
    encode_node,
    nibble_list_to_compact,
    patricialize,
    root,
    trie_get,
    trie_set,
)
from ethereum_types.bytes import Bytes, Bytes32
from ethereum_types.numeric import U256, Uint
from hypothesis import Verbosity, example, given, settings
from hypothesis import strategies as st

from cairo_addons.testing.errors import cairo_error, strict_raises
from cairo_addons.testing.hints import patch_hint
from tests.utils.args_gen import EthereumTries
from tests.utils.assertion import sequence_equal
from tests.utils.strategies import bytes32, nibble, trie_strategy, uint4


@st.composite
def prepare_trie_strategy(draw):
    key_type, value_type = draw(
        st.sampled_from([t.__args__ for t in EthereumTries.__args__])
    )
    return draw(trie_strategy(thing=Trie[key_type, value_type], include_none=True))


class TestTrie:
    @given(node=...)
    def test_encode_internal_node(self, cairo_run, node: Optional[InternalNode]):
        assert sequence_equal(
            encode_internal_node(node), cairo_run("encode_internal_node", node)
        )

    @given(node=..., storage_root=...)
    @example(node=None, storage_root=None)
    @example(node=Uint(145), storage_root=None)
    def test_encode_node(self, cairo_run, node: Node, storage_root: Optional[Bytes]):
        try:
            cairo_result = cairo_run("encode_node", node, storage_root)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                encode_node(node, storage_root)
            return
        result = encode_node(node, storage_root)
        assert cairo_result == result

    @given(node=...)
    def test_encode_account_should_fail_without_storage_root(
        self, cairo_run, node: Account
    ):
        with pytest.raises(AssertionError):
            encode_node(node, None)
        with pytest.raises(AssertionError):
            cairo_run("encode_node", node, None)

    @given(a=..., b=...)
    def test_common_prefix_length(self, cairo_run, a: Bytes, b: Bytes):
        assert common_prefix_length(a, b) == cairo_run("common_prefix_length", a, b)

    @given(a=..., b=...)
    @settings(verbosity=Verbosity.quiet)
    def test_common_prefix_length_should_fail(
        self, cairo_programs, cairo_run_py, a: Bytes, b: Bytes
    ):
        with (
            patch_hint(
                cairo_programs,
                "common_prefix_length_hint",
                "import random; memory[fp] = random.randint(0, 100)",
            ),
            cairo_error(message="common_prefix_length"),
        ):
            assert common_prefix_length(a, b) == cairo_run_py(
                "common_prefix_length", a, b
            )

    @given(x=nibble, is_leaf=...)
    def test_nibble_list_to_compact(self, cairo_run, x, is_leaf: bool):
        assert nibble_list_to_compact(x, is_leaf) == cairo_run(
            "nibble_list_to_compact", x, is_leaf
        )

    @given(x=nibble.filter(lambda x: len(x) != 0), is_leaf=...)
    @settings(verbosity=Verbosity.quiet)
    def test_nibble_list_to_compact_should_raise_when_wrong_remainder(
        self, cairo_programs, cairo_run_py, x, is_leaf: bool
    ):
        with (
            patch_hint(
                cairo_programs,
                "value_len_mod_two",
                "ids.remainder = not (ids.len % 2)",
            ),
            cairo_error(message="nibble_list_to_compact: invalid remainder"),
        ):
            # Always run patch_hint tests with the python VM
            cairo_run_py("nibble_list_to_compact", x, is_leaf)

    @given(bytes_=...)
    def test_bytes_to_nibble_list(self, cairo_run, bytes_: Bytes):
        assert bytes_to_nibble_list(bytes_) == cairo_run("bytes_to_nibble_list", bytes_)

    @given(
        obj=st.dictionaries(nibble, bytes32).filter(
            lambda x: len(x) > 0 and all(len(k) > 0 for k in x)
        ),
        nibble=uint4,
        level=uint4,
    )
    def test_get_branch_for_nibble_at_level(self, cairo_run, obj, nibble, level):
        prefix = (b"prefix" * 3)[:level]
        obj = {(prefix + k)[:64]: v for k, v in obj.items()}
        branch, value = cairo_run("_get_branch_for_nibble_at_level", obj, nibble, level)
        assert branch == {
            k: v for k, v in obj.items() if k[level] == nibble and len(k) > level
        }
        assert value == obj.get(level, b"")

    @given(
        obj=st.dictionaries(nibble, bytes32).filter(
            lambda x: len(x) > 0 and all(len(k) > 0 for k in x)
        ),
        level=uint4,
    )
    def test_get_branches(self, cairo_run, obj, level):
        prefix = (b"prefix" * 3)[:level]
        obj = {(prefix + k)[:64]: v for k, v in obj.items() if len(k) > 0}
        branches, value = cairo_run("_get_branches", obj, level)
        assert branches == tuple(
            {k: v for k, v in obj.items() if k[level] == nibble and len(k) > level}
            for nibble in range(16)
        )
        assert value == obj.get(level, b"")

    @pytest.mark.slow
    @given(obj=st.dictionaries(nibble, bytes32, max_size=100))
    def test_patricialize(self, cairo_run, obj: Mapping[Bytes, Bytes]):
        assert patricialize(obj, Uint(0)) == cairo_run("patricialize", obj, Uint(0))

    @given(leaf_node=...)
    def test_internal_node_leaf_node(self, cairo_run, leaf_node: LeafNode):
        result = cairo_run("InternalNodeImpl.leaf_node", leaf_node)
        assert result == leaf_node

    @given(extension_node=...)
    def test_internal_node_extension_node(
        self, cairo_run, extension_node: ExtensionNode
    ):
        result = cairo_run("InternalNodeImpl.extension_node", extension_node)
        assert result == extension_node

    @given(branch_node=...)
    def test_internal_node_branch_node(self, cairo_run, branch_node: BranchNode):
        result = cairo_run("InternalNodeImpl.branch_node", branch_node)
        assert result == branch_node

    @given(trie_with_none=prepare_trie_strategy(), storage_tries=...)
    def test_prepare_trie(
        self,
        cairo_run,
        trie_with_none: EthereumTries,
        storage_tries: Mapping[Address, Trie[Bytes32, U256]],
    ):
        key_type, _ = trie_with_none.__orig_class__.__args__

        # Python expects tries not to have None values (as writing the default None suppresses the key)
        # In Cairo, the filtering is done in `prepare_trie` where they're filtered out of the output
        # Mapping during iteration over dict entries.
        trie = Trie(
            secured=trie_with_none.secured,
            default=trie_with_none.default,
            _data=defaultdict(
                trie_with_none._data.default_factory,
                {k: v for k, v in trie_with_none._data.items() if v is not None},
            ),
        )

        if key_type is Address:
            # Cairo expects a Dict[Address, Root] as storage_roots - not a callable function
            storage_roots = defaultdict(
                lambda: U256.from_le_bytes(EMPTY_TRIE_ROOT),
                {
                    address: U256.from_le_bytes(root(storage_tries[address]))
                    for address in storage_tries
                },
            )

            def get_storage_root(address: Address) -> Root:
                return storage_roots[address].to_le_bytes32()

        else:
            storage_roots = None
            get_storage_root = None

        try:
            result_cairo = cairo_run("_prepare_trie", trie_with_none, storage_roots)
        except Exception as e:
            with strict_raises(type(e)):
                _prepare_trie(trie, get_storage_root)
            return

        assert result_cairo == _prepare_trie(trie, get_storage_root)

    @given(trie_with_none=prepare_trie_strategy(), storage_tries=...)
    def test_root(
        self,
        cairo_run,
        trie_with_none: EthereumTries,
        storage_tries: Mapping[Address, Trie[Bytes32, U256]],
    ):
        key_type, _ = trie_with_none.__orig_class__.__args__

        # Python expects tries not to have None values (as writing the default None suppresses the key)
        # In Cairo, the filtering is done in `prepare_trie` where they're filtered out of the output
        # Mapping during iteration over dict entries.
        trie = Trie(
            secured=trie_with_none.secured,
            default=trie_with_none.default,
            _data={k: v for k, v in trie_with_none._data.items() if v is not None},
        )

        if key_type is Address:
            # Cairo expects a Dict[Address, Root] as storage_roots - not a callable function
            storage_roots = defaultdict(
                lambda: U256.from_le_bytes(EMPTY_TRIE_ROOT),
                {
                    address: U256.from_le_bytes(root(storage_tries[address]))
                    for address in storage_tries
                },
            )

            def get_storage_root(address: Address) -> Root:
                return storage_roots[address].to_le_bytes32()

        else:
            storage_roots = None
            get_storage_root = None

        try:
            result_cairo = cairo_run("root", trie_with_none, storage_roots)
        except Exception as e:
            with strict_raises(type(e)):
                root(trie, get_storage_root)
            return
        assert result_cairo == root(trie, get_storage_root)


class TestTrieOperations:
    class TestGet:
        @given(trie=..., key=...)
        def test_trie_get_TrieAddressOptionalAccount(
            self, cairo_run, trie: Trie[Address, Optional[Account]], key: Address
        ):
            trie_cairo, result_cairo = cairo_run(
                "trie_get_TrieAddressOptionalAccount", trie, key
            )
            result_py = trie_get(trie, key)
            assert result_cairo == result_py
            assert trie_cairo == trie

        @given(trie=..., key=...)
        def test_trie_get_TrieBytes32U256(
            self, cairo_run, trie: Trie[Bytes32, U256], key: Bytes32
        ):
            trie_cairo, result_cairo = cairo_run("trie_get_TrieBytes32U256", trie, key)
            result_py = trie_get(trie, key)
            assert result_cairo == result_py
            assert trie_cairo == trie

        @given(trie=..., key_tuple=...)
        def test_trie_get_TrieTupleAddressBytes32U256(
            self,
            cairo_run,
            trie: Trie[Tuple[Address, Bytes32], U256],
            key_tuple: Tuple[Address, Bytes32],
        ):
            address, key = key_tuple
            trie_cairo, result_cairo = cairo_run(
                "trie_get_TrieTupleAddressBytes32U256", trie, address, key
            )
            result_py = trie_get(trie, key_tuple)
            assert result_cairo == result_py
            assert trie_cairo == trie

        @given(trie=..., key=...)
        def test_trie_get_TrieBytesOptionalUnionBytesLegacyTransaction(
            self,
            cairo_run,
            trie: Trie[Bytes, Optional[Union[Bytes, LegacyTransaction]]],
            key: Bytes,
        ):
            trie_cairo, result_cairo = cairo_run(
                "trie_get_TrieBytesOptionalUnionBytesLegacyTransaction", trie, key
            )
            result_py = trie_get(trie, key)
            assert result_cairo == result_py
            assert trie_cairo == trie

        @given(trie=..., key=...)
        def test_trie_get_TrieBytesOptionalUnionBytesReceipt(
            self,
            cairo_run,
            trie: Trie[Bytes, Optional[Union[Bytes, Receipt]]],
            key: Bytes,
        ):
            trie_cairo, result_cairo = cairo_run(
                "trie_get_TrieBytesOptionalUnionBytesReceipt", trie, key
            )
            result_py = trie_get(trie, key)
            assert result_cairo == result_py
            assert trie_cairo == trie

        @given(trie=..., key=...)
        def test_trie_get_TrieBytesOptionalUnionBytesWithdrawal(
            self,
            cairo_run,
            trie: Trie[Bytes, Optional[Union[Bytes, Withdrawal]]],
            key: Bytes,
        ):
            trie_cairo, result_cairo = cairo_run(
                "trie_get_TrieBytesOptionalUnionBytesWithdrawal", trie, key
            )
            assert result_cairo == trie_get(trie, key)
            assert trie_cairo == trie

    class TestSet:
        @given(trie=..., key=..., value=...)
        def test_trie_set_TrieAddressOptionalAccount(
            self,
            cairo_run,
            trie: Trie[Address, Optional[Account]],
            key: Address,
            value: Account,
        ):
            cairo_trie = cairo_run(
                "trie_set_TrieAddressOptionalAccount", trie, key, value
            )
            trie_set(trie, key, value)
            assert cairo_trie == trie

        @given(trie=..., key=..., value=...)
        def test_trie_set_TrieBytes32U256(
            self, cairo_run, trie: Trie[Bytes32, U256], key: Bytes32, value: U256
        ):
            cairo_trie = cairo_run("trie_set_TrieBytes32U256", trie, key, value)
            trie_set(trie, key, value)
            assert cairo_trie == trie

        @given(trie=..., key_tuple=..., value=...)
        def test_trie_set_TrieTupleAddressBytes32U256(
            self,
            cairo_run,
            trie: Trie[Tuple[Address, Bytes32], U256],
            key_tuple: Tuple[Address, Bytes32],
            value: U256,
        ):
            address, key = key_tuple
            cairo_trie = cairo_run(
                "trie_set_TrieTupleAddressBytes32U256", trie, address, key, value
            )
            trie_set(trie, key_tuple, value)
            assert cairo_trie == trie

        @given(trie=..., key=..., value=...)
        def test_trie_set_TrieBytesOptionalUnionBytesLegacyTransaction(
            self,
            cairo_run,
            trie: Trie[Bytes, Optional[Union[Bytes, LegacyTransaction]]],
            key: Bytes,
            value: Union[Bytes, LegacyTransaction],
        ):
            cairo_trie = cairo_run(
                "trie_set_TrieBytesOptionalUnionBytesLegacyTransaction",
                trie,
                key,
                value,
            )
            trie_set(trie, key, value)
            assert cairo_trie == trie

        @given(trie=..., key=..., value=...)
        def test_trie_set_TrieBytesOptionalUnionBytesReceipt(
            self,
            cairo_run,
            trie: Trie[Bytes, Optional[Union[Bytes, Receipt]]],
            key: Bytes,
            value: Union[Bytes, Receipt],
        ):
            cairo_trie = cairo_run(
                "trie_set_TrieBytesOptionalUnionBytesReceipt", trie, key, value
            )
            trie_set(trie, key, value)
            assert cairo_trie == trie

        @given(trie=..., key=..., value=...)
        def test_trie_set_TrieBytesOptionalUnionBytesWithdrawal(
            self,
            cairo_run,
            trie: Trie[Bytes, Optional[Union[Bytes, Withdrawal]]],
            key: Bytes,
            value: Union[Bytes, Withdrawal],
        ):
            cairo_trie = cairo_run(
                "trie_set_TrieBytesOptionalUnionBytesWithdrawal", trie, key, value
            )
            trie_set(trie, key, value)
            assert cairo_trie == trie

    class TestCopy:
        @given(trie=...)
        def test_copy_trie_AddressAccount(
            self, cairo_run, trie: Trie[Address, Optional[Account]]
        ):
            original_trie, copied_trie_cairo = cairo_run(
                "copy_TrieAddressOptionalAccount", trie
            )
            copied_trie_py = copy_trie(trie)
            assert original_trie == trie
            assert copied_trie_cairo == copied_trie_py

        @given(trie=...)
        def test_copy_trie_TupleAddressBytes32U256(
            self, cairo_run, trie: Trie[Tuple[Address, Bytes32], U256]
        ):
            original_trie, copied_trie_cairo = cairo_run(
                "copy_TrieTupleAddressBytes32U256", trie
            )
            copied_trie_py = copy_trie(trie)
            assert original_trie == trie
            assert copied_trie_cairo == copied_trie_py
