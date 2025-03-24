from collections import defaultdict
from pathlib import Path
from typing import Optional

import pytest
from ethereum.cancun.trie import LeafNode
from ethereum.crypto.hash import keccak256
from ethereum_types.bytes import Bytes, Bytes32
from hypothesis import HealthCheck, given, settings
from hypothesis import strategies as st

from mpt.ethereum_tries import EthereumTrieTransitionDB
from mpt.trie_diff import StateDiff
from mpt.utils import AccountNode, decode_node


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
    @settings(suppress_health_check=[HealthCheck.function_scoped_fixture])
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

        for dict_entry in result_diffs:
            key = dict_entry["key"]
            prev_value = dict_entry["prev_value"]
            new_value = dict_entry["new_value"]
            assert diff_cls._main_trie[key] == (prev_value, new_value)


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
