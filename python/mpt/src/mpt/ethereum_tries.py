import json
import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Mapping, Optional

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
from mpt.utils import (
    AccountNode,
    decode_node,
    nibble_list_to_bytes,
)

logger = logging.getLogger(__name__)


EMPTY_TRIE_HASH = Hash32.fromhex(
    "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
)
EMPTY_BYTES_HASH = Hash32.fromhex(
    "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
)


@dataclass
class EthereumTries:
    nodes: Mapping[Hash32, InternalNode]
    codes: Mapping[Hash32, Bytes]
    address_preimages: Mapping[Hash32, Address]
    storage_key_preimages: Mapping[Hash32, Bytes32]
    state_root: Hash32

    # TODO: remove this rpc client when we can
    rpc_client: Optional[EthereumRPC] = None

    def get_code(self, code_hash: Hash32, address: Address) -> Bytes:
        if code_hash == EMPTY_BYTES_HASH:
            return b""

        code = self.codes.get(code_hash)
        if code is not None:
            return code

        # init rpc client if not set
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
        nodes = {
            keccak256(bytes.fromhex(node[2:])): decode_node(bytes.fromhex(node[2:]))
            for node in data["witness"]["state"]
        }

        state_root = Hash32.fromhex(data["witness"]["ancestors"][0]["stateRoot"][2:])
        if state_root not in nodes:
            raise ValueError(f"State root not found in nodes: {state_root}")

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
        address_preimages = {
            keccak256(Bytes20.fromhex(preimage["address"][2:])): Address.fromhex(
                preimage["address"][2:]
            )
            for preimage in data["accessList"]
        }
        storage_key_preimages = {
            keccak256(Bytes32.fromhex(storage_key[2:])): Bytes32.fromhex(
                storage_key[2:]
            )
            for access in data["accessList"]
            for storage_key in access["storageKeys"] or []
        }

        return EthereumTries(
            nodes=nodes,
            codes=codes,
            address_preimages=address_preimages,
            storage_key_preimages=storage_key_preimages,
            state_root=state_root,
        )

    def traverse_trie(
        self, node: InternalNode, current_path: Bytes, process_leaf: callable, **kwargs
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
        **kwargs:
            Additional arguments to pass to process_leaf. Typically the mutable state object and optionally the current account address.
        """

        if isinstance(node, BranchNode):
            logger.debug(
                f"Traversing branch node with current path 0x{nibble_list_to_bytes(current_path).hex()}"
            )
            for i in range(16):
                nibble = bytes([i])
                subnode = node.subnodes[i]
                # We skip empty nodes
                if not subnode:
                    continue

                # Handle the next node
                next_node = None
                if len(subnode) == 32:
                    next_node = self.nodes.get(subnode)
                    if next_node is None:
                        # If the subnode is not found, we assume this path
                        # is not needed for block execution
                        continue
                if len(subnode) < 32:
                    next_node = decode_node(subnode)

                if len(subnode) > 32:
                    raise ValueError(f"Invalid subnode length: {len(subnode)}")

                if next_node is not None:
                    logger.debug(
                        f"Traversing branch node with current path 0x{nibble_list_to_bytes(current_path + nibble).hex()}"
                    )
                    self.traverse_trie(
                        next_node, current_path + nibble, process_leaf, **kwargs
                    )
            return

        if isinstance(node, ExtensionNode):
            logger.debug(
                f"Traversing extension node with current path 0x{nibble_list_to_bytes(current_path + node.key_segment).hex()}"
            )
            current_path = current_path + node.key_segment

            # subnode is a hash, so we need to resolve it
            if len(node.subnode) == 32:
                next_node = self.nodes.get(node.subnode)
                if next_node is None:
                    # If the subnode is not found, we assume this path
                    # is not needed for block execution
                    return
                self.traverse_trie(next_node, current_path, process_leaf, **kwargs)
                return
            # if subnode is less than 32 bytes, it's an embedded (RLP-encoded) node
            if len(node.subnode) < 32:
                next_node = decode_node(node.subnode)
                self.traverse_trie(next_node, current_path, process_leaf, **kwargs)
                return

            if len(node.subnode) > 32:
                raise ValueError(f"Invalid subnode length: {len(node.subnode)}")

        if isinstance(node, LeafNode):
            logger.debug(
                f"Traversing leaf node with current path 0x{nibble_list_to_bytes(current_path + node.rest_of_key).hex()}"
            )
            full_path = nibble_list_to_bytes(current_path + node.rest_of_key)
            return process_leaf(node, full_path, **kwargs)

        return

    def process_account_leaf(
        self,
        node: LeafNode,
        full_path: Bytes,
        state: State,
    ) -> None:
        logger.debug(f"Processing account leaf node with path 0x{full_path.hex()}")
        address = self.address_preimages.get(full_path)
        if address is None:
            logger.debug(
                f"Address not found in address preimages: {full_path}, skipping"
            )
            return

        account_node = AccountNode.from_rlp(node.value)
        account_code = self.get_code(account_node.code_hash, address)
        account = account_node.to_account(account_code)

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
                f"Storage root node not found for account 0x{address.hex()}, skipping"
            )
            return
        logger.debug(
            f"Storage root node found for 0x{address.hex()}, opening storage trie"
        )
        self.resolve_storage(storage_root_node, b"", state, address)

    def process_storage_leaf(
        self,
        node: LeafNode,
        full_path: Bytes,
        state: State,
        account_address: Address,
    ) -> None:
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

    def resolve(self, node: InternalNode, current_path: Bytes, state: State) -> None:
        logger.debug(f"Resolving node at path 0x{current_path.hex()}")
        return self.traverse_trie(
            node, current_path, self.process_account_leaf, state=state
        )

    def resolve_storage(
        self,
        node: InternalNode,
        current_path: Bytes,
        state: State,
        account_address: Address,
    ) -> None:
        return self.traverse_trie(
            node,
            current_path,
            self.process_storage_leaf,
            state=state,
            account_address=account_address,
        )

    def to_state(self) -> State:
        """
        Convert the Ethereum tries to a State object from the `ethereum` package.
        """
        state = State()
        root_node = self.nodes[self.state_root]
        logger.debug("Starting to derive state from root node")
        self.resolve(root_node, b"", state)
        logger.debug("Finished deriving state object")
        return state
