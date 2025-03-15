# %% Imports
import json
import logging
import os
import random
from pathlib import Path
from typing import List, Mapping, Optional, Tuple, Union

from ethereum_types.bytes import Bytes
from ethereum_types.numeric import U256, Uint
from hexbytes import HexBytes

from ethereum.cancun.blocks import Receipt
from ethereum.cancun.fork_types import Account
from ethereum.cancun.trie import (
    BranchNode,
    ExtensionNode,
    InternalNode,
    LeafNode,
    bytes_to_nibble_list,
    common_prefix_length,
    encode_internal_node,
)
from ethereum.crypto.hash import keccak256
from ethereum.rlp import decode
from tests.utils.helpers import flatten
from tests.utils.models import Block

if os.getcwd().endswith("cairo"):
    os.chdir("..")

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

# %% Load prover input
BLOCK_NUMBER = 21389405
prover_input_path = Path(f"cache/{BLOCK_NUMBER}.json")

with open(prover_input_path, "r") as f:
    prover_input = json.load(f)

prover_input_long = json.load(
    open(prover_input_path.parent / "21389405_long.json", "r")
)

preimages = {
    keccak256(HexBytes(preimage)): HexBytes(preimage)
    for preimage in flatten(
        [
            [proof["address"]] + [p["key"] for p in proof.get("storageProof", [])]
            for proof in prover_input_long["preStateProofs"]
        ]
    )
}

# %% Parse transactions

transactions = [
    tx for tx in prover_input["block"]["transactions"] if int(tx["type"], 16) != 3
]
logger.info(
    f"Number of non-blob transactions: {len(transactions)} / {len(prover_input['block']['transactions'])}"
)

header = prover_input["block"].copy()
del header["transactions"]
del header["withdrawals"]
del header["size"]

(prover_input_path.parent / f"{prover_input_path.stem}_block.json").write_text(
    Block.model_validate(
        {"block_header": header, "transactions": transactions}
    ).model_dump_json(indent=2)
)


# %% Utils to be added to ethereum.cancun.trie
def compact_to_nibble_list(compact: Bytes) -> tuple[Bytes, bool]:
    """
    Decompresses a compact byte array back into a nibble list and leaf flag.

    The compact encoding uses the highest nibble of the first byte as a flag:
    +---+---+----------+--------+
    | _ | _ | is_leaf | parity |
    +---+---+----------+--------+
      3   2      1         0

    Parameters
    ----------
    compact : Bytes
        Compact byte array with encoded flag.

    Returns
    -------
    tuple[Bytes, bool]
        (nibble_list, is_leaf) where:
        - nibble_list is the decoded array of nibbles
        - is_leaf is True for leaf nodes, False for extension nodes
    """
    flag = compact[0] >> 4  # Get the flag nibble
    is_leaf = bool((flag >> 1) & 1)  # Second bit of flag
    is_odd = bool(flag & 1)  # Last bit of flag

    nibbles = bytearray()

    # Handle first byte
    if is_odd:
        nibbles.append(compact[0] & 0x0F)  # Keep only lower nibble

    # Handle remaining bytes
    for byte in compact[1:]:
        nibbles.append(byte >> 4)  # High nibble
        nibbles.append(byte & 0x0F)  # Low nibble

    return Bytes(nibbles), is_leaf


def nibble_list_to_bytes(nibble_list: Bytes) -> Bytes:
    """
    Converts a sequence of nibbles (bytes with value < 16) back into bytes.

    Parameters
    ----------
    nibble_list : Bytes
        The nibble list to convert, must be even length.

    Returns
    -------
    bytes_ : Bytes
        The reconstructed bytes.

    Raises
    ------
    ValueError
        If nibble_list length is not even.
    """
    if len(nibble_list) % 2 != 0:
        nibble_list = b"\x00" + nibble_list

    bytes_array = bytearray(len(nibble_list) // 2)
    for i in range(0, len(nibble_list), 2):
        bytes_array[i // 2] = (nibble_list[i] << 4) | nibble_list[i + 1]

    return Bytes(bytes_array)


def decode_node(node: Bytes) -> Union[LeafNode, ExtensionNode, BranchNode]:
    decoded = decode(node)
    if len(decoded) == 17:
        return BranchNode(decoded[:16], decoded[16])

    nibbles, is_leaf = compact_to_nibble_list(decoded[0])

    if is_leaf:
        return LeafNode(nibbles, decoded[1])
    else:
        return ExtensionNode(nibbles, decoded[1])


def collect_leaves(
    node: Union[LeafNode, ExtensionNode, BranchNode],
    prefix: HexBytes = HexBytes(b""),
    references: dict[Bytes, Union[LeafNode, ExtensionNode, BranchNode]] = {},
) -> List[Tuple[Bytes, Bytes]]:
    """
    Recursively collects all leaves from a trie node.

    Parameters
    ----------
    node : Node
        The current node (Branch, Extension, or Leaf)
    prefix : Bytes
        The accumulated path prefix (in nibbles)

    Returns
    -------
    List[Tuple[Bytes, Bytes]]
        List of (path, value) pairs for all leaves
    """

    if isinstance(node, LeafNode):
        # For leaf nodes, combine prefix with node path and return value
        full_path = prefix + node.rest_of_key
        return [(nibble_list_to_bytes(full_path), node.value)]

    elif isinstance(node, ExtensionNode):
        # For extension nodes, add path to prefix and recurse
        if node.subnode in references:
            return collect_leaves(
                references[node.subnode], prefix + node.key_segment, references
            )

    elif isinstance(node, BranchNode):
        leaves = []
        # For branch nodes, recurse on all non-None children
        for i, child in enumerate(node.subnodes):
            if child is not None:
                # Add the branch index to the prefix
                child_prefix = prefix + Bytes([i])
                if child in references:
                    leaves.extend(
                        collect_leaves(references[child], child_prefix, references)
                    )

        # Don't forget the value if it exists
        if node.value != b"":
            leaves.append((nibble_list_to_bytes(prefix), node.value))

        return leaves

    return []


# %% Decode Pre state
pre_state = [HexBytes(node) for node in prover_input["preState"]]
nodes = [decode_node(node) for node in pre_state]
references = {
    (keccak256(node) if len(node) >= 32 else node): decode_node(node)
    for node in pre_state
}
state_root = HexBytes(prover_input["ancestors"][0]["stateRoot"])
root = references[state_root]

codes = {keccak256(HexBytes(code)): HexBytes(code) for code in prover_input["codes"]}
accounts = {}
storages = {}
pre_state = {}
for key, account in collect_leaves(root, references=references):
    nonce, balance, storage_root, code_hash = decode(account)
    if key in preimages:
        if storage_root in references:
            storage = {
                preimages[k]: v
                for k, v in collect_leaves(
                    references[storage_root], references=references
                )
            }
        else:
            storage = {}

        pre_state[preimages[key]] = {
            "nonce": Uint(int.from_bytes(nonce, "big")),
            "balance": U256(int.from_bytes(balance, "big")),
            "code": codes.get(code_hash, b""),
            "storage": storage,
        }

{
    preimages[k].hex(): {
        "code": list(v.code),
        "storage": storages,
        "balance": v.balance,
        "nonce": v.nonce,
    }
    for k, v in accounts.items()
    if k in preimages
}

logger.info(f"Number of accounts: {len(accounts)}")
logger.info(
    f"Number of storage leaves: {sum(len(values) for values in storages.values())}"
)
len(references)
len(nodes)

# %% Some stats
_nodes_count = 0


def patricialize(obj: Mapping[Bytes, Bytes], level: Uint) -> Optional[InternalNode]:
    """
    Structural composition function.

    Used to recursively patricialize and merkleize a dictionary. Includes
    memoization of the tree structure and hashes.

    Parameters
    ----------
    obj :
        Underlying trie key-value pairs, with keys in nibble-list format.
    level :
        Current trie level.

    Returns
    -------
    node : `ethereum.base_types.Bytes`
        Root node of `obj`.
    """
    global _nodes_count

    if len(obj) == 0:
        return None

    arbitrary_key = next(iter(obj))

    # if leaf node
    if len(obj) == 1:
        leaf = LeafNode(arbitrary_key[level:], obj[arbitrary_key])
        _nodes_count += 1
        return leaf

    # prepare for extension node check by finding max j such that all keys in
    # obj have the same key[i:j]
    substring = arbitrary_key[level:]
    prefix_length = len(substring)
    for key in obj:
        prefix_length = min(prefix_length, common_prefix_length(substring, key[level:]))

        # finished searching, found another key at the current level
        if prefix_length == 0:
            break

    # if extension node
    if prefix_length > 0:
        prefix = arbitrary_key[int(level) : int(level) + prefix_length]
        _nodes_count += 1
        return ExtensionNode(
            prefix,
            encode_internal_node(patricialize(obj, level + Uint(prefix_length))),
        )

    branches = []
    for _ in range(16):
        branches.append({})
    value = b""
    for key in obj:
        if len(key) == level:
            # shouldn't ever have an account or receipt in an internal node
            if isinstance(obj[key], (Account, Receipt, Uint)):
                raise AssertionError
            value = obj[key]
        else:
            branches[key[level]][key] = obj[key]

    _nodes_count += 1
    return BranchNode(
        [
            encode_internal_node(patricialize(branches[k], level + Uint(1)))
            for k in range(16)
        ],
        value,
    )


obj = {
    bytes_to_nibble_list(Bytes(random.randbytes(32))): Bytes(random.randbytes(32))
    for _ in range(5_000)
}

patricialize(obj, Uint(0))
print(_nodes_count)

# %% Pre state with long prover input
codes = {
    keccak256(HexBytes(code)): HexBytes(code) for code in prover_input_long["codes"]
}
pre_state = {}
for account in prover_input_long["preStateProofs"]:
    pre_state[account["address"]] = {
        "nonce": account.get("nonce", 0),
        "balance": int(account.get("balance", 0), 16),
        "code": codes.get(HexBytes(account.get("codeHash", b"")), b"").hex(),
        "storage": {
            slot["key"]: int(slot["value"], 16)
            for slot in account.get("storageProof", [])
        },
    }

json.dump(
    pre_state,
    open(prover_input_path.parent / f"{BLOCK_NUMBER}_pre_state.json", "w"),
    indent=2,
)
