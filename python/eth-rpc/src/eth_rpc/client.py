import logging
import os
from dataclasses import dataclass
from typing import List, Union

import requests
from dotenv import load_dotenv
from ethereum.cancun.fork_types import Address
from ethereum.crypto.hash import Hash32, keccak256
from ethereum_types.bytes import Bytes, Bytes32
from ethereum_types.numeric import U64, U256

logger = logging.getLogger(__name__)


@dataclass
class StorageProof:
    """
    Storage proof for a given key and value.
    """

    key: Bytes32
    value: U256
    proof: List[Bytes]


@dataclass
class AccountProof:
    """
    Account proof for a given address and block number.

    Attributes:
        address: The Ethereum address for which the proof is generated
        account_proof: List of RLP-encoded MPT nodes to prove the inclusion of the account in the world state
        balance: Account balance in wei
        code_hash: Hash of the account's code
        nonce: Number of transactions sent from this address
        storage_root: Root hash of the account's storage trie
        storage_proof: List of storage proofs for requested storage keys
    """

    address: Address
    account_proof: List[Bytes]
    balance: U256
    code_hash: Hash32
    nonce: U64
    storage_root: Hash32
    storage_proof: List[StorageProof]


@dataclass
class EthereumRPC:
    url: str

    @classmethod
    def from_env(cls) -> "EthereumRPC":
        load_dotenv()
        if not os.getenv("CHAIN_RPC_URL"):
            raise ValueError("CHAIN_RPC_URL is not set")
        return cls(os.getenv("CHAIN_RPC_URL"))

    def get_proof(
        self,
        address: Address,
        block_number: Union[U64, str] = "latest",
        storage_keys: List[Bytes32] = [],
    ) -> AccountProof:
        payload = {
            "jsonrpc": "2.0",
            "method": "eth_getProof",
            "params": [
                "0x" + address.hex(),
                ["0x" + storage_key.hex() for storage_key in storage_keys],
                (
                    hex(block_number)
                    if not isinstance(block_number, str)
                    else block_number
                ),
            ],
        }
        response = requests.post(self.url, json=payload)
        result = response.json()["result"]
        return AccountProof(
            address=Address.fromhex(result["address"][2:]),
            account_proof=[
                Bytes.fromhex(proof[2:]) for proof in result["accountProof"]
            ],
            balance=U256(int(result["balance"], 16)),
            code_hash=Hash32.fromhex(result["codeHash"][2:]),
            nonce=U64(int(result["nonce"], 16)),
            storage_root=Hash32.fromhex(result["storageRoot"][2:]),
            storage_proof=[
                StorageProof(
                    key=Bytes32.fromhex(proof["key"][2:]),
                    value=U256(int(proof["value"], 16)),
                    proof=[
                        Bytes.fromhex(proof_item[2:]) for proof_item in proof["proof"]
                    ],
                )
                for proof in result["storageProof"]
            ],
        )

    def get_code(
        self, address: Address, block_number: Union[U64, str] = "latest"
    ) -> Bytes:
        logger.debug(f"Getting code for 0x{address.hex()}")
        payload = {
            "jsonrpc": "2.0",
            "method": "eth_getCode",
            "params": [
                "0x" + address.hex(),
                (
                    hex(block_number)
                    if not isinstance(block_number, str)
                    else block_number
                ),
            ],
        }
        response = requests.post(self.url, json=payload)

        result = Bytes.fromhex(response.json()["result"][2:])
        logger.debug(f"Code Hash for 0x{address.hex()} is {keccak256(result).hex()}")
        return result
