import logging
from dataclasses import dataclass
from typing import Any

from ethereum.cancun.trie import (
    BranchNode,
    ExtensionNode,
    InternalNode,
    LeafNode,
    bytes_to_nibble_list,
)
from ethereum.crypto.hash import Hash32
from ethereum_rlp import Extended, rlp
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

    def to_rlp(self) -> Bytes:
        """
        Encode the account node as RLP.
        """
        nonce_bytes = (
            self.nonce._number.to_bytes(
                (self.nonce._number.bit_length() + 7) // 8, "big"
            )
            or b"\x00"
        )
        balance_bytes = self.balance._number.to_bytes(32, "big")
        balance_bytes = balance_bytes.lstrip(b"\x00") or b"\x00"

        encoded = rlp.encode(
            [
                nonce_bytes,
                balance_bytes,
                self.storage_root,
                self.code_hash,
            ]
        )
        return encoded

    def to_eels_account(self, code: Bytes) -> Any:
        """
        Converts an "AccountNode" to the "Account" type used in EELS.
        Note: This used the replacement `Account` type defined in `args_gen`
        """
        from tests.utils.args_gen import Account

        return Account(
            nonce=self.nonce,
            balance=self.balance,
            code=code,
            storage_root=self.storage_root,
        )


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
