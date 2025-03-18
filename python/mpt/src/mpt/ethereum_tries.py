import json
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping

from ethereum.cancun.fork_types import Address
from ethereum.cancun.trie import InternalNode
from ethereum.crypto.hash import Hash32, keccak256
from ethereum_types.bytes import Bytes, Bytes32
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
        nodes = {
            keccak256(bytes.fromhex(node[2:])): decode_node(bytes.fromhex(node[2:]))
            for node in data["nodes"]
        }
        assert bytes.fromhex(data["stateRoot"][2:]) in nodes
        return EthereumTries(
            nodes=nodes,
            codes={
                keccak256(bytes.fromhex(code[2:])): Bytes.fromhex(code[2:])
                for code in data["codes"]
            },
            address_preimages={
                keccak256(bytes.fromhex(preimage["address"][2:])): Address.fromhex(
                    preimage["address"][2:]
                )
                for preimage in data["accessList"]
            },
            storage_key_preimages={
                keccak256(bytes.fromhex(storage_key[2:])): Bytes32.fromhex(
                    storage_key[2:]
                )
                for access in data["accessList"]
                for storage_key in access["storageKeys"]
            },
            state_root=Hash32.fromhex(data["stateRoot"]),
        )
