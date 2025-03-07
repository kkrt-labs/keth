import json
from typing import Dict, List

from ethereum.cancun.trie import (
    BranchNode,
    ExtensionNode,
    InternalNode,
    LeafNode,
    nibble_list_to_compact,
)
from ethereum.crypto.hash import keccak256
from ethereum_rlp import rlp
from ethereum_types.bytes import Bytes, Bytes32


def mpt_from_json(path: str) -> InternalNode:
    with open(path, "r") as f:
        data = json.load(f)

    # Load the state root from the json file
    state_root = (
        bytes.fromhex(data["witness"]["ancestors"][0]["stateRoot"][2:])
        if data["witness"]["ancestors"][0]["stateRoot"].startswith("0x")
        else bytes.fromhex(data["witness"]["ancestors"][0]["stateRoot"])
    )

    # Load the state and storage MPT nodes from the json file
    nodes = [
        bytes.fromhex(node[2:] if node.startswith("0x") else node)
        for node in data["witness"]["state"]
    ]
    # Load the codes from the json file
    codes = [
        bytes.fromhex(code[2:] if code.startswith("0x") else code)
        for code in data["witness"]["codes"]
    ]

    # Build the MPT from the nodes
    mpt = build_mpt_from_nodes(nodes, codes, state_root)

    return mpt


def decode_node(node: Bytes, path: Bytes = b"") -> InternalNode:
    """Decode an RLP encoded node into an InternalNode."""
    decoded = rlp.decode(node)
    if isinstance(decoded, list) and len(decoded) == 17:
        return BranchNode(subnodes=decoded[0:16], value=decoded[16])
    elif isinstance(decoded, list) and len(decoded) == 2:
        prefix = node[0]
        value = node[1]

        if not isinstance(prefix, bytes):
            return

        # Determine if it's a leaf or extension node based on first nibble
        first_nibble = prefix[0] >> 4
        is_leaf = first_nibble in (2, 3)

        # Extract the path from the compact encoding
        nibbles = []
        for b in prefix:
            nibbles.extend([(b >> 4) & 0xF, b & 0xF])

        # Remove the flag nibble and odd padding if present
        if first_nibble in (1, 3):  # odd length
            nibbles = nibbles[1:]
        else:  # even length
            nibbles = nibbles[2:]

        # Convert nibbles to bytes and concatenate with the path
        nibble_bytes = bytes(nibbles)
        current_path = path + nibble_bytes

        if is_leaf:
            return LeafNode(rest_of_key=current_path, value=value)
        else:
            return ExtensionNode(key_segment=current_path, subnode=value)
    else:
        raise ValueError(f"Unknown node type: {type(decoded)}")


def build_mpt_from_nodes(
    nodes: List[Bytes], codes: List[Bytes], state_root: Bytes32
) -> InternalNode:
    """Build an Ethereum State Merkle Patricia Trie from a list of nodes and a state root.
    Returns the root node of the MPT with all the nodes resolved.
    """

    # Build a dictionary of keccak(node) -> node
    nodes_dict = {keccak256(node): node for node in nodes}

    # Build a dictionary of keccak(code) -> code
    codes_dict = {keccak256(code): code for code in codes}

    # Start from the state root and build the MPT from the top down.
    root_node = decode_node(nodes_dict[state_root])
    resolve_nodes(root_node, nodes_dict, codes_dict)

    return root_node


def resolve_nodes(
    node: InternalNode, nodes_dict: Dict[Bytes, Bytes], codes_dict: Dict[Bytes, Bytes]
):
    """
    Resolve all MPT nodes referenced by their keccak hash with their actual RLP encoding in the MPT.
    This function is recursive and will resolve all the nodes in the MPT.
    It has a side effect of mutating the root_node in place.
    """
    if isinstance(node, BranchNode):
        for i in range(16):
            # If the subnode is of length 32, it's a node hash
            # We resolve it in the Dict<keccak(rlp(node)), rlp(node)>
            if len(node.subnodes[i]) == 32 and node.subnodes[i] in nodes_dict:
                # If the hash is in the nodes_dict, decode it, else keep the hash
                node.subnodes[i] = decode_node(nodes_dict[node.subnodes[i]])
                resolve_nodes(node.subnodes[i], nodes_dict, codes_dict)
            if node.subnodes[i] is None:
                node.subnodes[i] = b""
    elif isinstance(node, ExtensionNode):
        if node.subnode in nodes_dict:
            node.subnode = decode_node(nodes_dict[node.subnode])
            resolve_nodes(node.subnode, nodes_dict, codes_dict)
    elif isinstance(node, LeafNode):
        # If node.value is a list and has 4 elements, it's an account node
        decoded = rlp.decode(node.value)
        if isinstance(decoded, list) and len(decoded) == 4:
            # The third element is the code hash
            _code_hash = decoded[2]
            # node.value[2] = codes_dict[code_hash]
            # The fourth element is the storage root
            storage_root = decoded[3]
            # We resolve the storage root
            if storage_root in nodes_dict:
                resolve_nodes(nodes_dict[storage_root], nodes_dict, codes_dict)
            else:
                pass
        elif isinstance(decoded, list) and len(decoded) == 2:
            pass


def encode_resolved_mpt(node: InternalNode) -> bytes:
    """
    Recursively encodes a fully resolved MPT structure into its RLP-encoded form.
    This function traverses the entire trie and properly encodes each node according to the
    Ethereum MPT specification.

    Parameters
    ----------
    node : InternalNode
        The root node of the MPT to encode.

    Returns
    -------
    bytes
        The RLP-encoded bytes of the entire MPT structure.
    """
    if node is None:
        return rlp.encode(b"")

    if isinstance(node, LeafNode):
        # For leaf nodes, encode as (path, value)
        encoded_path = nibble_list_to_compact(node.rest_of_key, True)
        return rlp.encode((encoded_path, node.value))

    elif isinstance(node, ExtensionNode):
        # For extension nodes, recursively encode the subnode first
        encoded_path = nibble_list_to_compact(node.key_segment, False)

        # If subnode is an internal node, recursively encode it
        if isinstance(node.subnode, (LeafNode, ExtensionNode, BranchNode)):
            encoded_subnode = encode_resolved_mpt(node.subnode)

            # If the encoded subnode is 32+ bytes, use its hash instead
            if len(encoded_subnode) >= 32:
                subnode_hash = keccak256(encoded_subnode)
                return rlp.encode((encoded_path, subnode_hash))
            else:
                # Decode the RLP to get the raw structure, then re-encode with the path
                decoded_subnode = rlp.decode(encoded_subnode)
                return rlp.encode((encoded_path, decoded_subnode))
        else:
            # If subnode is already a hash or raw value
            return rlp.encode((encoded_path, node.subnode))

    elif isinstance(node, BranchNode):
        # For branch nodes, recursively encode each of the 16 subnodes
        encoded_subnodes = []

        for subnode in node.subnodes:
            if isinstance(subnode, (LeafNode, ExtensionNode, BranchNode)):
                # Recursively encode internal nodes
                encoded_subnode = encode_resolved_mpt(subnode)

                # If the encoded subnode is 32+ bytes, use its hash
                if len(encoded_subnode) >= 32:
                    encoded_subnodes.append(keccak256(encoded_subnode))
                else:
                    # For small nodes, use the raw RLP structure
                    decoded_subnode = rlp.decode(encoded_subnode)
                    encoded_subnodes.append(decoded_subnode)
            elif subnode is None or subnode == b"":
                # Empty nodes are represented as empty byte strings
                encoded_subnodes.append(b"")
            else:
                # Raw values or hashes are used as-is
                encoded_subnodes.append(subnode)

        # Add the value (17th item)
        value = node.value if node.value is not None else b""

        # Encode the branch node with all subnodes and the value
        return rlp.encode(encoded_subnodes + [value])

    else:
        raise ValueError(f"Unknown node type: {type(node)}")
