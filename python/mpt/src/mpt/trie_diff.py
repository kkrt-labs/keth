from dataclasses import dataclass
from typing import Dict, Optional, Tuple, cast

from eth_typing import Hash32
from ethereum.cancun.fork_types import Account, Address
from ethereum_types.numeric import U256
from ethereum_types.bytes import Bytes32

from ethereum.cancun.trie import InternalNode, LeafNode, BranchNode, ExtensionNode
from ethereum.crypto.hash import Hash32, keccak256
from ethereum_types.bytes import Bytes, Bytes20, Bytes32
from ethereum_types.numeric import Uint
from ethereum_rlp import rlp
from mpt.utils import nibble_path_to_bytes

import logging

logger = logging.getLogger(__name__)

@dataclass
class AccountNode:
    nonce: Uint
    balance: U256
    code_hash: Hash32
    storage_root: Hash32

    @staticmethod
    def from_rlp(bytes: Bytes) -> "AccountNode":
        decoded = rlp.decode(bytes)
        return AccountNode(
            nonce=Uint(int.from_bytes(decoded[0], "big")),
            balance=U256(int.from_bytes(decoded[1], "big")),
            storage_root=Hash32(decoded[2]),
            code_hash=Hash32(decoded[3]),
        )

    def to_account(self, code: Bytes) -> Account:
        return Account(
            nonce=self.nonce,
            balance=self.balance,
            code=code,
        )

@dataclass
class StateDiff:
    """
    Contains all information that is preserved between transactions.
    """

    _main_trie: Dict[Address, Tuple[Optional[AccountNode], Optional[AccountNode]]]
    _storage_tries: Dict[Address, Tuple[Dict[Bytes32, U256], Dict[Bytes32, U256]]]

    _nodes: Dict[Hash32, InternalNode]
    _address_preimages: Dict[Hash32, Address]
    _storage_key_preimages: Dict[Hash32, Bytes32]

    @classmethod
    def from_tries(cls, tries: "EthereumTries") -> "StateDiff":
        # Merge all mappings of hash -> node to have a single DB to fetch nodes and resolve addresses from
        diff = StateDiff({}, {}, tries.nodes, tries.address_preimages, tries.storage_key_preimages)

        l_root = tries.pre_state_root
        r_root = tries.post_state_root

        diff._compute_diff(l_root, r_root, Bytes())
        return diff

    def _compute_diff(self, left: Optional[Hash32], right: Optional[Hash32], path: Bytes):
        if left == right:
            return

        l_node = self._nodes.get(left) if left else None
        r_node = self._nodes.get(right) if right else None

        l_name = l_node.__class__.__name__ if l_node else "None"
        r_name = r_node.__class__.__name__ if r_node else "None"

        match l_name, r_name:
            case "None", "None":
                # No change
                pass

            case "None", "LeafNode":
                # new leaf
                preimage = nibble_path_to_bytes(path + r_node.rest_of_key)
                address = self._address_preimages[preimage]
                self._main_trie[address] = tuple((None, AccountNode.from_rlp(r_node.value)))

            case "None", "ExtensionNode":
                r_node: ExtensionNode = cast(ExtensionNode, r_node)
                # Look for diffs in the right sub-tree
                self._compute_diff(None, r_node.subnode, path + r_node.key_segment)

            case "None", "BranchNode":
                # Look for diffs in all branches of the right sub-tree
                r_node: BranchNode = cast(BranchNode, r_node)
                for i in range(0, 16):
                    self._compute_diff(None, r_node.subnodes[i], path + i.to_bytes(1, "big"))

            case "LeafNode", "None":
                # deleted leaf (should not happen post-cancun)
                preimage = nibble_path_to_bytes(path + l_node.rest_of_key)
                address = self._address_preimages[preimage]
                self._main_trie[address] = tuple((AccountNode.from_rlp(l_node.value), None))

            case "LeafNode", "LeafNode":
                if l_node.value != r_node.value:
                    preimage = nibble_path_to_bytes(path + l_node.rest_of_key)
                    address = self._address_preimages[preimage]
                    self._main_trie[address] = tuple((AccountNode.from_rlp(l_node.value), AccountNode.from_rlp(r_node.value)))

            case "LeafNode", "BranchNode":
                # Left is a valute, right is
                logger.warning("LeafNode -> BranchNode")
                breakpoint()
                for i in range(0, 16):
                    self._compute_diff(None, r_node.subnodes[i], path + i.to_bytes(1, "big"))

            case "LeafNode", "ExtensionNode":
                raise ValueError("LeafNode -> ExtensionNode should not happen if comparing two valid trie roots")

            case "ExtensionNode", "None":
                # Look for diffs in the left sub-tree
                l_node: ExtensionNode = cast(ExtensionNode, l_node)
                self._compute_diff(l_node.subnode, None, path + l_node.key_segment)

            case "ExtensionNode", "LeafNode":
                raise ValueError("ExtensionNode -> LeafNode should not happen if comparing two valid trie roots")

            case "ExtensionNode", "ExtensionNode":
                l_node: ExtensionNode = cast(ExtensionNode, l_node)
                r_node: ExtensionNode = cast(ExtensionNode, r_node)

                # Equal keys -> Look for diffs in childrens
                if l_node.key_segment == r_node.key_segment:
                    self._compute_diff(l_node.subnode, r_node.subnode, path + l_node.key_segment)

                # Right is prefix of left -> Look for diffs in left sub-tree
                elif l_node.key_segment.startswith(r_node.key_segment):
                    # Remove the prefix from the extension key segment
                    l_node.key_segment = l_node.key_segment[len(r_node.key_segment):]
                    self._compute_diff(l_node.subnode, None, path + l_node.key_segment)

                # Left is prefix of right -> Look for diffs in right sub-tree
                elif r_node.key_segment.startswith(l_node.key_segment):
                    # Remove the prefix from the extension key segment
                    r_node.key_segment = r_node.key_segment[len(l_node.key_segment):]
                    self._compute_diff(None, r_node.subnode, path + r_node.key_segment)

                # Both are different -> Look for diffs in both sub-trees
                else:
                    self._compute_diff(l_node.subnode, r_node.subnode, path + l_node.key_segment)

            case "ExtensionNode", "BranchNode":
                l_node: ExtensionNode = cast(ExtensionNode, l_node)
                r_node: BranchNode = cast(BranchNode, r_node)
                # Match on the corresponding nibble of the extension key segment
                for i in range(0, 16):
                    nibble = i.to_bytes(1, "big")
                    if l_node.key_segment[0] == nibble:
                        # Remove the nibble from the extension key segment
                        l_node.key_segment = l_node.key_segment[1:]
                        self._compute_diff(l_node.subnode, r_node.subnodes[i], path + nibble)
                    else:
                        # Look for diffs in other branches
                        self._compute_diff(l_node.subnode, r_node.subnodes[i], path + nibble)

            case "BranchNode", "None":
                # Look for diffs in all branches of the left sub-tree
                l_node: BranchNode = cast(BranchNode, l_node)
                for i in range(0, 16):
                    self._compute_diff(l_node.subnodes[i], None, path + i.to_bytes(1, "big"))

            case "BranchNode", "LeafNode":
                raise ValueError("BranchNode -> LeafNode should not happen if comparing two valid trie roots")

            case "BranchNode", "ExtensionNode":
                l_node: BranchNode = cast(BranchNode, l_node)
                r_node: ExtensionNode = cast(ExtensionNode, r_node)
                # Match on the corresponding nibble of the extension key segment
                for i in range(0, 16):
                    nibble = i.to_bytes(1, "big")
                    if r_node.key_segment[0] == nibble:
                        # Remove the nibble from the extension key segment
                        r_node.key_segment = r_node.key_segment[1:]
                        self._compute_diff(l_node.subnodes[i], r_node.subnode, path + nibble)
                    else:
                        # Look for diffs in other branches
                        self._compute_diff(l_node, None, path + nibble)

            case "BranchNode", "BranchNode":
                # Look for diffs in all branches of the right sub-tree
                l_node = cast(BranchNode, l_node)
                r_node = cast(BranchNode, r_node)
                for i in range(0, 16):
                    l_hash = l_node.subnodes[i]
                    r_hash = r_node.subnodes[i]
                    self._compute_diff(l_hash, r_hash, path + i.to_bytes(1, "big"))

            case _:
                raise ValueError(f"Node types do not match: {type(l_node)} != {type(r_node)}")
