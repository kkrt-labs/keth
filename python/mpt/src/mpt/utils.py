import logging

from ethereum.cancun.trie import (
    BranchNode,
    ExtensionNode,
    InternalNode,
    LeafNode,
    bytes_to_nibble_list,
)
from ethereum_rlp import Extended, rlp
from ethereum_types.bytes import Bytes

logger = logging.getLogger(__name__)


def deserialize_to_internal_node(node: Extended) -> InternalNode:
    if not isinstance(node, list):
        raise ValueError(f"Unknown node structure: {type(node)}")
    if len(node) not in (2, 17):
        raise ValueError(f"Unknown node structure: {len(node)}")

    if len(node) == 17:
        return BranchNode(subnodes=tuple(node[0:16]), value=node[16])

    if len(node) == 2:
        prefix = node[0]
        value = node[1]

        nibbles = bytes_to_nibble_list(prefix)
        first_nibble = nibbles[0]
        ODD_LENGTH_PREFIX = (1, 3)

        if first_nibble in ODD_LENGTH_PREFIX:
            nibbles = nibbles[1:]
        else:
            nibbles = nibbles[2:]

        is_leaf = first_nibble in (2, 3)
        if is_leaf:
            return LeafNode(rest_of_key=nibbles, value=value)
        else:
            return ExtensionNode(key_segment=nibbles, subnode=value)


def decode_node(node: Bytes) -> InternalNode:
    decoded = rlp.decode(node)
    return deserialize_to_internal_node(decoded)


def nibble_list_to_bytes(nibble_path: Bytes) -> Bytes:
    """
    Convert a list of nibbles to bytes by concatenating pairs of nibbles.
    """
    is_odd = len(nibble_path) % 2
    result = bytes(
        [
            (nibble_path[i] & 0x0F) * 16 + (nibble_path[i + 1] & 0x0F)
            for i in range(0, len(nibble_path) - is_odd, 2)
        ]
    )
    # Handle the case where there's an odd number of nibbles
    if is_odd:
        result += bytes([(nibble_path[-1] & 0x0F) * 16])
    return result


def nibble_path_to_hex(nibble_path: Bytes) -> str:
    """
    Convert a nibble path to a hex string.
    """
    return "0x" + nibble_list_to_bytes(nibble_path).hex()


def check_branch_node(node: BranchNode) -> None:
    """
    Check that a branch node is valid.
    """
    if len(node.subnodes) < 2:
        raise ValueError("Invalid branch node, expected at least two non-null subnodes")

    non_null_subnodes = [
        subnode for subnode in node.subnodes if subnode not in (None, b"", [])
    ]
    if len(non_null_subnodes) < 2:
        raise ValueError("Invalid branch node, expected at least two non-null subnodes")
