import json
import logging
import os
from collections import defaultdict
from dataclasses import dataclass
from typing import Any, Dict, List, Mapping, Optional

import requests
from ethereum.cancun.fork_types import EMPTY_ACCOUNT, Account, Address, encode_account
from ethereum.cancun.state import State
from ethereum.cancun.trie import (
    BranchNode,
    ExtensionNode,
    InternalNode,
    LeafNode,
    Trie,
    bytes_to_nibble_list,
    common_prefix_length,
    nibble_list_to_compact,
    trie_set,
)
from ethereum.crypto.hash import Hash32, keccak256
from ethereum.utils.hexadecimal import hex_to_bytes
from ethereum_rlp import rlp
from ethereum_types.bytes import Bytes, Bytes32
from ethereum_types.numeric import U256, Uint

from mpt.state_diff import StateDiff

logger = logging.getLogger("mpt")


class ExclusionProof(Exception):
    """Exception raised when a key is proven not to exist in the trie."""

    pass


@dataclass
class AccountNode:
    nonce: bytes
    balance: bytes
    storage_root: Bytes32
    code_hash: Bytes32

    def to_account(self, code: Optional[bytes] = None) -> Account:
        return Account(
            nonce=Uint(int.from_bytes(self.nonce, "big")),
            balance=U256(int.from_bytes(self.balance, "big")),
            code=code,
        )

    def rlp_encode(self) -> bytes:
        return rlp.encode(
            (
                self.nonce,
                self.balance,
                self.storage_root,
                self.code_hash,
            )
        )


EMPTY_TRIE_ROOT_HASH = Hash32(
    bytes.fromhex("56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")
)

EMPTY_CODE_HASH = Hash32(
    bytes.fromhex("c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
)

EMPTY_BYTES_RLP = b"\x80"


def nibble_path_to_hex(nibble_path: Bytes) -> str:
    if len(nibble_path) % 2 != 0:
        nibble_path = nibble_path + b"\x00"  # Pad with zero if odd
    result = bytes(
        [
            nibble_path[i] * 16 + nibble_path[i + 1]
            for i in range(0, len(nibble_path), 2)
        ]
    )
    return "0x" + result.hex()


class StateTries:
    """
    Represents the (partial) state of Ethereum for a given block.
    Includes all account MPT leaf nodes and storage MPT leaf nodes and all intermediary nodes touched in a block,
    related codes, an access list of addresses and storage keys that were accessed in the block, and a state root.
    """

    nodes: Mapping[Bytes32, Bytes]
    codes: Mapping[Bytes32, Bytes]
    access_list: Mapping[Address, Optional[List[Bytes32]]]
    state_root: Hash32

    @classmethod
    def create_empty(cls) -> "StateTries":
        return cls(
            nodes={},
            codes={},
            access_list={},
            state_root=EMPTY_TRIE_ROOT_HASH,
        )

    def __init__(
        self,
        nodes: Mapping[Bytes32, Bytes],
        codes: Mapping[Bytes32, Bytes],
        access_list: Mapping[Address, Optional[List[Bytes32]]],
        state_root: Hash32,
    ):
        self.nodes = nodes
        self.codes = codes
        self.access_list = access_list
        self.state_root = state_root
        logger.debug(f"Initialized MPT with state root: 0x{state_root.hex()}")
        logger.debug(f"Number of nodes: {len(nodes)}")
        logger.debug(f"Number of codes: {len(codes)}")
        logger.debug(f"Number of addresses in access list: {len(access_list)}")

    def to_state(self) -> State:
        """
        Convert the StateTries to a State object.

        Returns
        -------
        State
            A State object representing the Ethereum state
        """

        # Step 1: Recursively explore the state trie to get to the leaves
        _main_trie: Trie[Address, Optional[Account]] = Trie(
            secured=True, default=None, _data=defaultdict(lambda: None)
        )
        _storage_tries: Dict[Address, Trie[Bytes32, U256]] = dict()

        logger.debug("Starting to convert StateTries to State")
        for address in self.access_list.keys():

            account = self.get(keccak256(address))
            if account is None:
                logger.debug(
                    f"Account not found: {address} - Considering this an exclusion proof"
                )
                trie_set(_main_trie, address, EMPTY_ACCOUNT)
                continue

            rlp_account = AccountNode(*rlp.decode(account))

            if rlp_account.code_hash == EMPTY_CODE_HASH:
                code = b""
            else:
                code = self.codes.get(rlp_account.code_hash, None)
                # TODO: This is a hack to get the code for codes not present in the StateTries object
                # This is due to the fact that the Account class in EELS
                # doesn't match the account node structure: the class contains the full code and not only the code hash
                if code is None:
                    payload = {
                        "jsonrpc": "2.0",
                        "method": "eth_getCode",
                        "params": [
                            "0x" + address.hex(),
                            "latest",
                        ],
                        "id": 1,
                    }
                    response = requests.post(
                        os.environ["CHAIN_RPC_URL"], json=payload, timeout=30
                    )

                    if response.status_code != 200:
                        raise Exception(
                            f"Failed to fetch code: HTTP {response.status_code}"
                        )
                    logger.debug(
                        f"Code: {response.json().get('result')} for address: {address}"
                    )
                    code = bytes.fromhex(
                        response.json().get("result")[2:]
                        if response.json().get("result") is not None
                        and response.json().get("result").startswith("0x")
                        else ""
                    )

            trie_set(
                _main_trie,
                address,
                rlp_account.to_account(code),
            )

            # Process storage for this account if it has storage keys in the access list
            storage_root = rlp_account.storage_root
            if not storage_root:
                raise ValueError(f"Storage root is None for address: {address}")

            if address in self.access_list and storage_root != EMPTY_TRIE_ROOT_HASH:
                for key in self.access_list[address]:
                    value = self.get(keccak256(key), Hash32(storage_root))
                    if value is None:
                        logger.debug(
                            f"Exclusion proof found for key: 0x{key.hex()} for address: 0x{address.hex()}"
                        )
                        continue
                    if address not in _storage_tries:
                        _storage_tries[address] = Trie(secured=True, default=U256(0))
                    trie_set(
                        _storage_tries[address],
                        key,
                        U256(int.from_bytes(rlp.decode(value), "big")),
                    )

        logger.debug("Finished converting StateTries to State")
        return State(
            _main_trie=_main_trie,
            _storage_tries=_storage_tries,
        )

    @classmethod
    def from_json(cls, path: str) -> "StateTries":
        logger.debug(f"Loading MPT from JSON file: {path}")
        with open(path, "r") as f:
            data = json.load(f)

        nodes = {
            keccak256(hex_to_bytes(node)): (hex_to_bytes(node))
            for node in data["witness"]["state"]
        }

        codes = {
            keccak256(hex_to_bytes(code)): hex_to_bytes(code)
            for code in data["witness"]["codes"]
        }

        # Process the access list from the JSON data
        access_list = {
            Address(hex_to_bytes(item["address"])): (
                [Bytes32(hex_to_bytes(key)) for key in item["storageKeys"]]
                if item["storageKeys"] is not None
                else None
            )
            for item in data.get("accessList", [])
        }

        state_root = Hash32(hex_to_bytes(data["witness"]["ancestors"][0]["stateRoot"]))

        return cls(
            nodes=nodes,
            codes=codes,
            access_list=access_list,
            state_root=state_root,
        )

    @classmethod
    def from_data(cls, data: Dict[str, Any]) -> "StateTries":
        """
        Create a StateTries object from a dictionary of data. We expect the data to be the same as `from_json` method.

        Parameters
        ----------
        data : Dict[str, Any]
            The data to create the StateTries object from
        """
        nodes = {
            keccak256(hex_to_bytes(node)): (hex_to_bytes(node))
            for node in data["witness"]["state"]
        }

        codes = {
            keccak256(hex_to_bytes(code)): hex_to_bytes(code)
            for code in data["witness"]["codes"]
        }

        # Process the access list from the JSON data
        access_list = {
            Address(hex_to_bytes(item["address"])): (
                [Bytes32(hex_to_bytes(key)) for key in item["storageKeys"]]
                if item["storageKeys"] is not None
                else None
            )
            for item in data.get("accessList", [])
        }

        state_root = Hash32(hex_to_bytes(data["witness"]["ancestors"][0]["stateRoot"]))

        return cls(
            nodes=nodes,
            codes=codes,
            access_list=access_list,
            state_root=state_root,
        )

    def get(self, path: Bytes, root_hash: Optional[Hash32] = None) -> Optional[Bytes]:
        """
        Get a value from the trie at the given path.

        Parameters
        ----------
        path : Bytes
            The path to look up
        root_hash : Hash32, optional
            The root hash to start from, defaults to the trie's state_root

        Returns
        -------
        Optional[Bytes]
            The value at the path, or None if not found
        """
        is_state_access = False
        if root_hash is None:
            root_hash = self.state_root
            # Debug flag to indicate that this is a state access
            is_state_access = True

        logger.debug(
            f"Getting value in {'state' if is_state_access else 'storage'} for path: {'0x' + path.hex() if path else 'None'}"
        )

        # Check if the root hash exists in our nodes
        if root_hash not in self.nodes and root_hash != EMPTY_TRIE_ROOT_HASH:
            raise KeyError(f"Root hash not found in nodes: 0x{root_hash.hex()}")

        # Start traversal from the root
        nibble_path = bytes_to_nibble_list(path)
        try:
            return self.resolve_node(root_hash, nibble_path)
        except ExclusionProof as e:
            logger.debug(
                f"Exclusion proof found for path: {'0x' + path.hex() if path else 'None'} - {str(e)}"
            )
            return None
        except Exception as e:
            logger.error(
                f"Error in {'state' if is_state_access else 'storage'} get: {str(e)}"
            )

    def get_storage_root(self, address: Address) -> Optional[Hash32]:
        """
        Get the storage root for an account.
        """
        account = self.get(keccak256(address))
        if account is None:
            logger.debug(
                "get_storage_root: Account not found - Return EMPTY_TRIE_ROOT_HASH"
            )
            return EMPTY_TRIE_ROOT_HASH

        rlp_account = AccountNode(*rlp.decode(account))
        return Hash32(rlp_account.storage_root)

    def resolve_node(self, node_hash: Hash32, nibble_path: Bytes) -> Optional[Bytes]:
        """
        Recursive helper for get method.

        Parameters
        ----------
        node_hash : Hash32
            The hash of the current node
        nibble_path : Bytes
            The remaining path to traverse (in nibbles)

        Returns
        -------
        Optional[Bytes]
            The value at the path, or None if not found
        """
        logger.debug(
            f"Getting node with hash: 0x{node_hash.hex()} - remaining path: {nibble_path_to_hex(nibble_path)}"
        )

        if node_hash == EMPTY_TRIE_ROOT_HASH:
            return None

        node_data = self.nodes.get(node_hash)

        if node_data is None:
            raise KeyError(
                f"Node not found: 0x{node_hash.hex()} - Missing Node at {nibble_path_to_hex(nibble_path)}"
            )

        node = decode_node(node_data)
        return self.resolve_node_path(node, nibble_path)

    def resolve_node_path(
        self, node: InternalNode, nibble_path: Bytes
    ) -> Optional[Bytes]:
        """
        Process a node based on its type and traverse the trie.

        Parameters
        ----------
        node : InternalNode
            The node to process (BranchNode, ExtensionNode, or LeafNode)
        nibble_path : Bytes
            The remaining path to traverse (in nibbles)

        Returns
        -------
        Optional[Bytes]
            The value at the path, or None if not found
        """
        # Process based on node type
        if isinstance(node, BranchNode):
            logger.debug("Processing branch node")
            if not nibble_path:
                raise ValueError("Invariant: trying to access node value")

            next_nibble = nibble_path[0]
            logger.debug(f"Next nibble: {next_nibble}")

            if next_nibble >= 16:
                raise ValueError(f"Invalid nibble value: {next_nibble}")

            next_node = node.subnodes[next_nibble]

            if not next_node:
                raise ExclusionProof(f"No subnode at index {next_nibble}")

            # If the next node is a hash reference (bytes), follow it
            if isinstance(next_node, bytes) and len(next_node) == 32:
                logger.debug(f"Following hash reference: 0x{next_node.hex()}")
                return self.resolve_node(Hash32(next_node), nibble_path[1:])
            elif isinstance(next_node, bytes) and len(next_node) < 32:
                logger.debug("Next node is embedded")
                decoded = decode_node(next_node)
                return self.resolve_node_path(decoded, nibble_path[1:])

            else:
                raise ValueError(f"Unknown node type: {type(next_node)}")

        elif isinstance(node, ExtensionNode):
            logger.debug(
                f"Processing extension node with key segment: {node.key_segment}"
            )

            # If the path doesn't match the key segment, the path doesn't exist
            if len(nibble_path) < len(node.key_segment):
                raise KeyError(
                    f"Path too short for extension key segment {node.key_segment}"
                )

            # Check if the key segment matches the beginning of the path
            for i in range(len(node.key_segment)):
                if nibble_path[i] != node.key_segment[i]:
                    # If the key segment is not a prefix of the path, then the path doesn't exist
                    # If it existed, this extension node would have been a branch node, hence
                    # we can raise an exclusion proof
                    raise ExclusionProof(
                        f"Path mismatch at index {i}: {nibble_path[i]} != {node.key_segment[i]}"
                    )

            remaining_path = nibble_path[len(node.key_segment) :]
            logger.debug(f"Remaining path after extension: {remaining_path}")

            # If the subnode is a hash reference, follow it
            if isinstance(node.subnode, bytes) and len(node.subnode) == 32:
                logger.debug(f"Following hash reference: 0x{node.subnode.hex()}")
                return self.resolve_node(Hash32(node.subnode), remaining_path)
            elif isinstance(node.subnode, bytes) and len(node.subnode) < 32:
                logger.debug("Processing nested embedded node")
                decoded = decode_node(node.subnode)
                return self.resolve_node_path(decoded, remaining_path)
            else:
                raise ValueError(f"Unknown node type: {type(node.subnode)}")

        elif isinstance(node, LeafNode):
            logger.debug("Processing leaf node")

            # If the path matches exactly, return the value
            if nibble_path == node.rest_of_key:
                logger.debug("Path matches leaf key, returning value")
                return node.value

            raise ExclusionProof(
                f"Path does not match leaf key: {nibble_path_to_hex(nibble_path)} != {nibble_path_to_hex(node.rest_of_key)}"
            )

        raise ValueError(f"Unknown node type: {type(node)}")

    def delete(
        self, path: Bytes, root_hash: Optional[Hash32] = None
    ) -> Optional[Hash32]:
        """
        Delete a value from the trie at the given path.

        The deletion process in a Merkle Patricia Trie follows these steps:

        1. Navigate to the target node using the path:
            - At each branch node, follow the appropriate nibble
            - At each extension node, verify the shared prefix matches
            - Continue until reaching a leaf node

        2. When the target node is found:
            - If it's a leaf node and the path matches exactly, remove it
            - If it's not found, return without changes

        3. After deletion, restructure the trie to maintain invariants:
            - If a branch node is left with only one child, convert it to an extension node
            - If an extension node's child is deleted, remove the extension node
            - Merge extension nodes with their child extension nodes when possible
            - Update all affected node hashes up to the root

        Parameters
        ----------
        path : Bytes
            The path to delete
        root_hash : Hash32, optional
            The root hash to start from, defaults to the trie's state_root

        Returns
        -------
        Optional[Hash32]
            The new root hash after deletion, or None if the path wasn't found.
            Returns the original root_hash if no changes were made.
        """
        if root_hash is None:
            root_hash = self.state_root

        logger.debug(
            f"Deleting value for path: {'0x' + path.hex() if path else 'None'} - starting from root hash: 0x{root_hash.hex()}"
        )

        # Check if the root hash exists in our nodes
        if root_hash not in self.nodes or root_hash == EMPTY_TRIE_ROOT_HASH:
            logger.error(f"Root hash not found in nodes: {root_hash.hex()}")
            return None

        # Start deletion from the root
        nibble_path = bytes_to_nibble_list(path)
        try:
            new_root_node, deleted = self.delete_node_hash(root_hash, nibble_path)
            if not deleted:
                logger.debug("Path not found, nothing deleted")
                return root_hash

            if new_root_node is None:
                logger.debug("Trie is now empty")
                return EMPTY_TRIE_ROOT_HASH

            # Encode and hash the new root node
            encoded_node = encode_internal_node(new_root_node)
            new_root_hash = keccak256(encoded_node)

            # Update the nodes mapping with the new root
            self.nodes[new_root_hash] = encoded_node

            # Update the state root if we were deleting from it
            if root_hash == self.state_root:
                self.state_root = new_root_hash

            logger.debug(
                f"Deleted value for path: {'0x' + path.hex() if path else 'None'} - new root hash: 0x{new_root_hash.hex()}"
            )
            return new_root_hash
        except Exception as e:
            logger.error(f"Error in delete: {str(e)}")
            return None

    def delete_account(self, address: Address):
        path = keccak256(address)
        self.delete(path)

    def delete_storage_key(self, address: Address, key: Bytes32):
        """
        Delete a storage key for an account.

        Parameters
        ----------
        address : Address
            The address of the account
        key : Bytes32
            The key to delete
        """
        account = self.get(keccak256(address))
        if account is None:
            logger.debug("Account not found, nothing to delete")
            return
        rlp_account = AccountNode(*rlp.decode(account))
        storage_root = rlp_account.storage_root

        # Delete the storage key
        path = keccak256(key)
        new_root_hash = self.delete(path, storage_root)
        if new_root_hash is None:
            logger.debug("Failed to delete storage key, nothing to update")
            return
        else:
            rlp_account.storage_root = new_root_hash
            encoded = rlp_account.rlp_encode()
            self.upsert(keccak256(address), encoded)
            return

    def delete_node_hash(
        self, node_hash: Hash32, nibble_path: Bytes
    ) -> tuple[Optional[Bytes], bool]:
        """
        Recursive helper for delete method.

        Parameters
        ----------
        node_hash : Hash32
            The hash of the current node
        nibble_path : Bytes
            The remaining path to traverse (in nibbles)

        Returns
        -------
        tuple[Optional[Bytes], bool]
            The new node (or None if deleted) and a boolean indicating if deletion occurred
        """
        logger.debug(
            f"Deleting from node with hash: 0x{node_hash.hex()} - remaining path: {nibble_path_to_hex(nibble_path)}"
        )

        node_data = self.nodes.get(node_hash)
        if node_data is None:
            raise KeyError(f"Node not found: 0x{node_hash.hex()}")

        # Process the node
        new_node, deleted = self.delete_node(decode_node(node_data), nibble_path)

        return new_node, deleted

    def delete_node(
        self, node: InternalNode, nibble_path: Bytes
    ) -> tuple[Optional[InternalNode], bool]:
        """
        Process a node for deletion based on its type.

        Parameters
        ----------
        node : InternalNode
            The node to process (BranchNode, ExtensionNode, or LeafNode)
        nibble_path : Bytes
            The remaining path to traverse (in nibbles)

        Returns
        -------
        tuple[Optional[InternalNode], bool]
            The new node (or None if deleted) and a boolean indicating if deletion occurred
        """
        # Process based on node type
        if isinstance(node, BranchNode):
            logger.debug("Processing branch node for deletion")

            if not nibble_path:
                if node.value:
                    raise ValueError(
                        "Invariant: trying to delete a branch node with a value - branch nodes are not supposed to have values"
                    )
                return node, False

            # Otherwise, follow the path
            next_nibble = nibble_path[0]
            if next_nibble >= 16:
                raise ValueError(f"Invalid nibble value: {next_nibble}")

            next_node = node.subnodes[next_nibble]
            if not next_node:
                logger.debug("Subnode not found, nothing to delete")
                return node, False

            # Recursively delete from the child
            # case 1: next_node is a hash reference
            if isinstance(next_node, bytes) and len(next_node) == 32:
                new_child, deleted = self.delete_node_hash(
                    Hash32(next_node), nibble_path[1:]
                )
            # case 2: next_node is an embedded node
            elif isinstance(next_node, bytes) and len(next_node) < 32:
                child_node = decode_node(next_node)
                new_child, deleted = self.delete_node(child_node, nibble_path[1:])
            else:
                raise ValueError(f"Unknown subnode type: {type(next_node)}")

            if not deleted:
                return node, False

            # Update the branch with the new child
            new_subnodes = list(node.subnodes)
            if not new_child:
                new_subnodes[next_nibble] = b""
            else:
                encoded_child = encode_internal_node(new_child)
                if len(encoded_child) >= 32:
                    child_hash = keccak256(encoded_child)
                    self.nodes[child_hash] = encoded_child
                    new_subnodes[next_nibble] = child_hash
                else:
                    new_subnodes[next_nibble] = encoded_child

            # Check if the branch now has only one child and no value
            non_empty_subnodes = [
                i for i, subnode in enumerate(new_subnodes) if subnode
            ]
            if len(non_empty_subnodes) == 1 and not node.value:
                # Convert to extension or leaf node
                index = non_empty_subnodes[0]
                child = new_subnodes[index]

                # If child is a hash reference, resolve it
                if isinstance(child, bytes) and len(child) == 32:
                    child_data = self.nodes.get(Hash32(child))
                    if child_data is None:
                        # SPECIAL CASE: If we are not able to resolve the child node,
                        # then it SHOULD be that the child node is a branch node
                        # source: <https://github.com/kkrt-labs/zk-pig/blob/main/docs/modified-mpt.md>
                        logger.debug(
                            "Special case: child node not found, returning one-nibble extension node"
                        )
                        return (
                            ExtensionNode(
                                key_segment=bytes([index]), subnode=Hash32(child)
                            ),
                            True,
                        )
                    child_node = decode_node(child_data)
                else:
                    child_node = decode_node(child)

                # Create a new path segment with the branch index
                new_segment = bytes([index])

                if isinstance(child_node, LeafNode):
                    # Combine paths and create a new leaf
                    combined_path = new_segment + child_node.rest_of_key
                    return (
                        LeafNode(rest_of_key=combined_path, value=child_node.value),
                        True,
                    )
                elif isinstance(child_node, ExtensionNode):
                    # Combine paths and create a new extension
                    combined_path = new_segment + child_node.key_segment
                    return (
                        ExtensionNode(
                            key_segment=combined_path, subnode=child_node.subnode
                        ),
                        True,
                    )
                else:
                    # Create an extension to the branch
                    return ExtensionNode(key_segment=new_segment, subnode=child), True

            return BranchNode(subnodes=tuple(new_subnodes), value=node.value), True

        elif isinstance(node, ExtensionNode):
            logger.debug("Processing extension node for deletion")

            # Check if the path matches the key segment
            if len(nibble_path) < len(node.key_segment):
                logger.error("Path too short, nothing to delete")
                return node, False

            for i in range(len(node.key_segment)):
                if nibble_path[i] != node.key_segment[i]:
                    logger.error("Path mismatch, nothing to delete")
                    return node, False

            remaining_path = nibble_path[len(node.key_segment) :]

            # Recursively delete from the child
            if isinstance(node.subnode, bytes) and len(node.subnode) == 32:
                new_child, deleted = self.delete_node_hash(
                    Hash32(node.subnode), remaining_path
                )
            elif isinstance(node.subnode, bytes) and len(node.subnode) < 32:
                child_node = decode_node(node.subnode)
                new_child, deleted = self.delete_node(child_node, remaining_path)
            else:
                raise ValueError(f"Unknown subnode type: {type(node.subnode)}")

            if not deleted:
                return node, False

            if new_child is None:
                return None, True

            # If the child is a leaf or extension, merge the paths
            if isinstance(new_child, LeafNode):
                combined_path = node.key_segment + new_child.rest_of_key
                # INVARIANT: The combined path should be the same as the remaining path
                assert (
                    combined_path == nibble_path
                ), f"Invariant broken - Combined path: {nibble_path_to_hex(combined_path)} != {nibble_path_to_hex(nibble_path)}"
                return LeafNode(rest_of_key=combined_path, value=new_child.value), True
            elif isinstance(new_child, ExtensionNode):
                combined_path = node.key_segment + new_child.key_segment
                # INVARIANT: The combined path should be the same as the remaining path
                assert (
                    combined_path == nibble_path
                ), f"Invariant broken - Combined path: {nibble_path_to_hex(combined_path)} != {nibble_path_to_hex(nibble_path)}"
                return (
                    ExtensionNode(key_segment=combined_path, subnode=new_child.subnode),
                    True,
                )

            encoded_child = encode_internal_node(new_child)
            if len(encoded_child) >= 32:
                child_hash = keccak256(encoded_child)
                self.nodes[child_hash] = encoded_child
                new_child = child_hash
            else:
                new_child = encoded_child

            return (
                ExtensionNode(key_segment=node.key_segment, subnode=new_child),
                True,
            )

        elif isinstance(node, LeafNode):
            logger.debug("Processing leaf node for deletion")

            # Check if the path matches exactly
            if nibble_path == node.rest_of_key:
                logger.debug("Path matches leaf key, deleting leaf")
                return None, True

            raise ValueError(
                f"Delete - Path does not match leaf key: {nibble_path_to_hex(nibble_path)} != {nibble_path_to_hex(node.rest_of_key)}"
            )

        raise ValueError(f"Unknown node type: {type(node)}")

    def upsert(
        self, path: Bytes, value: Bytes, root_hash: Optional[Hash32] = None
    ) -> Hash32:
        """
        Update or insert a value in the trie at the given path.

        The upsert process in a Merkle Patricia Trie follows these steps:

        1. Special case - Empty trie:
        - If the trie is empty (root_hash == EMPTY_TRIE_ROOT_HASH)
        - Create a new leaf node with the entire path and value
        - No need for complex path splitting or node creation

        2. Path traversal and node creation:
        a) At a Branch node:
            - If path is empty: (not supported in this implementation)
            - Otherwise: Follow the next nibble
            - If that branch is empty: Create new leaf node
            - If branch exists: Recursively upsert into that branch

        b) At an Extension node:
            - Find common prefix between path and node's key_segment
            - If paths diverge: Create a branch node at divergence point
            - If extension is prefix of path: Recursively upsert remaining path
            - Handle path compression by merging extension nodes when possible

        c) At a Leaf node:
            - If paths match exactly: Update value
            - If paths differ: Create branch node at first different nibble
            - Add both paths (existing and new) to the branch
            - Create extension node if common prefix exists

        3. Node encoding and storage:
        - Encode modified nodes using RLP
        - For nodes ≥ 32 bytes: Store separately and use hash as reference
        - For nodes < 32 bytes: Store directly in parent node
        - Update node hashes up to root

        Parameters
        ----------
        path : Bytes
            The path where the value should be stored
        value : Bytes
            The RLP-encoded value to store
        root_hash : Hash32, optional
            The root hash to start from, defaults to the trie's state_root

        Returns
        -------
        Hash32
            The new root hash after insertion/update
        """
        if root_hash is None:
            root_hash = self.state_root

        if path is None or len(path) != 32:
            raise ValueError(f"Invalid path: {path}")

        logger.debug(
            f"Upsert value at path: {'0x' + path.hex()} - root hash: 0x{root_hash.hex()}"
        )

        nibble_path = bytes_to_nibble_list(path)

        # If the root hash is the empty trie root hash,
        # we are instantiating a new trie
        if root_hash == EMPTY_TRIE_ROOT_HASH:
            logger.debug(f"Inserting 0x{path.hex()} into empty trie")
            node = LeafNode(rest_of_key=nibble_path, value=value)
            encoded_node = encode_internal_node(node)
            new_root_hash = keccak256(encoded_node)
            self.nodes[new_root_hash] = encoded_node
            if root_hash == self.state_root:
                self.state_root = new_root_hash
            return new_root_hash

        if root_hash not in self.nodes:
            raise ValueError(f"Root hash not found: {root_hash.hex()}")

        try:
            new_root_node, _ = self._upsert_node(root_hash, nibble_path, value)
        except Exception as e:
            logger.error(f"Error during upsert node: {e}")
            raise e

        # Encode and hash the new root node
        encoded_node = encode_internal_node(new_root_node)
        new_root_hash = keccak256(encoded_node)

        # Update the nodes mapping with the new root
        self.nodes[new_root_hash] = encoded_node

        if root_hash == self.state_root:
            self.state_root = new_root_hash

        return new_root_hash

    def upsert_storage_key(self, address: Address, key: Bytes32, value: Bytes):
        """
        Upsert a storage key for an account.

        Parameters
        ----------
        address : Address
            The address of the account
        key : Bytes32
            The key to upsert
        value : Bytes
            The value to upsert (RLP-encoded)
        """
        account = self.get(keccak256(address))
        if account is None:
            logger.error(
                f"Account not found: {address.hex()} - Failed to upsert storage key"
            )
            return

        rlp_account = AccountNode(*rlp.decode(account))

        storage_root = Hash32(rlp_account.storage_root)
        path = keccak256(key)

        if storage_root is None:
            raise ValueError("Invariant: storage root must not be None")

        new_root_hash = self.upsert(path, value, storage_root)
        if new_root_hash is None:
            raise ValueError("Invariant: new root hash must not be None")

        if new_root_hash == storage_root:
            logger.debug("Nothing to update, storage root is the same")
            return
        logger.debug(
            f"Updating storage root for account: 0x{address.hex()} - new root hash: 0x{new_root_hash.hex()}"
        )
        rlp_account.storage_root = new_root_hash
        encoded = rlp_account.rlp_encode()
        self.upsert(keccak256(address), encoded)
        return

    def upsert_account(self, address: Address, value: Bytes, code: Bytes) -> None:
        """
        Upsert an account.

        Parameters
        ----------
        address : Address
            The address of the account
        value : Bytes
            The value to upsert (RLP-encoded [nonce, balance, storage_root, code_hash])
        code : Bytes
            The code to insert in the code store mapping CodeHash -> Code
        """
        self.codes[keccak256(code)] = code
        path = keccak256(address)
        self.upsert(path, value)

    def _upsert_node(
        self, node_hash: Hash32, nibble_path: Bytes, value: Bytes
    ) -> tuple[InternalNode, bool]:
        """
        Recursive helper for upsert method.

        Parameters
        ----------
        node_hash : Hash32
            The hash of the current node
        nibble_path : Bytes
            The remaining path to traverse (in nibbles)
        value : Bytes
            The RLP-encoded value to store

        Returns
        -------
        tuple[InternalNode, bool]
            The new node and a boolean indicating if the node was modified
        """
        logger.debug(
            f"Upsert into node with hash: 0x{node_hash.hex()} - remaining path: {nibble_path_to_hex(nibble_path)}"
        )

        node_data = self.nodes.get(node_hash)
        if node_data is None:
            raise ValueError(f"Node not found: 0x{node_hash.hex()}")

        # Decode the node
        node = decode_node(node_data)

        # Process the node
        return self._process_upsert(node, nibble_path, value)

    def _process_upsert(
        self, node: InternalNode, nibble_path: Bytes, value: Bytes
    ) -> tuple[InternalNode, bool]:
        """
        Process a node for upsert based on its type.

        Parameters
        ----------
        node : InternalNode
            The node to process (BranchNode, ExtensionNode, or LeafNode)
        nibble_path : Bytes
            The remaining path to traverse (in nibbles)
        value : Bytes
            The RLP-encoded value to store

        Returns
        -------
        tuple[InternalNode, bool]
            The new node and a boolean indicating if the node was modified
        """
        # Process based on node type
        if isinstance(node, BranchNode):
            logger.debug("Processing branch node for upsert")

            # If we've reached the end of the path, update the value
            if not nibble_path:
                # TODO: Handle branch node with value
                raise ValueError(
                    "Invariant: cannot insert or update a branch node value"
                )

            # Otherwise, follow the path
            next_nibble = nibble_path[0]
            if next_nibble >= 16:
                raise ValueError(f"Invalid nibble value: {next_nibble}")

            next_node = node.subnodes[next_nibble]

            # If the next node is empty, we are in insert case, create a new leaf
            if not next_node:
                logger.debug(
                    f"Subnode at index {next_nibble} is empty, inserting new leaf node"
                )
                leaf_node = LeafNode(rest_of_key=nibble_path[1:], value=value)

                # Update the branch with the new leaf
                new_subnodes = list(node.subnodes)
                encoded_subnode = encode_internal_node(leaf_node)
                if len(encoded_subnode) >= 32:
                    node_hash = keccak256(encoded_subnode)
                    self.nodes[node_hash] = encoded_subnode
                    new_subnodes[next_nibble] = node_hash
                else:
                    new_subnodes[next_nibble] = encoded_subnode
                return BranchNode(subnodes=tuple(new_subnodes), value=node.value), True

            # Recursively upsert into the child
            if isinstance(next_node, bytes) and len(next_node) == 32:
                logger.debug(
                    f"Subnode at index {next_nibble} is a hash reference, upsert into child"
                )
                new_child, modified = self._upsert_node(
                    Hash32(next_node), nibble_path[1:], value
                )
                if not modified:
                    return node, False

                new_subnodes = list(node.subnodes)
                encoded_child = encode_internal_node(new_child)
                if len(encoded_child) >= 32:
                    node_hash = keccak256(encoded_child)
                    self.nodes[node_hash] = encoded_child
                    new_subnodes[next_nibble] = node_hash
                else:
                    new_subnodes[next_nibble] = encoded_child
                return BranchNode(subnodes=tuple(new_subnodes), value=node.value), True
            elif isinstance(next_node, bytes) and len(next_node) < 32:
                logger.debug(
                    f"Subnode at index {next_nibble} is an embedded node, upsert into child"
                )
                child_node = decode_node(next_node)
                new_child, modified = self._process_upsert(
                    child_node, nibble_path[1:], value
                )
                if not modified:
                    return node, False

                # Update the branch with the new child
                new_subnodes = list(node.subnodes)
                encoded_child = encode_internal_node(new_child)
                if len(encoded_child) >= 32:
                    node_hash = keccak256(encoded_child)
                    self.nodes[node_hash] = encoded_child
                    new_subnodes[next_nibble] = node_hash
                else:
                    new_subnodes[next_nibble] = encoded_child
                return BranchNode(subnodes=tuple(new_subnodes), value=node.value), True
            else:
                raise ValueError(f"Unknown next node type: {type(next_node)}")

        elif isinstance(node, ExtensionNode):
            logger.debug("Processing extension node for upsert")

            key_segment = node.key_segment

            # Find the common prefix length
            common_prefix_len = common_prefix_length(key_segment, nibble_path)
            logger.debug(
                f"Common prefix length: {common_prefix_len} for key_segment: {key_segment.hex()} and nibble_path: {nibble_path.hex()}"
            )

            # If the paths diverge
            if common_prefix_len < len(key_segment):
                # Create a branch node at the divergence point
                logger.debug(
                    f"Creating branch node at divergence point {common_prefix_len} for key_segment: {key_segment.hex()} and nibble_path: {nibble_path.hex()}"
                )
                branch_subnodes = [b"" for _ in range(16)]

                # Add the existing extension's suffix as one branch
                if common_prefix_len + 1 < len(key_segment):
                    logger.debug(
                        f"Adding existing extension's suffix as one branch for key_segment {key_segment[common_prefix_len + 1 :].hex()}"
                    )
                    # Create a new extension node with the remaining segment
                    new_ext = ExtensionNode(
                        key_segment=key_segment[common_prefix_len + 1 :],
                        subnode=node.subnode,
                    )
                    encoded_ext = encode_internal_node(new_ext)
                    if len(encoded_ext) >= 32:
                        ext_hash = keccak256(encoded_ext)
                        self.nodes[ext_hash] = encoded_ext
                        branch_subnodes[key_segment[common_prefix_len]] = ext_hash
                    else:
                        branch_subnodes[key_segment[common_prefix_len]] = encoded_ext
                else:
                    # The extension ends at the branch, add its subnode directly
                    # INVARIANT: The extension must end at the branch
                    assert common_prefix_len + 1 == len(key_segment)
                    branch_subnodes[key_segment[common_prefix_len]] = node.subnode

                # Add the new path as another branch
                if common_prefix_len + 1 < len(nibble_path):
                    # INVARIANT: nibble_path[common_prefix_len] and key_segment[common_prefix_len] are different
                    assert (
                        nibble_path[common_prefix_len] != key_segment[common_prefix_len]
                    ), "Invariant broken: nibble_path[common_prefix_len] and key_segment[common_prefix_len] is defined as the first nibble where paths diverge."
                    # Create a new leaf node with the remaining path
                    leaf_node = LeafNode(
                        rest_of_key=nibble_path[common_prefix_len + 1 :], value=value
                    )
                    encoded_leaf = encode_internal_node(leaf_node)
                    if len(encoded_leaf) >= 32:
                        leaf_hash = keccak256(encoded_leaf)
                        self.nodes[leaf_hash] = encoded_leaf
                        branch_subnodes[nibble_path[common_prefix_len]] = leaf_hash
                    else:
                        branch_subnodes[nibble_path[common_prefix_len]] = encoded_leaf
                else:
                    # The path ends at the branch, add the value
                    raise ValueError(
                        "Invariant: cannot insert or update a branch node value"
                    )

                logger.debug(f"New Branch Node: {branch_subnodes}")
                branch_node = BranchNode(subnodes=tuple(branch_subnodes), value=b"")

                # If there's a common prefix, create a new extension node
                if common_prefix_len > 0:
                    encoded_branch = encode_internal_node(branch_node)
                    if len(encoded_branch) >= 32:
                        branch_hash = keccak256(encoded_branch)
                        self.nodes[branch_hash] = encoded_branch
                        return (
                            ExtensionNode(
                                key_segment=key_segment[:common_prefix_len],
                                subnode=branch_hash,
                            ),
                            True,
                        )
                    else:
                        return (
                            ExtensionNode(
                                key_segment=key_segment[:common_prefix_len],
                                subnode=encoded_branch,
                            ),
                            True,
                        )
                else:
                    return branch_node, True

            # If the extension's key is a prefix of the path
            if common_prefix_len == len(key_segment):
                # Continue with the remaining path
                remaining_path = nibble_path[common_prefix_len:]

                # Recursively upsert into the child
                if isinstance(node.subnode, bytes) and len(node.subnode) == 32:
                    new_child, modified = self._upsert_node(
                        Hash32(node.subnode), remaining_path, value
                    )
                    if not modified:
                        return node, False

                    encoded_child = encode_internal_node(new_child)
                    if len(encoded_child) >= 32:
                        child_hash = keccak256(encoded_child)
                        self.nodes[child_hash] = encoded_child
                        return (
                            ExtensionNode(key_segment=key_segment, subnode=child_hash),
                            True,
                        )
                    else:
                        return (
                            ExtensionNode(
                                key_segment=key_segment, subnode=encoded_child
                            ),
                            True,
                        )
                elif isinstance(node.subnode, bytes) and len(node.subnode) < 32:
                    # Process embedded node
                    child_node = decode_node(node.subnode)
                    new_child, modified = self._process_upsert(
                        child_node, remaining_path, value
                    )
                    if not modified:
                        return node, False

                    encoded_child = encode_internal_node(new_child)
                    if len(encoded_child) >= 32:
                        child_hash = keccak256(encoded_child)
                        self.nodes[child_hash] = encoded_child
                        return (
                            ExtensionNode(key_segment=key_segment, subnode=child_hash),
                            True,
                        )
                    else:
                        return (
                            ExtensionNode(
                                key_segment=key_segment, subnode=encoded_child
                            ),
                            True,
                        )
                else:
                    raise ValueError(
                        f"Unexpected case in extension node processing - key_segment: {key_segment.hex()} - nibble_path: {nibble_path.hex()}"
                    )

            # Invariant: this case shouldn't happen if the trie is well-formed
            raise ValueError(
                f"Unexpected case in extension node processing - key_segment: {key_segment.hex()} - nibble_path: {nibble_path.hex()}"
            )

        elif isinstance(node, LeafNode):
            logger.debug("Processing leaf node")

            if nibble_path == node.rest_of_key:
                if node.value == value:
                    return node, False

                logger.debug(f"Leaf node value changed: {node.value} -> {value}")
                return LeafNode(rest_of_key=node.rest_of_key, value=value), True

            # Paths diverge, need to create a branch
            # Find the common prefix length
            common_prefix_len = common_prefix_length(node.rest_of_key, nibble_path)

            logger.debug(
                f"Common prefix length: {common_prefix_len} for path {nibble_path.hex()} and {node.rest_of_key.hex()}"
            )

            # Create a branch node at the divergence point
            branch_node = BranchNode(subnodes=tuple(b"" for _ in range(16)), value=b"")

            # Add the existing leaf as one branch
            if common_prefix_len + 1 < len(node.rest_of_key):
                # Create a new leaf node with the remaining key
                new_leaf = LeafNode(
                    rest_of_key=node.rest_of_key[common_prefix_len + 1 :],
                    value=node.value,
                )

                # Add to the branch
                branch_subnodes = list(branch_node.subnodes)
                encoded_leaf = encode_internal_node(new_leaf)
                if len(encoded_leaf) >= 32:
                    leaf_hash = keccak256(encoded_leaf)
                    branch_subnodes[node.rest_of_key[common_prefix_len]] = leaf_hash
                    self.nodes[leaf_hash] = encoded_leaf
                else:
                    branch_subnodes[node.rest_of_key[common_prefix_len]] = encoded_leaf
                branch_node = BranchNode(subnodes=tuple(branch_subnodes), value=b"")
                logger.debug(
                    f"Created a branch node at divergence point {common_prefix_len} for path {nibble_path.hex()} and {node.rest_of_key.hex()} and a leaf node"
                )
            else:
                # INVARIANT: The leaf must end at the branch
                assert common_prefix_len + 1 == len(node.rest_of_key)
                # The leaf ends at the branch, add its value
                raise ValueError(
                    "Invariant broken: Leaf node ends at the branch, inserting a non-null value in a Branch node"
                )

            # Add the new path as another branch
            if common_prefix_len + 1 < len(nibble_path):
                # Create a leaf node for the new path
                new_leaf = LeafNode(
                    rest_of_key=nibble_path[common_prefix_len + 1 :], value=value
                )

                # Add to the branch
                branch_subnodes = list(branch_node.subnodes)
                encoded_leaf = encode_internal_node(new_leaf)
                if len(encoded_leaf) >= 32:
                    leaf_hash = keccak256(encoded_leaf)
                    branch_subnodes[nibble_path[common_prefix_len]] = leaf_hash
                    self.nodes[leaf_hash] = encoded_leaf
                else:
                    branch_subnodes[nibble_path[common_prefix_len]] = encoded_leaf
                branch_node = BranchNode(
                    subnodes=tuple(branch_subnodes), value=branch_node.value
                )
            else:
                # TODO: Handle branch node with value
                raise ValueError("Invariant: Branch node with value not supported")

            # If there's a common prefix, create a new extension node
            if common_prefix_len > 0:
                encoded_branch = encode_internal_node(branch_node)
                if len(encoded_branch) >= 32:
                    branch_hash = keccak256(encoded_branch)
                    self.nodes[branch_hash] = encoded_branch
                    return (
                        ExtensionNode(
                            key_segment=nibble_path[:common_prefix_len],
                            subnode=branch_hash,
                        ),
                        True,
                    )
                elif len(encoded_branch) < 32:
                    return (
                        ExtensionNode(
                            key_segment=nibble_path[:common_prefix_len],
                            subnode=encoded_branch,
                        ),
                        True,
                    )
                else:
                    raise ValueError(
                        f"Unexpected case in extension node processing - nibble_path: {nibble_path.hex()} - encoded_branch: {encoded_branch.hex()}"
                    )
            else:
                return branch_node, True

        raise ValueError(f"Unknown node type: {type(node)}")

    def update_from_state_diff(self, state_diff: StateDiff):
        """Apply a state diff to the current state."""
        # First pass: Create or delete accounts
        logger.debug("Updating from state diff")
        for address, account_diff in state_diff.account_diffs.items():
            if account_diff.account is None or account_diff.account == EMPTY_ACCOUNT:
                # Delete account
                logger.debug(f"Deleting account: 0x{address.hex()}")
                self.delete_account(address)
            elif isinstance(account_diff.account, Account):
                logger.debug(
                    f"Start updating account: 0x{address.hex()} - getting storage root"
                )
                storage_root = self.get_storage_root(address)
                for key, value in account_diff.storage_updates.items():
                    if value != U256(0):
                        logger.debug(
                            f"Inserting storage key: 0x{key.hex()} - for address 0x{address.hex()} - value: {value}"
                        )
                        storage_root = self.upsert(
                            keccak256(key), rlp.encode(value), storage_root
                        )
                    else:
                        logger.debug(
                            f"Deleting storage key: 0x{key.hex()} - for address 0x{address.hex()}"
                        )
                        storage_root = self.delete(keccak256(key), storage_root)

                if storage_root is not None:
                    logger.debug(
                        f"Storage root: 0x{storage_root.hex() if storage_root != EMPTY_TRIE_ROOT_HASH else 'EMPTY_TRIE_ROOT_HASH'}"
                    )
                    encoded = encode_account(account_diff.account, storage_root)
                    logger.debug(
                        f"Trying to upsert account: 0x{address.hex()} - encoded: {encoded.hex()}"
                    )
                    self.upsert_account(address, encoded, account_diff.account.code)
                    logger.debug(f"Inserted account: 0x{address.hex()}")

            else:
                raise ValueError(f"Unknown account type: {type(account_diff.account)}")
        logger.debug("Finished updating from state diff")


# Redefinition of encode_internal_node from ethereum.cancun.trie
# without keccak256 of the RLP encoded node if its length is greater than 32 bytes
def encode_internal_node(node: Optional[InternalNode]) -> rlp.Extended:
    """
    Encodes a Merkle Trie node into its RLP form. The RLP will then be
    serialized into a `Bytes` and hashed unless it is less that 32 bytes
    when serialized.

    This function also accepts `None`, representing the absence of a node,
    which is encoded to `b""`.

    Parameters
    ----------
    node : Optional[InternalNode]
        The node to encode.

    Returns
    -------
    encoded : `rlp.Extended`
        The node encoded as RLP.
    """
    unencoded: rlp.Extended
    if node is None:
        unencoded = b""
    elif isinstance(node, LeafNode):
        unencoded = (
            nibble_list_to_compact(node.rest_of_key, True),
            node.value,
        )
    elif isinstance(node, ExtensionNode):
        unencoded = (
            nibble_list_to_compact(node.key_segment, False),
            node.subnode,
        )
    elif isinstance(node, BranchNode):
        unencoded = list(node.subnodes) + [node.value]
    else:
        raise AssertionError(f"Invalid internal node type {type(node)}!")

    encoded = rlp.encode(unencoded)
    return encoded


def decode_node(node: Bytes) -> InternalNode:
    """
    Decode a node from its RLP encoding.

    Parameters
    ----------
    node_data : Bytes
        The RLP encoded node data

    Returns
    -------
    InternalNode
        The decoded node (BranchNode, ExtensionNode, or LeafNode)
    """
    """Decode an RLP encoded node into an InternalNode."""

    decoded = rlp.decode(node)

    if isinstance(decoded, list) and len(decoded) == 17:
        logger.debug("Decoding as branch node")
        return BranchNode(subnodes=tuple(decoded[0:16]), value=decoded[16])
    elif isinstance(decoded, list) and len(decoded) == 2:
        logger.debug("Decoding as extension or leaf node")
        prefix = decoded[0]
        value = decoded[1]

        if not isinstance(prefix, bytes):
            raise ValueError(f"Invalid prefix type: {type(prefix)}")

        # Determine if it's a leaf or extension node based on first nibble
        first_nibble = prefix[0] >> 4
        is_leaf = first_nibble in (2, 3)
        logger.debug(f"First nibble: {first_nibble}, is_leaf: {is_leaf}")

        # Extract the path from the compact encoding
        nibbles = bytes_to_nibble_list(prefix)

        # Remove the flag nibble and odd padding if present
        if first_nibble in (1, 3):  # odd length
            nibbles = nibbles[1:]
            logger.debug("Odd length, removed first nibble")
        else:  # even length
            nibbles = nibbles[2:]
            logger.debug("Even length, removed first two nibbles")

        logger.debug(f"Current path {nibble_path_to_hex(nibbles)}")

        if is_leaf:
            return LeafNode(rest_of_key=nibbles, value=value)
        else:
            return ExtensionNode(key_segment=nibbles, subnode=value)
    else:
        raise ValueError(f"Unknown node structure: {type(decoded)}")
