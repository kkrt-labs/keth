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
        pre_nodes = {
            keccak256(bytes.fromhex(node[2:])): decode_node(bytes.fromhex(node[2:]))
            for node in data["witness"]["state"]
        }

        pre_state_root = Hash32.fromhex(
            data["witness"]["ancestors"][0]["stateRoot"][2:]
        )
        if pre_state_root not in pre_nodes:
            raise ValueError(f"State root not found in nodes: {pre_state_root}")

        codes = {
            keccak256(Bytes.fromhex(code[2:])): Bytes.fromhex(code[2:])
            for code in data["witness"]["codes"]
        }

        # TODO: modify zk-pig to provide directly address preimages

        # We need address & storage key preimages to get an address and storage key given a trie path, which is the hash of address and storage_key for the Ethereum tries
        # Because State object from `ethereum` package maps Addresses to Accounts, and Storage Keys to Storage Values.
        # See 👇
        # class State:
        #     _main_trie: Trie[Address, Optional[Account]]
        #     _storage_tries: Dict[Address, Trie[Bytes32, U256]]
        # ...
        access_list = (
            data["accessList"] if "accessList" in data else data["extra"]["accessList"]
        )
        address_preimages = {
            keccak256(Bytes20.fromhex(preimage["address"][2:])): Address.fromhex(
                preimage["address"][2:]
            )
            for preimage in access_list
        }
        storage_key_preimages = {
            keccak256(Bytes32.fromhex(storage_key[2:])): Bytes32.fromhex(
                storage_key[2:]
            )
            for access in access_list
            for storage_key in access["storageKeys"] or []
        }

        return EthereumTries(
            nodes=pre_nodes,
            codes=codes,
            address_preimages=address_preimages,
            storage_key_preimages=storage_key_preimages,
            state_root=pre_state_root,
        )


@dataclass
class EthereumTrieTransitionDB:
    nodes: Mapping[Hash32, InternalNode]
    codes: Mapping[Hash32, Bytes]
    address_preimages: Mapping[Hash32, Address]
    storage_key_preimages: Mapping[Hash32, Bytes32]
    pre_state_root: Hash32
    post_state_root: Hash32

    @staticmethod
    def from_pre_and_post_tries(pre_trie: EthereumTries, post_trie: EthereumTries):
        return EthereumTrieTransitionDB(
            nodes={**pre_trie.nodes, **post_trie.nodes},
            codes={**pre_trie.codes, **post_trie.codes},
            address_preimages={
                **pre_trie.address_preimages,
                **post_trie.address_preimages,
            },
            storage_key_preimages={
                **pre_trie.storage_key_preimages,
                **post_trie.storage_key_preimages,
            },
            pre_state_root=pre_trie.state_root,
            post_state_root=post_trie.state_root,
        )

    @staticmethod
    def from_json(path: Path):
        with open(path, "r") as f:
            data = json.load(f)
        return EthereumTrieTransitionDB.from_data(data)

    @staticmethod
    def from_data(data: Dict[str, Any]):
        pre_nodes = {
            keccak256(bytes.fromhex(node[2:])): decode_node(bytes.fromhex(node[2:]))
            for node in data["witness"]["state"]
        }

        pre_state_root = Hash32.fromhex(
            data["witness"]["ancestors"][0]["stateRoot"][2:]
        )
        if pre_state_root not in pre_nodes:
            raise ValueError(f"State root not found in nodes: {pre_state_root}")

        post_nodes = {
            keccak256(bytes.fromhex(node[2:])): decode_node(bytes.fromhex(node[2:]))
            for node in data["extra"]["committed"]
        }

        post_state_root = Hash32.fromhex(data["blocks"][0]["header"]["stateRoot"][2:])
        if post_state_root not in post_nodes:
            raise ValueError(f"State root not found in nodes: {post_state_root}")

        nodes = {**pre_nodes, **post_nodes}

        codes = {
            keccak256(Bytes.fromhex(code[2:])): Bytes.fromhex(code[2:])
            for code in data["witness"]["codes"]
        }

        # TODO: modify zk-pig to provide directly address preimages

        # We need address & storage key preimages to get an address and storage key given a trie path, which is the hash of address and storage_key for the Ethereum tries
        # Because State object from `ethereum` package maps Addresses to Accounts, and Storage Keys to Storage Values.
        # See 👇
        # class State:
        #     _main_trie: Trie[Address, Optional[Account]]
        #     _storage_tries: Dict[Address, Trie[Bytes32, U256]]
        # ...
        access_list = (
            data["accessList"] if "accessList" in data else data["extra"]["accessList"]
        )
        address_preimages = {
            keccak256(Bytes20.fromhex(preimage["address"][2:])): Address.fromhex(
                preimage["address"][2:]
            )
            for preimage in access_list
        }
        storage_key_preimages = {
            keccak256(Bytes32.fromhex(storage_key[2:])): Bytes32.fromhex(
                storage_key[2:]
            )
            for access in access_list
            for storage_key in access["storageKeys"] or []
        }

        return EthereumTrieTransitionDB(
            nodes=nodes,
            codes=codes,
            address_preimages=address_preimages,
            storage_key_preimages=storage_key_preimages,
            pre_state_root=pre_state_root,
            post_state_root=post_state_root,
        )
