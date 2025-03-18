import logging

from ethereum.cancun.trie import (
    BranchNode,
    ExtensionNode,
    InternalNode,
    LeafNode,
    bytes_to_nibble_list,
)
from ethereum_rlp import rlp
from ethereum_types.bytes import Bytes

logger = logging.getLogger(__name__)


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
