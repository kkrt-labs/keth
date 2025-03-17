import json

import pytest
from ethereum.cancun.fork_types import Account, Address, encode_account
from ethereum.crypto.hash import keccak256
from ethereum_rlp import rlp
from ethereum_spec_tools.evm_tools.loaders.fixture_loader import Load
from ethereum_types.bytes import Bytes, Bytes32
from ethereum_types.numeric import U256, Uint

from mpt import EMPTY_TRIE_ROOT_HASH, StateTries

# Test constants
TEST_PATH = "./data/1"
SUB_PATH = "inputs"
FILE_NAME = "22009357.json"

# A set of encoded storage keys and values for testing
STORAGE_KEYS: list[Bytes32] = [U256(i).to_be_bytes32() for i in range(1, 6)]
KECCAK_STORAGE_KEYS: list[Bytes32] = [Bytes32(keccak256(key)) for key in STORAGE_KEYS]

STORAGE_VALUES: list[U256] = [U256(i) for i in range(1, 6)]
RLP_STORAGE_VALUES: list[Bytes] = [rlp.encode(value) for value in STORAGE_VALUES]

ADDRESSES: list[Address] = [
    Address(bytes.fromhex(f"000000000000000000000000000000000000000{i:x}"))
    for i in range(1, 6)
]

# Standard test account
TEST_ACCOUNT = Account(
    nonce=Uint(10), balance=U256(1000), code=bytes.fromhex("deadbeef")
)


@pytest.fixture
def test_file_path():
    return f"{TEST_PATH}/{SUB_PATH}/{FILE_NAME}"


@pytest.fixture
def mpt_from_json(test_file_path):
    return StateTries.from_json(test_file_path)


@pytest.fixture
def empty_mpt():
    return StateTries.create_empty()


@pytest.fixture
def test_address(mpt_from_json):
    # Using an address from the JSON file that we know exists
    return Address(list(mpt_from_json.access_list.keys())[0])


@pytest.fixture
def encoded_test_account():
    return encode_account(TEST_ACCOUNT, EMPTY_TRIE_ROOT_HASH)


@pytest.fixture
def mpt_with_account(empty_mpt, encoded_test_account):
    mpt = empty_mpt
    mpt.upsert_account(ADDRESSES[0], encoded_test_account, TEST_ACCOUNT.code)
    mpt.access_list[ADDRESSES[0]] = None
    return mpt


@pytest.fixture
def eels_state():
    with open(f"{TEST_PATH}/eels/{FILE_NAME}", "r") as f:
        fixture = json.load(f)

    load = Load("Cancun", "cancun")
    return load.json_to_state(fixture["pre"])
