import json
from pathlib import Path

import pytest
from ethereum.cancun.fork_types import Address
from ethereum.crypto.hash import Hash32, keccak256
from ethereum_types.bytes import Bytes, Bytes32

from mpt import EthereumTries
from mpt.utils import decode_node


@pytest.fixture
def zkpi(path: Path):
    with open(path, "r") as f:
        data = json.load(f)
    return data


@pytest.mark.parametrize("path", [Path("python/mpt/tests/data/22079718.json")])
class TestEthereumTries:
    def test_from_json(self, zkpi):
        ethereum_tries = EthereumTries.from_data(zkpi)
        assert ethereum_tries is not None

    def test_preimages(self, zkpi):
        ethereum_tries = EthereumTries.from_data(zkpi)
        access_list = zkpi["accessList"]
        for access in access_list:
            address = Address.fromhex(access["address"][2:])
            address_hash = keccak256(address)
            for storage_key in access["storageKeys"] or []:
                key = Bytes32.fromhex(storage_key[2:])
                key_hash = keccak256(key)
                assert ethereum_tries.address_preimages[address_hash] == address
                assert ethereum_tries.storage_key_preimages[key_hash] == key

    def test_state_root(self, zkpi):
        ethereum_tries = EthereumTries.from_data(zkpi)
        assert ethereum_tries.state_root == Hash32.fromhex(
            zkpi["witness"]["ancestors"][0]["stateRoot"][2:]
        )

    def test_nodes(self, zkpi):
        ethereum_tries = EthereumTries.from_data(zkpi)
        nodes = zkpi["witness"]["state"]
        for node in nodes:
            node = Bytes.fromhex(node[2:])
            node_hash = keccak256(node)
            assert ethereum_tries.nodes[node_hash] == decode_node(node)

    def test_codes(self, zkpi):
        ethereum_tries = EthereumTries.from_data(zkpi)
        codes = zkpi["witness"]["codes"]
        for code in codes:
            code = Bytes.fromhex(code[2:])
            code_hash = keccak256(code)
            assert ethereum_tries.codes[code_hash] == code
