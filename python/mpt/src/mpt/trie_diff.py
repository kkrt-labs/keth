import logging
from dataclasses import dataclass
from typing import Any, Dict, Optional, Tuple

from ethereum.cancun.fork_types import Address
from ethereum.cancun.trie import BranchNode, ExtensionNode, InternalNode, LeafNode
from ethereum.crypto.hash import Hash32, keccak256
from ethereum_types.bytes import Bytes, Bytes20, Bytes32
from ethereum_types.numeric import U256, Uint

from mpt import EthereumTrieTransitionDB
from mpt.utils import AccountNode, decode_node, nibble_path_to_bytes

logger = logging.getLogger(__name__)


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

    @staticmethod
    def from_data(data: Dict[str, Any]) -> "StateDiff":
        pre_nodes = {
            keccak256(bytes.fromhex(node[2:])): decode_node(bytes.fromhex(node[2:]))
            for node in data["witness"]["state"]
        }

        pre_state_root = Hash32.fromhex(
            data["witness"]["ancestors"][0]["stateRoot"][2:]
        )
        if pre_state_root not in pre_nodes:
            raise ValueError(f"State root not found in nodes: {pre_state_root}")

        post_nodes = {
            keccak256(bytes.fromhex(node[2:])): decode_node(bytes.fromhex(node[2:]))
            for node in data["extra"]["committed"]
        }

        post_state_root = Hash32.fromhex(data["blocks"][0]["header"]["stateRoot"][2:])
        if post_state_root not in post_nodes:
            raise ValueError(f"State root not found in nodes: {post_state_root}")

        nodes = {**pre_nodes, **post_nodes}

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

        ## Parse state diff
        state_diff = StateDiff({}, {}, nodes, address_preimages, storage_key_preimages)
        for diff in data["extra"]["stateDiffs"]:
            address = Address.fromhex(diff["address"][2:])
            if "preAccount" in diff:
                pre_balance = U256(int(diff["preAccount"]["balance"][2:], 16))
                pre_nonce = Uint(int(diff["preAccount"]["nonce"][2:], 16))
                pre_code_hash = Hash32.fromhex(diff["preAccount"]["codeHash"][2:])
                pre_storage_hash = Hash32.fromhex(diff["preAccount"]["storageHash"][2:])
                pre_account = AccountNode(
                    nonce=pre_nonce,
                    balance=pre_balance,
                    code_hash=pre_code_hash,
                    storage_root=pre_storage_hash,
                )
            else:
                pre_account = None

            if "postAccount" in diff:
                post_balance = U256(int(diff["postAccount"]["balance"][2:], 16))
                post_nonce = Uint(int(diff["postAccount"]["nonce"][2:], 16))
                post_code_hash = Hash32.fromhex(diff["postAccount"]["codeHash"][2:])
                post_storage_hash = Hash32.fromhex(
                    diff["postAccount"]["storageHash"][2:]
                )
                post_account = AccountNode(
                    nonce=post_nonce,
                    balance=post_balance,
                    code_hash=post_code_hash,
                    storage_root=post_storage_hash,
                )
            else:
                post_account = None

            state_diff._main_trie[address] = tuple((pre_account, post_account))
        # {
        #         "address": "0xff311cba8a1444d447676d7a180361b54b8e6f45",
        #         "preAccount": {
        #             "balance": "0x3bb651fa5c4d018",
        #             "codeHash": "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
        #             "nonce": "0xe",
        #             "storageHash": "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
        #         },
        #         "postAccount": {
        #             "balance": "0x1af7228882cef08",
        #             "codeHash": "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
        #             "nonce": "0xf",
        #             "storageHash": "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
        #         }
        #     }
        # }

        return state_diff

    @classmethod
    def from_tries(cls, tries: EthereumTrieTransitionDB) -> "StateDiff":
        # Merge all mappings of hash -> node to have a single DB to fetch nodes and resolve addresses from
        diff = StateDiff(
            {}, {}, tries.nodes, tries.address_preimages, tries.storage_key_preimages
        )

        l_root = tries.pre_state_root
        r_root = tries.post_state_root

        diff._compute_diff(l_root, r_root, Bytes())
        return diff

    def _compute_diff(
        self, left: Optional[Hash32], right: Optional[Hash32], path: Bytes
    ):
        if left == right:
            return

        l_node = self._nodes.get(left) if left else None
        r_node = self._nodes.get(right) if right else None

        # Use direct class pattern matching
        match (l_node, r_node):
            case (None, None):
                # No change
                pass

            case (None, LeafNode()):
                # new leaf
                preimage = nibble_path_to_bytes(path + r_node.rest_of_key)
                address = self._address_preimages[preimage]
                self._main_trie[address] = tuple(
                    (None, AccountNode.from_rlp(r_node.value))
                )

            case (None, ExtensionNode()):
                # Look for diffs in the right sub-tree
                self._compute_diff(None, r_node.subnode, path + r_node.key_segment)

            case (None, BranchNode()):
                # Look for diffs in all branches of the right sub-tree
                for i in range(0, 16):
                    self._compute_diff(
                        None, r_node.subnodes[i], path + i.to_bytes(1, "big")
                    )

            case (LeafNode(), None):
                # deleted leaf (should not happen post-cancun)
                preimage = nibble_path_to_bytes(path + l_node.rest_of_key)
                address = self._address_preimages[preimage]
                self._main_trie[address] = tuple(
                    (AccountNode.from_rlp(l_node.value), None)
                )

            case (LeafNode(), LeafNode()):
                if l_node.value != r_node.value:
                    preimage = nibble_path_to_bytes(path + l_node.rest_of_key)
                    address = self._address_preimages[preimage]
                    self._main_trie[address] = tuple(
                        (
                            AccountNode.from_rlp(l_node.value),
                            AccountNode.from_rlp(r_node.value),
                        )
                    )

            case (LeafNode(), BranchNode()):
                # Look for diffs in all branches of the right sub-tree
                for i in range(0, 16):
                    if (
                        i != l_node.rest_of_key[0]
                        or not self._nodes[r_node.subnodes[i]].value == l_node.value
                    ):
                        self._compute_diff(None, r_node.subnodes[i], path + bytes([i]))

            case (LeafNode(), ExtensionNode()):
                raise ValueError(
                    "LeafNode -> ExtensionNode should not happen if comparing two valid trie roots"
                )

            case (ExtensionNode(), None):
                # Look for diffs in the left sub-tree
                self._compute_diff(l_node.subnode, None, path + l_node.key_segment)

            case (ExtensionNode(), LeafNode()):
                raise ValueError(
                    "ExtensionNode -> LeafNode should not happen if comparing two valid trie roots"
                )

            case (ExtensionNode(), ExtensionNode()):
                # Equal keys -> Look for diffs in children
                if l_node.key_segment == r_node.key_segment:
                    self._compute_diff(
                        l_node.subnode, r_node.subnode, path + l_node.key_segment
                    )
                # Right is prefix of left
                elif l_node.key_segment.startswith(r_node.key_segment):
                    # Create a copy of l_node with key_segment shortened by r_node's key_segment
                    l_node.key_segment = l_node.key_segment[len(r_node.key_segment) :]
                    # Compare the right node's value with the left node shortened by right key
                    shortened_path = path + r_node.key_segment
                    self._compute_diff(l_node, r_node.subnode, shortened_path)
                # Left is prefix of right
                elif r_node.key_segment.startswith(l_node.key_segment):
                    # Create a copy of r_node with key_segment shortened by l_node's key_segment
                    r_node.key_segment = r_node.key_segment[len(l_node.key_segment) :]
                    # We'll keep track of the path using the common prefix (left key)
                    shortened_path = path + l_node.key_segment
                    self._compute_diff(l_node.subnode, r_node, shortened_path)
                # Both are different -> Look for diffs in both sub-trees
                else:
                    self._compute_diff(l_node.subnode, None, path + l_node.key_segment)
                    self._compute_diff(None, r_node.subnode, path + r_node.key_segment)

            case (ExtensionNode(), BranchNode()):
                # Match on the corresponding nibble of the extension key segment
                for i in range(0, 16):
                    nibble = i.to_bytes(1, "big")
                    if l_node.key_segment[0] == nibble:
                        # Remove the nibble from the extension key segment
                        l_node.key_segment = l_node.key_segment[1:]
                        self._compute_diff(
                            l_node.subnode, r_node.subnodes[i], path + nibble
                        )
                    else:
                        # Look for diffs in other branches
                        self._compute_diff(
                            l_node.subnode, r_node.subnodes[i], path + nibble
                        )

            case (BranchNode(), None):
                # Look for diffs in all branches of the left sub-tree
                for i in range(0, 16):
                    self._compute_diff(
                        l_node.subnodes[i], None, path + i.to_bytes(1, "big")
                    )

            case (BranchNode(), LeafNode()):
                raise ValueError(
                    "BranchNode -> LeafNode should not happen if comparing two valid trie roots"
                )

            case (BranchNode(), ExtensionNode()):
                # Match on the corresponding nibble of the extension key segment
                for i in range(0, 16):
                    nibble = i.to_bytes(1, "big")
                    if r_node.key_segment[0] == nibble:
                        # Remove the nibble from the extension key segment
                        r_node.key_segment = r_node.key_segment[1:]
                        self._compute_diff(
                            l_node.subnodes[i], r_node.subnode, path + nibble
                        )
                    else:
                        # Look for diffs in other branches
                        self._compute_diff(l_node, None, path + nibble)

            case (BranchNode(), BranchNode()):
                # Look for diffs in all branches of the right sub-tree
                for i in range(0, 16):
                    l_hash = l_node.subnodes[i]
                    r_hash = r_node.subnodes[i]
                    self._compute_diff(l_hash, r_hash, path + i.to_bytes(1, "big"))

            case _:
                raise ValueError(
                    f"Node types do not match: {type(l_node)} != {type(r_node)}"
                )
