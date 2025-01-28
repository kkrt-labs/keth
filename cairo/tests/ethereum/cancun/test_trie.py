from typing import Mapping, Optional, Tuple

import pytest
from cairo_addons.testing.hints import patch_hint
from ethereum_types.bytes import Bytes, Bytes32
from ethereum_types.numeric import U256, Uint
from hypothesis import assume, given, settings
from hypothesis import strategies as st

from ethereum.cancun.fork_types import Account, Address
from ethereum.cancun.trie import (
    InternalNode,
    Node,
    Trie,
    bytes_to_nibble_list,
    common_prefix_length,
    copy_trie,
    encode_internal_node,
    encode_node,
    nibble_list_to_compact,
    patricialize,
    trie_get,
    trie_set,
)
from tests.utils.assertion import sequence_equal
from tests.utils.errors import cairo_error
from tests.utils.strategies import bytes32, nibble, uint4


class TestTrie:
    @given(node=...)
    def test_encode_internal_node(self, cairo_run, node: Optional[InternalNode]):
        assert sequence_equal(
            encode_internal_node(node), cairo_run("encode_internal_node", node)
        )

    @given(node=..., storage_root=...)
    def test_encode_node(self, cairo_run, node: Node, storage_root: Optional[Bytes]):
        assume(node is not None)
        assume(not isinstance(node, Uint))
        assume(not (isinstance(node, Account) and storage_root is None))
        assert encode_node(node, storage_root) == cairo_run(
            "encode_node", node, storage_root
        )

    @given(node=...)
    def test_encode_account_should_fail_without_storage_root(
        self, cairo_run_py, node: Account
    ):
        with pytest.raises(AssertionError):
            encode_node(node, None)
        with cairo_error(message="encode_node"):
            cairo_run_py("encode_node", node, None)

    @given(a=..., b=...)
    def test_common_prefix_length(self, cairo_run_py, a: Bytes, b: Bytes):
        assert common_prefix_length(a, b) == cairo_run_py("common_prefix_length", a, b)

    @given(a=..., b=...)
    def test_common_prefix_length_should_fail(
        self, cairo_program, cairo_run, a: Bytes, b: Bytes
    ):
        with (
            patch_hint(
                cairo_program,
                'memory[fp] = oracle(ids, reference="ethereum.cancun.trie.common_prefix_length")',
                "import random; memory[fp] = random.randint(0, 100)",
            ),
            cairo_error(message="common_prefix_length"),
        ):
            assert common_prefix_length(a, b) == cairo_run("common_prefix_length", a, b)

    @given(x=nibble, is_leaf=...)
    def test_nibble_list_to_compact(self, cairo_run, x, is_leaf: bool):
        assert nibble_list_to_compact(x, is_leaf) == cairo_run(
            "nibble_list_to_compact", x, is_leaf
        )

    @given(x=nibble.filter(lambda x: len(x) != 0), is_leaf=...)
    def test_nibble_list_to_compact_should_raise_when_wrong_remainder(
        self, cairo_program, cairo_run_py, x, is_leaf: bool
    ):
        with (
            patch_hint(
                cairo_program,
                "nondet %{ ids.x.value.len % 2 %};",
                "nondet %{ not (ids.x.value.len % 2) %};",
            ),
            cairo_error(message="nibble_list_to_compact: invalid remainder"),
        ):
            # Always run patch_hint tests with the python VM
            cairo_run_py("nibble_list_to_compact", x, is_leaf)

    @given(bytes_=...)
    def test_bytes_to_nibble_list(self, cairo_run_py, bytes_: Bytes):
        assert bytes_to_nibble_list(bytes_) == cairo_run_py(
            "bytes_to_nibble_list", bytes_
        )

    # def test_root(self, cairo_run, trie, get_storage_root):
    #     assert root(trie, get_storage_root) == cairo_run("root", trie, get_storage_root)

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
        branche, value = cairo_run(
            "_get_branch_for_nibble_at_level", obj, nibble, level
        )
        assert branche == {
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
    @settings(max_examples=20)
    @given(obj=st.dictionaries(nibble, bytes32, max_size=100))
    def test_patricialize(self, cairo_run_py, obj: Mapping[Bytes, Bytes]):
        assert patricialize(obj, Uint(0)) == cairo_run_py("patricialize", obj, Uint(0))


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
