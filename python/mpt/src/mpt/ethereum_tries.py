import json
import logging
from dataclasses import dataclass
from functools import partial
from pathlib import Path
from typing import Any, Callable, Dict, Mapping

from ethereum.cancun.fork_types import EMPTY_ACCOUNT, Account, Address
from ethereum.cancun.state import State, set_account, set_storage
from ethereum.cancun.trie import (
    BranchNode,
    ExtensionNode,
    InternalNode,
    LeafNode,
    Trie,
)
from ethereum.crypto.hash import Hash32, keccak256
from ethereum_rlp import rlp
from ethereum_types.bytes import Bytes, Bytes20, Bytes32
from ethereum_types.numeric import U256, Uint

from mpt.utils import decode_node, nibble_list_to_bytes

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

    def get_code(self, code_hash: Hash32) -> Bytes:
        """
        Get the code corresponding to the given code hash.
        If no code is found, it means the code is not required for block execution.
        """
        if code_hash == EMPTY_BYTES_HASH:
            return b""

        code = self.codes.get(code_hash)
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
        address = self.address_preimages.get(full_path)
        if address is None:
            return

        # RLP-decode the account, then get the code matching the code hash.
        account_without_code = Account.from_rlp(node.value)
        account_code = self.get_code(account_without_code.code_hash)
        account = Account(
            nonce=account_without_code.nonce,
            balance=account_without_code.balance,
            code_hash=account_without_code.code_hash,
            storage_root=account_without_code.storage_root,
            code=account_code,
        )

        set_account(state, address, account)

        if account.storage_root == EMPTY_TRIE_HASH:
            return

        # We need to resolve the storage root of the account
        storage_root_node = self.nodes.get(account.storage_root)
        if storage_root_node is None:
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
        storage_key = self.storage_key_preimages.get(full_path)
        if storage_key is None:
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


class PreState:
    @staticmethod
    def from_data(data: Dict[str, Any]) -> State:
        """
        Create a PreState object from the ZKPI-provided data.
        """
        pre_state = State()
        for address_hex, account in data["extra"]["preState"].items():
            address = Address.fromhex(address_hex[2:])
            # Create an empty storage trie for the account
            storage_trie = Trie(secured=True, default=U256(0), _data={})
            pre_state._storage_tries[address] = storage_trie
            if account is None:
                # If the account is not present in the preState data, we want it explicitly set EMPTY_ACCOUNT
                # so it's an existing entry in the state.
                set_account(pre_state, address, EMPTY_ACCOUNT)
                continue

            # Initialize the account
            pre_balance = U256(int(account["balance"][2:], 16))
            pre_nonce = Uint(int(account["nonce"][2:], 16))
            pre_code_hash = Hash32.fromhex(account["codeHash"][2:])
            pre_storage_hash = Hash32.fromhex(account["storageHash"][2:])
            pre_code = Bytes.fromhex(account["code"][2:]) if "code" in account else None
            # TODO: this is a temporary workaround to EELS doing checking senders of transactions based on code==bytearray() instead of codehash
            # Remove once the e2e flow does not need to call EELS
            if pre_code is None:
                if pre_code_hash == EMPTY_BYTES_HASH:
                    pre_code = b""

            # Explicitly instantiate without code, as it's not an interesting data in the
            # case of state / trie diffs
            pre_account = Account(
                nonce=pre_nonce,
                balance=pre_balance,
                code_hash=pre_code_hash,
                storage_root=pre_storage_hash,
                code=pre_code,
            )
            set_account(pre_state, address, pre_account)

            if "storage" not in account:
                continue

            # Fill the storage trie
            for storage_key_hex, value in account["storage"].items():
                storage_key = Bytes32.fromhex(storage_key_hex[2:])
                pre_state._storage_tries[address]._data[storage_key] = U256(
                    int(value[2:], 16)
                )

        return pre_state


@dataclass
class ZkPi:
    """
    Contains the pre-state, state diff, and transition DB, extracted from the ZKPI-provided JSON data.

    Attributes:
        transition_db: A DB containing nodes and information about the pre and post-block MPTs.
        state_diff: The state diff produced by the STF.
        pre_state: The pre-state of the block.
    """

    from mpt.trie_diff import StateDiff

    transition_db: EthereumTrieTransitionDB
    state_diff: StateDiff
    pre_state: State

    @classmethod
    def from_data(cls, data: Dict[str, Any]) -> "ZkPi":
        """
        Create a ZkPi object from the ZKPI-provided data.

        An account that is not present in the preState data but is present in the postState data is
        set in the pre-state to EMPTY_ACCOUNT.

        A storage key that is not present in the preState
        data but is present in the postState data is set in the pre-state to U256(0).
        """
        from mpt.trie_diff import StateDiff

        transition_tries = EthereumTrieTransitionDB.from_data(data)
        state_diff = StateDiff.from_data(data)
        pre_state = PreState.from_data(data)
        return cls(
            transition_db=transition_tries, state_diff=state_diff, pre_state=pre_state
        )
