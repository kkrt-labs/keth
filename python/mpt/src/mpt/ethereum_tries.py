import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Mapping

from ethereum.cancun.fork_types import Address
from ethereum.cancun.trie import InternalNode
from ethereum.crypto.hash import Hash32, keccak256
from ethereum_types.bytes import Bytes, Bytes20, Bytes32

from mpt.utils import decode_node


@dataclass
class EthereumTries:
    nodes: Mapping[Hash32, InternalNode]
    codes: Mapping[Hash32, Bytes]
    address_preimages: Mapping[Hash32, Address]
    storage_key_preimages: Mapping[Hash32, Bytes32]
    state_root: Hash32

    @staticmethod
    def from_json(path: Path):
        with open(path, "r") as f:
            data = json.load(f)
        return EthereumTries.from_data(data)

    @staticmethod
    def from_data(data: Dict[str, Any]):
        nodes = {
            keccak256(bytes.fromhex(node[2:])): decode_node(bytes.fromhex(node[2:]))
            for node in data["witness"]["state"]
        }

        state_root = Hash32.fromhex(data["witness"]["ancestors"][0]["stateRoot"][2:])
        if state_root not in nodes:
            raise ValueError(f"State root not found in nodes: {state_root}")

        codes = {
            keccak256(Bytes.fromhex(code[2:])): Bytes.fromhex(code[2:])
            for code in data["witness"]["codes"]
        }

        # TODO: modify zk-pig to provide directly address & storage key preimages
        # We need address preimages to get an address given a trie path, which is the keccak(address) for the Ethereum state trie
        # Because State object from `ethereum` package maps Addresses to Accounts.
        address_preimages = {
            keccak256(Bytes20.fromhex(preimage["address"][2:])): Address.fromhex(
                preimage["address"][2:]
            )
            for preimage in data["accessList"]
        }

        # We need storage key preimages to get a storage key given a trie path, which is the keccak(storage_key) for the Ethereum state trie
        # Because State object from `ethereum` package maps Addresses to Storage Tries, which map Storage Keys to Storage Values.
        storage_key_preimages = {
            keccak256(Bytes32.fromhex(storage_key[2:])): Bytes32.fromhex(
                storage_key[2:]
            )
            for access in data["accessList"]
            for storage_key in access["storageKeys"] or []
        }

        return EthereumTries(
            nodes=nodes,
            codes=codes,
            address_preimages=address_preimages,
            storage_key_preimages=storage_key_preimages,
            state_root=state_root,
        )
