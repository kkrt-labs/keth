import json
import logging
from dataclasses import dataclass
from functools import partial
from pathlib import Path
from typing import Any, Callable, Dict, Mapping, Optional


from ethereum.cancun.fork_types import Address
from ethereum.cancun.state import State, set_account, set_storage
from ethereum.cancun.trie import (
    BranchNode,
    ExtensionNode,
    InternalNode,
    LeafNode,
)
from ethereum.crypto.hash import Hash32, keccak256
from ethereum_rlp import rlp
from ethereum_types.bytes import Bytes, Bytes20, Bytes32
from ethereum_types.numeric import U256

from eth_rpc import EthereumRPC
from mpt.utils import AccountNode, decode_node, nibble_list_to_bytes

logger = logging.getLogger(__name__)


EMPTY_TRIE_HASH = Hash32.fromhex(
    "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
)
EMPTY_BYTES_HASH = Hash32.fromhex(
    "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
)


@dataclass
class EthereumTries:
    """
    Represents an Ethereum MPT.

    Attributes:
        nodes: A mapping of node hashes to the corresponding internal nodes.
        codes: A mapping of code hashes to the corresponding code.
        address_preimages: A mapping of MPT path to the corresponding addresses.
        storage_key_preimages: A mapping of MPT path to the corresponding storage keys.
        state_root: The root hash of the MPT.
    """

    nodes: Mapping[Hash32, InternalNode]
    codes: Mapping[Hash32, Bytes]
    address_preimages: Mapping[Hash32, Address]
    storage_key_preimages: Mapping[Hash32, Bytes32]
    state_root: Hash32

    # TODO: remove
    # Currently, zkpi does not provide codes of accounts touched only by EXTCODEHASH during a block
    # execution. As such, we fallback on an RPC client to fetch missing codes.
    rpc_client: Optional[EthereumRPC] = None

    def get_code(self, code_hash: Hash32, address: Address) -> Bytes:
        """
        Get the code corresponding to the given code hash.
        If no code is found, we fallback on an RPC client to fetch the code.
        """
        if code_hash == EMPTY_BYTES_HASH:
            return b""

        code = self.codes.get(code_hash)
        if code is not None:
            return code

        if self.rpc_client is None:
            self.rpc_client = EthereumRPC.from_env()

        code = self.rpc_client.get_code(address)
        self.codes[code_hash] = code
        return code

    @staticmethod
    def from_json(path: Path):
        with open(path, "r") as f:
            data = json.load(f)
        return EthereumTries.from_data(data)

    @staticmethod
    def from_data(data: Dict[str, Any]):
        """
        Create an EthereumTries object from the ZKPI-provided data.

        Args:
            data: The ZKPI-provided data.

        Returns:
            An EthereumTries object.
        """
        nodes = {
            keccak256(bytes.fromhex(node[2:])): decode_node(bytes.fromhex(node[2:]))
            for node in data["witness"]["state"]
        }

        pre_state_root = Hash32.fromhex(
            data["witness"]["ancestors"][0]["stateRoot"][2:]
        )
        if pre_state_root not in nodes:
            raise ValueError(f"State root not found in nodes: {pre_state_root}")

        codes = {
            keccak256(Bytes.fromhex(code[2:])): Bytes.fromhex(code[2:])
            for code in data["witness"]["codes"]
        }

        # TODO: modify zk-pig to provide directly address preimages

        # We need address & storage key preimages to get an address and storage key given a trie path, which is the hash of address and storage_key for the Ethereum tries
        # Because State object from `ethereum` package maps Addresses to Accounts, and Storage Keys to Storage Values.
        # See 👇
        # class State:
        #     _main_trie: Trie[Address, Optional[Account]]
        #     _storage_tries: Dict[Address, Trie[Bytes32, U256]]
        # ...
        access_list = (
            data["accessList"] if "accessList" in data else data["extra"]["accessList"]
        )
        address_preimages = {
            keccak256(Bytes20.fromhex(preimage["address"][2:])): Address.fromhex(
                preimage["address"][2:]
            )
            for preimage in access_list
        }
        storage_key_preimages = {
            keccak256(Bytes32.fromhex(storage_key[2:])): Bytes32.fromhex(
                storage_key[2:]
            )
            for access in access_list
            for storage_key in access["storageKeys"] or []
        }

        return EthereumTries(
            nodes=nodes,
            codes=codes,
            address_preimages=address_preimages,
            storage_key_preimages=storage_key_preimages,
            state_root=pre_state_root,
        )

    def traverse_trie_and_process_leaf(
        self,
        node: InternalNode,
        current_path: Bytes,
        process_leaf: Callable,
    ) -> None:
        """
        Recursive trie traversal function with a callback for each leaf node.
        The callback is expected to either set an account in state or a value in storage.

        Parameters:
        -----------
        node: InternalNode
            The current node being processed
        current_path: Bytes
            The path traversed so far
        process_leaf: callable
            Function to call when a leaf node is found
        :
            Additional arguments to pass to process_leaf. Typically the mutable state object and optionally the current account address.
        """
        match node:
            case BranchNode():
                for i, subnode in enumerate(node.subnodes):
                    # We skip empty nodes
                    if not subnode:
                        continue
                    nibble = bytes([i])

                    # Handle the next node
                    if len(subnode) > 32:
                        raise ValueError(f"Invalid subnode length: {len(subnode)}")

                    next_node = (
                        self.nodes.get(subnode)
                        if len(subnode) == 32
                        else decode_node(subnode)
                    )
                    if not next_node:
                        # If the subnode is not found, we assume this path
                        # is not needed for block execution
                        continue

                    self.traverse_trie_and_process_leaf(
                        next_node,
                        current_path + nibble,
                        process_leaf,
                    )
                return

            case ExtensionNode():
                current_path = current_path + node.key_segment

                if len(node.subnode) > 32:
                    raise ValueError(f"Invalid subnode length: {len(node.subnode)}")

                # subnode is a hash, so we need to resolve it
                next_node = (
                    self.nodes.get(node.subnode)
                    if len(node.subnode) == 32
                    else decode_node(node.subnode)
                )
                if not next_node:
                    # If the subnode is not found, we assume this path
                    # is not needed for block execution
                    return

                return self.traverse_trie_and_process_leaf(
                    next_node,
                    current_path,
                    process_leaf,
                )

            case LeafNode():
                full_path = nibble_list_to_bytes(current_path + node.rest_of_key)
                return process_leaf(
                    node,
                    full_path,
                )

            case _:
                raise ValueError(f"Invalid node type: {type(node)}")

    def set_account_from_leaf(
        self,
        node: LeafNode,
        full_path: Bytes,
        state: State,
    ):
        """
        Decode the account contained in the leaf node and set the account in the state.
        """
        logger.debug(f"Processing account leaf node with path 0x{full_path.hex()}")
        address = self.address_preimages.get(full_path)
        if address is None:
            logger.debug(
                f"Address not found in address preimages: {full_path}, skipping"
            )
            return

        account_node = AccountNode.from_rlp(node.value)
        account_code = self.get_code(account_node.code_hash, address)
        account = account_node.to_eels_account(account_code)

        logger.debug(
            f"Setting account 0x{address.hex()} with nonce {account.nonce}, balance {account.balance}, code hash 0x{keccak256(account.code).hex()}"
        )
        set_account(state, address, account)

        if account_node.storage_root == EMPTY_TRIE_HASH:
            logger.debug(f"Storage root is empty for account {address.hex()}, skipping")
            return

        # We need to resolve the storage root of the account
        storage_root_node = self.nodes.get(account_node.storage_root)
        if storage_root_node is None:
            logger.debug(
                f"Storage root node not found for account {address.hex()}, skipping"
            )
            return

        self.traverse_trie_and_process_leaf(
            storage_root_node,
            b"",
            partial(self.set_storage_from_leaf, state=state, account_address=address),
        )

    def set_storage_from_leaf(
        self,
        node: LeafNode,
        full_path: Bytes,
        state: State,
        account_address: Address,
    ):
        """
        Decode the storage value contained in the leaf node and set the storage value in the state.
        """
        logger.debug(f"Processing storage leaf node with path 0x{full_path.hex()}")
        storage_key = self.storage_key_preimages.get(full_path)
        if storage_key is None:
            logger.debug(
                f"Storage key not found in storage key preimages: {full_path}, skipping"
            )
            return

        # We need to decode the value of the storage key
        value = rlp.decode(node.value)
        set_storage(
            state, account_address, storage_key, U256(int.from_bytes(value, "big"))
        )

    def to_state(self) -> State:
        """
        Convert the Ethereum tries to a State object from the `ethereum` package.
        """
        state = State()
        root_node = self.nodes[self.state_root]
        self.traverse_trie_and_process_leaf(
            root_node, b"", partial(self.set_account_from_leaf, state=state)
        )
        return state


class EthereumTrieTransitionDB(EthereumTries):
    """
    Contains nodes of two Ethereum tries:
     1. The sparse pre-state trie
     2. The modified nodes in the post-state trie

    We can traverse the entire pre-trie and post-trie from the pre_state_root and post_state_root by
    looking up the nodes in the nodes mapping.

    We can then compute the trie diff by comparing the pre-trie and post-trie.
    """

    post_state_root: Hash32

    @staticmethod
    def from_pre_and_post_tries(pre_trie: EthereumTries, post_trie: EthereumTries):
        return EthereumTrieTransitionDB(
            nodes={**pre_trie.nodes, **post_trie.nodes},
            codes={**pre_trie.codes, **post_trie.codes},
            address_preimages={
                **pre_trie.address_preimages,
                **post_trie.address_preimages,
            },
            storage_key_preimages={
                **pre_trie.storage_key_preimages,
                **post_trie.storage_key_preimages,
            },
            pre_state_root=pre_trie.state_root,
            post_state_root=post_trie.state_root,
        )

    @classmethod
    def from_json(cls, path: Path) -> "EthereumTrieTransitionDB":
        with open(path, "r") as f:
            data = json.load(f)
        return EthereumTrieTransitionDB.from_data(data)

    @classmethod
    def from_data(cls, data: Dict[str, Any]) -> "EthereumTrieTransitionDB":
        """
        Create an EthereumTrieTransitionDB object from the ZKPI-provided data.
        """
        pre_trie = EthereumTries.from_data(data)

        post_nodes = {
            keccak256(bytes.fromhex(node[2:])): decode_node(bytes.fromhex(node[2:]))
            for node in data["extra"]["committed"]
        }
        post_state_root = Hash32.fromhex(data["blocks"][0]["header"]["stateRoot"][2:])
        if post_state_root not in post_nodes:
            raise ValueError(f"Post state root not found in nodes: {post_state_root}")

        instance = cls(
            nodes={**pre_trie.nodes, **post_nodes},
            codes=pre_trie.codes,
            address_preimages=pre_trie.address_preimages,
            storage_key_preimages=pre_trie.storage_key_preimages,
            state_root=pre_trie.state_root,
        )
        instance.post_state_root = post_state_root
        return instance

    def to_pre_state(self) -> State:
        """Convert the pre-state trie to a State object."""
        return self.to_state()

    def to_post_state(self) -> State:
        """Convert the post-state trie to a State object."""
        state = State()
        root_node = self.nodes[self.post_state_root]
        self.traverse_trie_and_process_leaf(
            root_node, b"", partial(self.set_account_from_leaf, state=state)
        )
        return state
