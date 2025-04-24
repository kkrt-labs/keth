import re
from pathlib import Path
from typing import Dict, Mapping, Optional, Tuple, Union

import pytest
from ethereum.cancun.fork_types import EMPTY_ACCOUNT, Account, Address
from ethereum.cancun.trie import (
    BranchNode,
    ExtensionNode,
    InternalNode,
    LeafNode,
    bytes_to_nibble_list,
    encode_internal_node,
)
from ethereum.crypto.hash import Hash32, keccak256
from ethereum_rlp import rlp
from ethereum_rlp.rlp import Extended
from ethereum_types.bytes import Bytes, Bytes32
from ethereum_types.numeric import U256
from hypothesis import assume, given
from hypothesis import strategies as st
from hypothesis.strategies import composite

from cairo_addons.rust_bindings.vm import poseidon_hash_many
from cairo_addons.utils.uint256 import int_to_uint256
from keth_types.types import EMPTY_TRIE_HASH, encode_account
from mpt.ethereum_tries import EthereumTries, EthereumTrieTransitionDB
from mpt.trie_builder import TrieTestBuilder
from mpt.trie_diff import StateDiff, resolve
from mpt.utils import decode_node


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


@composite
def invalid_mpt_strategy(draw, invalid_case: str):
    """
    Creates a EthereumTries that is invalid.
    Invalid cases:
    1. Branch Node:
        - Non-empty value.
        - Less than two non-null subnodes.
    2. Extension Node:
        - Empty key segment.
        - None subnode.
    3. Leaf Node:
        - Empty value.
        - Length of rest_of_key plus path > 64.
    """

    builder = TrieTestBuilder()

    address = draw(st.from_type(Address))
    nibble_path = bytes_to_nibble_list(keccak256(address))
    other_address = draw(st.from_type(Address))
    other_nibble_path = bytes_to_nibble_list(keccak256(other_address))
    # Ensure the first nibble is different
    assume(nibble_path[0] != other_nibble_path[0])

    account = draw(st.from_type(Account))
    assume(account != EMPTY_ACCOUNT)
    leaf_value = encode_account(account, EMPTY_TRIE_HASH)

    match invalid_case:
        case "NonEmptyBytesValue":
            branch = builder.branch()
            branch.with_value(leaf_value)
            branch.with_leaf(nibble_path[0], nibble_path[1:], leaf_value)
            builder.build()

        case "LTTwoNonNullSubnodes":
            branch = builder.branch()
            length = draw(st.integers(min_value=0, max_value=1))
            match length:
                case 0:
                    pass
                case 1:
                    branch.with_leaf(nibble_path[0], nibble_path[1:], leaf_value)
            builder.build()

        case "EmptyKeySegment":
            extension = builder.extension(b"")
            extension.with_leaf(nibble_path, leaf_value)
            builder.build()

        case "EmptySubnode":
            branch = builder.branch()
            branch.with_extension(nibble_path[0], nibble_path[1:])
            branch.with_leaf(other_nibble_path[0], other_nibble_path[1:], leaf_value)
            builder.build()

        case "EmptyValue":
            branch = builder.branch()
            branch.with_leaf(nibble_path[0], nibble_path[1:], b"")
            branch.with_leaf(other_nibble_path[0], other_nibble_path[1:], leaf_value)
            builder.build()

        case "InvalidFullPath":
            branch = builder.branch()
            # Incorrect: use the first nibble and the full path (65 nibbles)
            branch.with_leaf(nibble_path[0], nibble_path, leaf_value)
            # Correct: use the first nibble and the rest of the path (64 nibbles)
            branch.with_leaf(other_nibble_path[0], other_nibble_path[1:], leaf_value)
            builder.build()

        case "InvalidParent":
            extension = builder.extension(nibble_path[0:1])
            ext_child = extension.with_extension(nibble_path[1:2])
            ext_child.with_leaf(nibble_path[2:], leaf_value)
            builder.build()

    return builder.to_ethereum_tries(addresses=[address, other_address])


@pytest.fixture(scope="session")
def empty_ethereum_tries():
    """Provides an empty, valid EthereumTrie instance."""
    return EthereumTries(
        nodes={},
        codes={},
        address_preimages={},
        storage_key_preimages={},
        state_root=EMPTY_TRIE_HASH,
    )


@pytest.fixture
def ethereum_trie_transition_db(data_path):
    return EthereumTrieTransitionDB.from_json(data_path)


@pytest.fixture(scope="session")
def node_store(zkpi):
    nodes = {
        keccak256(Bytes.fromhex(node[2:])): Bytes.fromhex(node[2:])
        for node in zkpi["witness"]["state"]
    }
    return nodes


class TestTrieDiff:
    @pytest.mark.parametrize(
        "data_path", [Path("test_data/21688509.json")], scope="session"
    )
    def test_trie_diff(
        self,
        cairo_run,
        data_path,
        ethereum_trie_transition_db: EthereumTrieTransitionDB,
    ):
        # Python
        state_diff = StateDiff.from_json(data_path)
        trie_diff = StateDiff.from_tries(ethereum_trie_transition_db)
        assert trie_diff._main_trie == state_diff._main_trie
        assert trie_diff._storage_tries == state_diff._storage_tries

        # Compare main trie
        for address, (cairo_prev, cairo_new) in trie_diff._main_trie.items():
            python_prev, python_new = state_diff._main_trie.get(address)
            assert cairo_prev == python_prev and cairo_new == python_new

        # Cairo
        main_trie_diff_cairo, storage_trie_diff_cairo = cairo_run(
            "compute_diff_entrypoint",
            node_store=ethereum_trie_transition_db.nodes,
            address_preimages=ethereum_trie_transition_db.address_preimages,
            storage_key_preimages=ethereum_trie_transition_db.storage_key_preimages,
            left=ethereum_trie_transition_db.state_root,
            right=ethereum_trie_transition_db.post_state_root,
        )

        accounts_lookup: Dict[Address, Tuple[Optional[Account], Optional[Account]]] = {
            dict_entry.key: (dict_entry.prev_value, dict_entry.new_value)
            for dict_entry in main_trie_diff_cairo
        }

        assert len(accounts_lookup) == len(state_diff._main_trie)
        for key, (prev_value, new_value) in state_diff._main_trie.items():
            assert (prev_value, new_value) == accounts_lookup[key]

        storage_lookup: Dict[int, Tuple[Optional[U256], Optional[U256]]] = {
            int(dict_entry.key): (
                dict_entry.prev_value,
                dict_entry.new_value,
            )
            for dict_entry in storage_trie_diff_cairo
        }

        addresses = state_diff._storage_tries.keys()
        for address in addresses:
            keys_in_address = 0
            for key, (prev_value, new_value) in state_diff._storage_tries[
                address
            ].items():
                key = int_to_uint256(int.from_bytes(key, "little"))
                key_hashed = poseidon_hash_many(
                    (int.from_bytes(address, "little"), *key)
                )
                assert (prev_value, new_value) == storage_lookup[key_hashed]
                keys_in_address += 1
            assert keys_in_address == len(state_diff._storage_tries[address].keys())

    @pytest.mark.parametrize(
        "invalid_case",
        [
            "NonEmptyBytesValue",
            "LTTwoNonNullSubnodes",
            "EmptyKeySegment",
            "EmptySubnode",
            "EmptyValue",
            "InvalidFullPath",
            "InvalidParent",
        ],
    )
    @given(data=st.data())
    def test_invalid_trie_diff(
        self,
        cairo_run,
        empty_ethereum_tries,
        data,
        invalid_case,
    ):
        invalid_post_trie = data.draw(invalid_mpt_strategy(invalid_case=invalid_case))

        trie = EthereumTrieTransitionDB.from_pre_and_post_tries(
            empty_ethereum_tries, invalid_post_trie
        )
        with pytest.raises(Exception, match=re.escape(invalid_case)):
            cairo_run(
                "compute_diff_entrypoint",
                node_store=trie.nodes,
                address_preimages=trie.address_preimages,
                storage_key_preimages=trie.storage_key_preimages,
                left=trie.state_root,
                right=trie.post_state_root,
            )
        with pytest.raises(Exception, match=re.escape(invalid_case)):
            StateDiff.from_tries(trie)

    @pytest.mark.parametrize(
        "data_path", [Path("test_data/22081873.json")], scope="session"
    )
    @given(data=st.data())
    @pytest.mark.slow
    def test_node_store_get(self, cairo_run, node_store, data):
        # take 20 keys from the node_store
        small_store = {k: v for k, v in list(node_store.items())[:6]}
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
            try:
                _, result = cairo_run("node_store_get", small_store, key)
            except Exception as cairo_error:
                assert "Dict Error: No value found for key" in str(cairo_error)
                with pytest.raises(KeyError):
                    decode_node(small_store[key])
                continue
            assert result == decode_node(small_store[key])

    @given(address=..., account_before=..., account_after=...)
    def test__process_account_diff(
        self,
        cairo_run,
        address: Address,
        account_before: Optional[Account],
        account_after: Optional[Account],
    ):
        # Python
        path = keccak256(address)
        diff_cls = StateDiff()
        diff_cls._address_preimages = {path: address}
        leaf_before = (
            None
            if account_before is None or account_before == EMPTY_ACCOUNT
            else LeafNode(rest_of_key=b"", value=account_before.to_rlp())
        )
        leaf_after = (
            None
            if account_after is None or account_after == EMPTY_ACCOUNT
            else LeafNode(rest_of_key=b"", value=account_after.to_rlp())
        )
        diff_cls._process_account_diff(
            path=path,
            left=leaf_before,
            right=leaf_after,
        )

        node_store = {}

        result_diffs = cairo_run(
            "test__process_account_diff",
            node_store=node_store,
            address_preimages=diff_cls._address_preimages,
            storage_key_preimages=diff_cls._storage_key_preimages,
            path=path,
            left=leaf_before,
            right=leaf_after,
        )
        if not isinstance(result_diffs, list):
            result_diffs = [result_diffs]

        result_lookup = {
            diff_entry.key: (diff_entry.prev_value, diff_entry.new_value)
            for diff_entry in result_diffs
        }

        for key, (prev_value, new_value) in diff_cls._main_trie.items():
            assert (prev_value, new_value) == result_lookup[key]

    @given(address=..., data=st.data())
    def test__process_account_diff_raise_on_empty_account(
        self,
        cairo_run,
        address: Address,
        data: st.DataObject,
    ):
        # Setup
        is_before_empty = data.draw(st.booleans())
        if is_before_empty:
            account_before = EMPTY_ACCOUNT
            account_after = data.draw(st.builds(Account))
        else:
            account_before = data.draw(st.builds(Account))
            account_after = EMPTY_ACCOUNT
        assume(account_before != account_after)

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
        path = keccak256(address)

        # These are required for the call
        diff_cls = StateDiff()
        diff_cls._address_preimages = {path: address}
        node_store = {}

        with pytest.raises(
            Exception,
            match=re.compile(
                "InvariantLeftLeafEmptyAccount|InvariantRightLeafEmptyAccount"
            ),
        ):
            cairo_run(
                "test__process_account_diff",
                node_store=node_store,
                address_preimages=diff_cls._address_preimages,
                storage_key_preimages=diff_cls._storage_key_preimages,
                path=path,
                left=leaf_before,
                right=leaf_after,
            )

    @given(address=..., account_before=..., account_after=...)
    def test__process_account_diff_invalid(
        self,
        cairo_run,
        address: Address,
        account_before: Optional[Account],
        account_after: Optional[Account],
    ):
        path = keccak256(address)

        ## BREAKING THE INVARIANT:
        wrong_address = keccak256(b"invalid")[0:20]

        diff_cls = StateDiff()
        diff_cls._address_preimages = {path: wrong_address}
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

        node_store = {}

        with pytest.raises(
            Exception,
            match=re.escape(
                "INVARIANT - Invalid address preimage: keccak(address) != path"
            ),
        ):
            cairo_run(
                "test__process_account_diff",
                node_store=node_store,
                address_preimages=diff_cls._address_preimages,
                storage_key_preimages=diff_cls._storage_key_preimages,
                path=path,
                left=leaf_before,
                right=leaf_after,
            )

    @given(
        storage_key=..., address=..., storage_value_before=..., storage_value_after=...
    )
    def test__process_storage_diff(
        self,
        cairo_run,
        storage_key: Bytes32,
        address: Address,
        storage_value_before: Optional[U256],
        storage_value_after: Optional[U256],
    ):
        diff_cls = StateDiff()
        path = keccak256(storage_key)
        diff_cls._storage_key_preimages = {path: storage_key}
        leaf_before = (
            None
            if storage_value_before is None or int(storage_value_before) == 0
            else LeafNode(rest_of_key=b"", value=rlp.encode(storage_value_before))
        )
        leaf_after = (
            None
            if storage_value_after is None or int(storage_value_after) == 0
            else LeafNode(rest_of_key=b"", value=rlp.encode(storage_value_after))
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
            # todo: this should be serialize properly, without a "value"
            int(diff.key): (diff.prev_value, diff.new_value)
            for diff in result_diffs
        }

        # Cases where the prev == new, so no diffs are generated.
        if address not in diff_cls._storage_tries:
            assert address not in result_lookup
            return

        for key, (prev_value, new_value) in diff_cls._storage_tries[address].items():
            key = int_to_uint256(int.from_bytes(key, "little"))
            hashed_key = poseidon_hash_many((int.from_bytes(address, "little"), *key))
            assert (prev_value, new_value) == result_lookup[hashed_key]

    @given(storage_key=..., address=..., data=st.data())
    def test__process_storage_diff_raise_if_zero(
        self,
        cairo_run,
        storage_key: Bytes32,
        address: Address,
        data: st.DataObject,
    ):
        diff_cls = StateDiff()
        path = keccak256(storage_key)
        diff_cls._storage_key_preimages = {path: storage_key}

        is_before_zero = data.draw(st.booleans())
        if is_before_zero:
            storage_value_before = U256(0)
            storage_value_after = data.draw(
                st.integers(min_value=1, max_value=2**256 - 1)
            )
            storage_value_after = U256(storage_value_after)
        else:
            storage_value_before = data.draw(
                st.integers(min_value=1, max_value=2**256 - 1)
            )
            storage_value_before = U256(storage_value_before)
            storage_value_after = U256(0)

        leaf_before = LeafNode(rest_of_key=b"", value=rlp.encode(storage_value_before))
        leaf_after = LeafNode(rest_of_key=b"", value=rlp.encode(storage_value_after))

        with pytest.raises(
            Exception,
            match=re.compile("InvariantLeftNodeZero|InvariantRightNodeZero"),
        ):
            cairo_run(
                "test__process_storage_diff",
                storage_key_preimages=diff_cls._storage_key_preimages,
                path=path,
                address=address,
                left=leaf_before,
                right=leaf_after,
            )

    @given(
        storage_key=..., address=..., storage_value_before=..., storage_value_after=...
    )
    def test__process_storage_diff_invalid(
        self,
        cairo_run,
        storage_key: Bytes32,
        address: Address,
        storage_value_before: Optional[U256],
        storage_value_after: Optional[U256],
    ):
        diff_cls = StateDiff()
        path = keccak256(storage_key)

        fake_storage_key = keccak256(b"invalid")
        diff_cls._storage_key_preimages = {path: fake_storage_key}
        leaf_before = (
            None
            if storage_value_before is None
            else LeafNode(rest_of_key=b"", value=rlp.encode(storage_value_before))
        )
        leaf_after = (
            None
            if storage_value_after is None
            else LeafNode(rest_of_key=b"", value=rlp.encode(storage_value_after))
        )
        diff_cls._process_storage_diff(
            address=address,
            path=path,
            left=leaf_before,
            right=leaf_after,
        )

        with pytest.raises(
            Exception,
            match=re.escape(
                "INVARIANT - Invalid storage key preimage: keccak(storage_key) != path"
            ),
        ):
            cairo_run(
                "test__process_storage_diff",
                storage_key_preimages=diff_cls._storage_key_preimages,
                path=path,
                address=address,
                left=leaf_before,
                right=leaf_after,
            )

    @pytest.mark.parametrize(
        "data_path", [Path("test_data/22081873.json")], scope="session"
    )
    @given(data=st.data())
    def test_resolve(self, cairo_run, node_store: Mapping[Hash32, Bytes], data):
        # take 20 keys from the node_store
        small_store = {k: v for k, v in list(node_store.items())[:3]}
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
            try:
                _, cairo_result = cairo_run("resolve", small_store, node=bytes(key))
            except Exception as cairo_error:
                assert "Dict Error: No value found for key" in str(cairo_error)
                # We can't use strict_raises here because the error is a RuntimeError in Cairo
                with pytest.raises(KeyError):
                    resolve(key, small_store)
                continue
            result = resolve(key, small_store)
            assert result == cairo_result

            # check that resolving a node returns the same node
            _, node = cairo_run("resolve", small_store, result)
            assert node == resolve(result, small_store)

    @given(embedded_node_dict=embedded_node_strategy())
    @pytest.mark.slow
    def test_resolve_embedded_node(self, cairo_run, embedded_node_dict):
        # We don't need a node store for this test
        node_store = {}
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


class TestTypes:
    @given(left=..., right=...)
    def test_OptionalUnionInternalNodeExtended__eq__(
        self,
        cairo_run,
        left: Optional[Union[InternalNode, Extended]],
        right: Optional[Union[InternalNode, Extended]],
    ):
        eq_py = (left == right) and type(left) is type(right)
        eq_cairo = cairo_run("OptionalUnionInternalNodeExtended__eq__", left, right)
        assert eq_py == eq_cairo
