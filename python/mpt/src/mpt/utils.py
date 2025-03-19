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
    decoded = rlp.decode(node)

    if not isinstance(decoded, list):
        raise ValueError(f"Unknown node structure: {type(decoded)}")
    if len(decoded) not in (2, 17):
        raise ValueError(f"Unknown node structure: {len(decoded)}")

    if len(decoded) == 17:
        logger.debug("Decoding as branch node")
        return BranchNode(subnodes=tuple(decoded[0:16]), value=decoded[16])

    if len(decoded) == 2:
        logger.debug("Decoding as extension or leaf node")
        prefix = decoded[0]
        value = decoded[1]

        nibbles = bytes_to_nibble_list(prefix)
        first_nibble = nibbles[0]
        if first_nibble in (1, 3):
            nibbles = nibbles[1:]
        else:
            nibbles = nibbles[2:]

        is_leaf = first_nibble in (2, 3)
        if is_leaf:
            return LeafNode(rest_of_key=nibbles, value=value)
        else:
            return ExtensionNode(key_segment=nibbles, subnode=value)


def nibble_path_to_hex(nibble_path: Bytes) -> str:
    """
    Convert a nibble path to a hex string.
    """
    if len(nibble_path) % 2 != 0:
        nibble_path = nibble_path + b"\x00"
    result = bytes(
        [
            nibble_path[i] * 16 + nibble_path[i + 1]
            for i in range(0, len(nibble_path), 2)
        ]
    )
    return "0x" + result.hex()

def nibble_path_to_bytes(nibble_path: Bytes) -> Bytes:
    """
    Convert a nibble path to a bytes object.
    """
    if len(nibble_path) % 2 != 0:
        nibble_path = nibble_path + b"\x00"
    return bytes([nibble_path[i] * 16 + nibble_path[i + 1] for i in range(0, len(nibble_path), 2)])
