import json
from typing import Dict, List, Optional

from ethereum.cancun.blocks import Block, Withdrawal
from ethereum.cancun.fork import BlockChain, state_transition
from ethereum.cancun.fork_types import Account, Address
from ethereum.cancun.state import State
from ethereum.cancun.transactions import LegacyTransaction, encode_transaction
from ethereum.cancun.trie import InternalNode, Trie
from ethereum.crypto.hash import keccak256
from ethereum.utils.hexadecimal import hex_to_bytes, hex_to_u256, hex_to_uint
from ethereum_rlp import rlp
from ethereum_spec_tools.evm_tools.loaders.fixture_loader import Load
from ethereum_spec_tools.evm_tools.loaders.fork_loader import ForkLoad
from ethereum_spec_tools.evm_tools.loaders.transaction_loader import TransactionLoad
from ethereum_types.bytes import Bytes, Bytes0, Bytes32
from ethereum_types.numeric import U64, U256, Uint
from scripts.zkpi_to_eels import normalize_transaction


def decode_node(node: str) -> InternalNode:
    if node.startswith("0x"):
        node = node[2:]
    return rlp.decode(bytes.fromhex(node))


def hash_node(node_str: str) -> str:
    """
    Hash a node string using keccak256.
    If the node is less than 32 bytes, return the node itself.
    Otherwise, return the keccak256 hash of the node.
    """
    # Remove '0x' prefix if present
    if node_str.startswith("0x"):
        node_str = node_str[2:]

    # Convert to bytes
    node_bytes = bytes.fromhex(node_str)

    # If node is less than 32 bytes, return the node itself
    if len(node_bytes) < 32:
        return "0x" + node_str

    # Otherwise, hash the node
    return "0x" + keccak256(node_bytes).hex()


def hash_code(code_str: str) -> str:
    """
    Hash a code string using keccak256.
    """
    # Remove '0x' prefix if present
    if code_str.startswith("0x"):
        code_str = code_str[2:]

    # Convert to bytes
    code_bytes = bytes.fromhex(code_str)

    # Hash the code
    return "0x" + keccak256(code_bytes).hex()


def explore_trie(
    node_dict: Dict[str, str],
    node_hash: str,
    path: str = "",
    accounts_or_storage: Dict = {},
    code_dict: Dict = {},
    storage_roots: List[str] = [],
) -> Dict[str, Account]:
    """
    Recursively explore the trie starting from a node hash.

    Parameters:
    - node_dict: Dictionary mapping node hashes to node data
    - node_hash: Hash of the current node to explore
    - path: Current accumulated path (in hex)
    - accounts_or_storage: Dictionary to store accounts or storage slots (path -> account or storage slot)

    Returns:
    - Dictionary mapping paths to accounts or storage slots
    """

    # Get the node data from the dictionary
    node_data = node_dict.get(node_hash)
    if not node_data:
        raise ValueError(
            f"Node with hash {node_hash} not found in node dictionary - path is 0x{path}"
        )

    # Decode the node
    decoded_node = decode_node(node_data)

    # Check node type based on the decoded structure
    if isinstance(decoded_node, list) and len(decoded_node) == 17:  # Branch node
        # Process value at the branch node (16th element)
        if decoded_node[16]:
            raise ValueError("Branch node with value found is very sus")

        # Recursively explore all branches (first 16 elements)
        for i in range(16):
            if decoded_node[i]:
                # If this branch has a node, explore it
                new_path = path + hex(i)[2:]

                # Check if it's an embedded node or a hash reference
                if isinstance(decoded_node[i], list):
                    # It's an embedded node, process it directly
                    process_node(
                        decoded_node[i],
                        new_path,
                        accounts_or_storage,
                        node_dict,
                        code_dict,
                        storage_roots,
                    )
                else:
                    child_hash = "0x" + decoded_node[i].hex()

                    try:
                        explore_trie(
                            node_dict,
                            child_hash,
                            new_path,
                            accounts_or_storage,
                            code_dict,
                            storage_roots,
                        )
                    except ValueError:
                        pass

    elif (
        isinstance(decoded_node, list) and len(decoded_node) == 2
    ):  # Extension or Leaf node
        process_node(
            decoded_node,
            path,
            accounts_or_storage,
            node_dict,
            code_dict,
            storage_roots,
        )
    return accounts_or_storage


def process_node(node, path, accounts_or_storage, node_dict, code_dict, storage_roots):
    """
    Process a node (extension or leaf) and update accounts dictionary.

    Parameters:
    - node: The node to process
    - path: Current path
    - accounts: Dictionary to update with accounts
    - node_dict: Dictionary of all nodes
    """
    if len(node) != 2:
        return

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

    current_path = path + "".join(hex(n)[2:] for n in nibbles)

    if is_leaf:
        value = rlp.decode(value)
        if isinstance(value, list) and len(value) == 4:
            # This leaf node stores an account
            code = bytes.fromhex(code_dict.get("0x" + value[3].hex(), "0x")[2:])
            accounts_or_storage[current_path] = Account(
                nonce=Uint(int.from_bytes(value[0], "big")),
                balance=U256(int.from_bytes(value[1], "big")),
                code=code,
            )
            storage_roots.append((current_path, value[2]))
        else:
            # This leaf node stores a storage slot
            accounts_or_storage[current_path] = U256(int.from_bytes(value, "big"))
    else:
        # This is an extension node, continue exploring
        if isinstance(value, list):
            # Embedded node
            process_node(
                value,
                current_path,
                accounts_or_storage,
                node_dict,
                code_dict,
                storage_roots,
            )
        else:
            # Hash reference
            next_encoded = rlp.encode(value)
            next_node_hash = hash_node(next_encoded.hex())
            try:
                explore_trie(
                    node_dict,
                    next_node_hash,
                    current_path,
                    accounts_or_storage,
                    code_dict,
                    storage_roots,
                )
            except ValueError:
                pass


def main():
    with open("data/1/inputs/21872325.json", "r") as f:
        data = json.load(f)
        witness = data["witness"]

        # Step 1: Hash all nodes in the witness:state and insert them in a Dict<keccak(rlp(node)), node>
        node_dict = {}
        for node in witness["state"]:
            node_hash = hash_node(node)
            node_dict[node_hash] = node

        # Step 2: Hash all codes in the witness:codes and insert them in a Dict<keccak(code), code>
        code_dict = {}
        if "codes" in witness:
            for code in witness["codes"]:
                code_hash = hash_code(code)
                code_dict[code_hash] = code

        #  Step 3: Get ancestors[0]['stateRoot']
        state_root = witness["ancestors"][0]["stateRoot"]

        # Step 4: Recursively explore the state trie to get to the leaves,
        # starting from the state root provided in the parent block header
        accounts = {}
        storage_roots = []
        explore_trie(
            node_dict,
            state_root,
            accounts_or_storage=accounts,
            code_dict=code_dict,
            storage_roots=storage_roots,
        )

        # Step 5: Traverse the storage nodes using the multiple storage roots
        # found in the leaves of the state MPT nodes
        storage_dicts = {}
        for path, storage_root in storage_roots:
            storage_dict = {}
            storage_root_hex = "0x" + storage_root.hex()
            (
                explore_trie(
                    node_dict,
                    storage_root_hex,
                    accounts_or_storage=storage_dict,
                    code_dict=code_dict,
                )
                if storage_root_hex in node_dict
                else {}
            )
            if storage_dict != {}:
                storage_dicts[path] = storage_dict

        # Step 6: Create the Blockchain and Block objects
        load = Load("Cancun", "cancun")
        blocks = [
            Block(
                header=load.json_to_header(ancestor),
                transactions=(),
                ommers=(),
                withdrawals=(),
            )
            for ancestor in data["witness"]["ancestors"][::-1]
        ]
        pre_state = State(
            _main_trie=Trie[Address, Optional[Account]](
                default=None, secured=True, _data=accounts
            ),
            _storage_tries={
                Address(bytes.fromhex(address)): Trie[Bytes32, U256](
                    default=0, secured=True, _data=storage_dicts[address]
                )
                for address in storage_dicts.keys()
            },
        )
        blockchain = BlockChain(
            blocks=blocks,
            state=pre_state,
            chain_id=U64(data["chainConfig"]["chainId"]),
        )

        # Step 7: for each new block in blocks, create a Block object and apply the state transition
        for block in data["blocks"]:
            transactions = tuple(
                TransactionLoad(normalize_transaction(tx), ForkLoad("cancun")).read()
                for tx in block["transaction"]
            )
            encoded_transactions = tuple(
                (
                    "0x" + encode_transaction(tx).hex()
                    if not isinstance(tx, LegacyTransaction)
                    else {
                        "nonce": hex(tx.nonce),
                        "gasPrice": hex(tx.gas_price),
                        "gas": hex(tx.gas),
                        "to": "0x" + tx.to.hex() if tx.to else "",
                        "value": hex(tx.value),
                        "data": "0x" + tx.data.hex(),
                        "v": hex(tx.v),
                        "r": hex(tx.r),
                        "s": hex(tx.s),
                    }
                )
                for tx in transactions
            )
            block = Block(
                header=load.json_to_header(block["header"]),
                transactions=tuple(
                    (
                        LegacyTransaction(
                            nonce=hex_to_u256(tx["nonce"]),
                            gas_price=hex_to_uint(tx["gasPrice"]),
                            gas=hex_to_uint(tx["gas"]),
                            to=(
                                Address(hex_to_bytes(tx["to"]))
                                if tx["to"]
                                else Bytes0()
                            ),
                            value=hex_to_u256(tx["value"]),
                            data=Bytes(hex_to_bytes(tx["data"])),
                            v=hex_to_u256(tx["v"]),
                            r=hex_to_u256(tx["r"]),
                            s=hex_to_u256(tx["s"]),
                        )
                        if isinstance(tx, dict)
                        else Bytes(hex_to_bytes(tx))
                    )  # Non-legacy txs are hex strings
                    for tx in encoded_transactions
                ),
                ommers=(),
                withdrawals=tuple(
                    Withdrawal(
                        index=U64(int(w["index"], 16)),
                        validator_index=U64(int(w["validatorIndex"], 16)),
                        address=Address(hex_to_bytes(w["address"])),
                        amount=U256(int(w["amount"], 16)),
                    )
                    for w in block["withdrawals"]
                ),
            )

            state_transition(blockchain, block)


if __name__ == "__main__":
    main()
