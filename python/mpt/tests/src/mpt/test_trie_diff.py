from collections import defaultdict
from pathlib import Path
from typing import Mapping, Optional

import pytest
from ethereum.cancun.fork_types import Address
from ethereum.cancun.trie import (
    BranchNode,
    ExtensionNode,
    InternalNode,
    LeafNode,
    encode_internal_node,
)
from ethereum.crypto.hash import Hash32, keccak256
from ethereum_rlp import rlp
from ethereum_types.bytes import Bytes, Bytes32
from ethereum_types.numeric import U256
from hypothesis import assume, given
from hypothesis import strategies as st
from hypothesis.strategies import composite
from starkware.cairo.lang.vm.crypto import poseidon_hash_many

from cairo_addons.utils.uint256 import int_to_uint256
from mpt.ethereum_tries import EthereumTrieTransitionDB
from mpt.trie_diff import StateDiff, resolve
from mpt.utils import AccountNode, decode_node


@composite
def embedded_node_strategy(draw):
    storage_value = draw(st.from_type(U256))
    # subnodes is b"" except at index
    subnodes = [b"" for _ in range(16)]
    # inject storage_values into subnodes

    # Create leaf node and encode it
    leaf_node = LeafNode(rest_of_key=b"", value=rlp.encode(storage_value))
    embedded_leaf_node = encode_internal_node(leaf_node)
    assume(not isinstance(embedded_leaf_node, bytes))

    subnodes[draw(st.integers(min_value=0, max_value=15))] = list(embedded_leaf_node)

    branch_node = BranchNode(
        subnodes=tuple(subnodes),
        value=b"",
    )
    embedded_branch_node = encode_internal_node(branch_node)

    # Check that we're not constructing a node hash
    assume(not isinstance(embedded_branch_node, bytes))

    extension_node = ExtensionNode(
        key_segment=b"",
        subnode=embedded_branch_node,
    )

    return {
        "extension": extension_node,
        "branch": branch_node,
        "leaf": leaf_node,
    }


@pytest.fixture
def ethereum_trie_transition_db(data_path):
    return EthereumTrieTransitionDB.from_json(data_path)


@pytest.fixture(scope="session")
def node_store(zkpi):
    nodes = defaultdict(
        lambda: None,
        {
            keccak256(Bytes.fromhex(node[2:])): decode_node(Bytes.fromhex(node[2:]))
            for node in zkpi["witness"]["state"]
        },
    )
    return nodes


class TestTrieDiff:
    @pytest.mark.parametrize(
        "data_path", [Path("test_data/22081873.json")], scope="session"
    )
    def test_trie_diff(self, data_path, ethereum_trie_transition_db):
        # Python
        state_diff = StateDiff.from_json(data_path)
        trie_diff = StateDiff.from_tries(ethereum_trie_transition_db)
        assert trie_diff._main_trie == state_diff._main_trie
        assert trie_diff._storage_tries == state_diff._storage_tries

    @pytest.mark.parametrize(
        "data_path", [Path("test_data/22081873.json")], scope="session"
    )
    @given(data=st.data())
    def test_node_store_get(self, cairo_run, node_store, data):
        # take 20 keys from the node_store
        small_store = defaultdict(
            lambda: None, {k: v for k, v in list(node_store.items())[:6]}
        )
        existing_keys = list(small_store.keys())
        # take sample_size keys from small_store
        sample_size = data.draw(
            st.integers(min_value=5, max_value=min(10, len(small_store)))
        )
        keys = data.draw(
            st.lists(
                st.sampled_from(existing_keys),
                min_size=sample_size,
                max_size=sample_size,
                unique=True,
            )
        )
        # add a non-existing key which should return None
        keys.append(keccak256("non_existing".encode()))

        for key in keys:
            _, result = cairo_run("node_store_get", small_store, key)
            assert result == small_store.get(key)

    @given(path=..., account_before=..., account_after=...)
    def test__process_account_diff(
        self,
        cairo_run,
        path: Bytes32,
        account_before: Optional[AccountNode],
        account_after: Optional[AccountNode],
    ):
        # Python
        diff_cls = StateDiff()
        diff_cls._address_preimages = {path: keccak256(path)[:20]}
        leaf_before = (
            None
            if account_before is None
            else LeafNode(rest_of_key=b"", value=account_before.to_rlp())
        )
        leaf_after = (
            None
            if account_after is None
            else LeafNode(rest_of_key=b"", value=account_after.to_rlp())
        )
        diff_cls._process_account_diff(
            path=path,
            left=leaf_before,
            right=leaf_after,
        )

        result_diffs = cairo_run(
            "test__process_account_diff",
            address_preimages=diff_cls._address_preimages,
            path=path,
            left=leaf_before,
            right=leaf_after,
        )
        if not isinstance(result_diffs, list):
            result_diffs = [result_diffs]

        result_lookup = {
            dict_entry["key"]: (dict_entry["prev_value"], dict_entry["new_value"])
            for dict_entry in result_diffs
        }

        for key, (prev_value, new_value) in diff_cls._main_trie.items():
            assert (prev_value, new_value) == result_lookup[key]

    @given(path=..., address=..., storage_key_before=..., storage_key_after=...)
    def test__process_storage_diff(
        self,
        cairo_run,
        path: Bytes32,
        address: Address,
        storage_key_before: Optional[U256],
        storage_key_after: Optional[U256],
    ):
        diff_cls = StateDiff()
        # Fill preimages with arbitrary 32-bytes data
        diff_cls._storage_key_preimages = {path: keccak256(path)}
        leaf_before = (
            None
            if storage_key_before is None
            else LeafNode(rest_of_key=b"", value=rlp.encode(storage_key_before))
        )
        leaf_after = (
            None
            if storage_key_after is None
            else LeafNode(rest_of_key=b"", value=rlp.encode(storage_key_after))
        )
        diff_cls._process_storage_diff(
            address=address,
            path=path,
            left=leaf_before,
            right=leaf_after,
        )

        result_diffs = cairo_run(
            "test__process_storage_diff",
            storage_key_preimages=diff_cls._storage_key_preimages,
            path=path,
            address=address,
            left=leaf_before,
            right=leaf_after,
        )
        if not isinstance(result_diffs, list):
            result_diffs = [result_diffs]

        result_lookup = {
            diff["key"]: (diff["prev_value"], diff["new_value"])
            for diff in result_diffs
        }

        for key, (prev_value, new_value) in diff_cls._storage_tries[address].items():
            hashed_key = poseidon_hash_many(
                int_to_uint256(int.from_bytes(key, "little"))
            )
            assert (prev_value, new_value) == result_lookup[hashed_key]

    @pytest.mark.parametrize(
        "data_path", [Path("test_data/22081873.json")], scope="session"
    )
    @given(data=st.data())
    def test_resolve(self, cairo_run, node_store: Mapping[Hash32, InternalNode], data):
        # take 20 keys from the node_store
        small_store = defaultdict(
            lambda: None, {k: v for k, v in list(node_store.items())[:3]}
        )
        existing_keys = list(small_store.keys())
        # take sample_size keys from small_store
        sample_size = data.draw(
            st.integers(min_value=1, max_value=min(10, len(small_store)))
        )
        keys = data.draw(
            st.lists(
                st.sampled_from(existing_keys),
                min_size=sample_size,
                max_size=sample_size,
                unique=True,
            )
        )
        # add a non-existing key which should return None
        keys.append(keccak256("non_existing".encode()))

        for key in keys:
            _, cairo_result = cairo_run("resolve", small_store, node=bytes(key))
            result = resolve(key, small_store)
            assert result == cairo_result

            # check that resolving a node returns the same node
            _, node = cairo_run("resolve", small_store, result)
            assert node == resolve(result, small_store)

    @given(embedded_node_dict=embedded_node_strategy())
    def test_resolve_embedded_node(self, cairo_run, embedded_node_dict):
        # We don't need a node store for this test
        node_store = defaultdict(
            lambda: None,
        )
        parent_node = embedded_node_dict["extension"]
        expected_branch_node = embedded_node_dict["branch"]
        expected_leaf_node = embedded_node_dict["leaf"]

        _, cairo_result = cairo_run("resolve", node_store, node=parent_node)
        extension = resolve(parent_node, node_store)
        assert cairo_result == extension

        subnode = extension.subnode
        _, cairo_subnode = cairo_run("resolve", node_store, node=subnode)
        branch_node = resolve(subnode, node_store)
        assert cairo_subnode == branch_node
        assert cairo_subnode == expected_branch_node

        for subnode in branch_node.subnodes:
            _, cairo_subnode = cairo_run("resolve", node_store, node=subnode)
            subnode = resolve(subnode, node_store)
            assert cairo_subnode == subnode
            if isinstance(subnode, LeafNode):
                assert cairo_subnode == expected_leaf_node


class TestAccountNode:
    @given(account_node=...)
    def test_account_node_rlp(self, cairo_run, account_node: AccountNode):
        # Python from / to rlp
        rlp_encoded = account_node.to_rlp()
        decoded = AccountNode.from_rlp(rlp_encoded)
        assert decoded == account_node

        # Cairo from rlp
        cairo_decoded = cairo_run("AccountNode_from_rlp", encoding=rlp_encoded)
        assert cairo_decoded == account_node
