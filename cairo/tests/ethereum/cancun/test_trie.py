from typing import Optional

import pytest
from hypothesis import assume, given

from ethereum.base_types import Bytes, Uint
from ethereum.cancun.fork_types import Account
from ethereum.cancun.trie import (
    InternalNode,
    Node,
    bytes_to_nibble_list,
    common_prefix_length,
    encode_internal_node,
    encode_node,
    nibble_list_to_compact,
)
from tests.utils.assertion import sequence_equal
from tests.utils.errors import cairo_error
from tests.utils.hints import patch_hint
from tests.utils.strategies import nibble


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
        self, cairo_run, node: Account
    ):
        with pytest.raises(AssertionError):
            encode_node(node, None)
        with cairo_error(message="encode_node"):
            cairo_run("encode_node", node, None)

    # def test_copy_trie(self, cairo_run, trie):
    #     assert copy_trie(trie) == cairo_run("copy_trie", trie)

    # @given(key=..., value=...)
    # def test_trie_set(self, cairo_run, key: K, value: V):
    #     assert trie_set(trie, key, value) == cairo_run("trie_set", trie, key, value)

    # @given(key=...)
    # def test_trie_get(self, cairo_run, key: K):
    #     assert trie_get(trie, key) == cairo_run("trie_get", trie, key)

    @given(a=..., b=...)
    def test_common_prefix_length(self, cairo_run, a: Bytes, b: Bytes):
        assert common_prefix_length(a, b) == cairo_run("common_prefix_length", a, b)

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
        self, cairo_program, cairo_run, x, is_leaf: bool
    ):
        with (
            patch_hint(
                cairo_program,
                "nondet %{ ids.x.value.len % 2 %};",
                "nondet %{ not (ids.x.value.len % 2) %};",
            ),
            cairo_error(message="nibble_list_to_compact: invalid remainder"),
        ):
            nibble_list_to_compact(x, is_leaf) == cairo_run(
                "nibble_list_to_compact", x, is_leaf
            )

    @given(bytes_=...)
    def test_bytes_to_nibble_list(self, cairo_run, bytes_: Bytes):
        assert bytes_to_nibble_list(bytes_) == cairo_run("bytes_to_nibble_list", bytes_)

    # def test_root(self, cairo_run, trie, get_storage_root):
    #     assert root(trie, get_storage_root) == cairo_run("root", trie, get_storage_root)

    # @given(level=...)
    # def test_patricialize(self, cairo_run, level: Uint):
    #     assert patricialize(obj, level) == cairo_run("patricialize", obj, level)
