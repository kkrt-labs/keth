import logging
from dataclasses import dataclass

from ethereum.cancun.fork_types import Account
from ethereum.cancun.trie import (
    BranchNode,
    ExtensionNode,
    InternalNode,
    LeafNode,
    bytes_to_nibble_list,
)
from ethereum.crypto.hash import Hash32
from ethereum_rlp import rlp
from ethereum_types.bytes import Bytes
from ethereum_types.numeric import U256, Uint

logger = logging.getLogger(__name__)


@dataclass
class AccountNode:
    """
    Represents an account node in an Ethereum MPT.
    """

    nonce: Uint
    balance: U256
    code_hash: Hash32
    storage_root: Hash32

    @staticmethod
    def from_rlp(bytes: Bytes) -> "AccountNode":
        """
        Decode the RLP encoded representation of an account node.
        """
        decoded = rlp.decode(bytes)
        return AccountNode(
            nonce=Uint(int.from_bytes(decoded[0], "big")),
            balance=U256(int.from_bytes(decoded[1], "big")),
            storage_root=Hash32(decoded[2]),
            code_hash=Hash32(decoded[3]),
        )

    def to_eels_account(self, code: Bytes) -> Account:
        """
        Converts an "AccountNode" to the "Account" type used in EELS.
        """
        return Account(
            nonce=self.nonce,
            balance=self.balance,
            code=code,
        )


def decode_node(node: Bytes) -> InternalNode:
    decoded = rlp.decode(node)

    if not isinstance(decoded, list):
        raise ValueError(f"Unknown node structure: {type(decoded)}")
    if len(decoded) not in (2, 17):
        raise ValueError(f"Unknown node structure: {len(decoded)}")

    if len(decoded) == 17:
        return BranchNode(subnodes=tuple(decoded[0:16]), value=decoded[16])

    if len(decoded) == 2:
        prefix = decoded[0]
        value = decoded[1]

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


def nibble_path_to_bytes(nibble_path: Bytes) -> Bytes:
    """
    Convert a list of nibbles to bytes by concatenating pairs of nibbles.
    """
    return bytes(
        [
            (nibble_path[i] & 0x0F) * 16 + (nibble_path[i + 1] & 0x0F)
            for i in range(0, len(nibble_path) - 1, 2)
        ]
    )


def nibble_path_to_hex(nibble_path: Bytes) -> str:
    """
    Convert a nibble path to a hex string.
    """
    return "0x" + nibble_path_to_bytes(nibble_path).hex()
