import json

from ethereum.cancun.fork_types import Account, Address, encode_account
from ethereum.crypto.hash import keccak256
from ethereum_spec_tools.evm_tools.loaders.fixture_loader import Load
from ethereum_types.numeric import U256, Uint
from python.mpt.src.mpt import EMPTY_TRIE_ROOT_HASH, EthereumState


class TestEthereumState:
    def test_from_json(self):
        mpt = EthereumState.from_json("data/1/inputs/22009357.json")
        assert mpt is not None

    def test_get(self):
        mpt = EthereumState.from_json("data/1/inputs/22009357.json")

        random_address = list(mpt.access_list.keys())[0]

        key = keccak256(random_address)

        result = mpt.get(key)

        assert result is not None

    def test_get_account(self):
        mpt = EthereumState.from_json("data/1/inputs/22009357.json")

        account = mpt.get_account(
            Address(bytes.fromhex("0000000000000000000000000000000000000001"))
        )

        assert account.nonce == Uint(0)
        # Some people sent money to precompile 0x01 🤷‍♂️
        assert account.balance > U256(0)
        assert account.code == b""

    def test_delete(self):
        mpt = EthereumState.from_json("data/1/inputs/22009357.json")

        assert (
            mpt.get(
                keccak256(
                    Address(bytes.fromhex("0000000000000000000000000000000000000001"))
                )
            )
            is not None
        )

        mpt.delete(
            keccak256(
                Address(bytes.fromhex("0000000000000000000000000000000000000001"))
            )
        )

        assert (
            mpt.get(
                keccak256(
                    Address(bytes.fromhex("0000000000000000000000000000000000000001"))
                )
            )
            is None
        )

    def test_upsert(self):
        mpt = EthereumState.from_json("data/1/inputs/22009357.json")

        account = Account(
            nonce=Uint(10), balance=U256(1000), code=bytes.fromhex("deadbeef")
        )
        encoded_account = encode_account(account, EMPTY_TRIE_ROOT_HASH)

        mpt.upsert(
            keccak256(
                # Address from data/1/inputs/22009357.json::AccessList[0]
                # TODO: Use an address from the access list
                Address(bytes.fromhex("30325619135da691a6932b13a19b8928527f8456"))
            ),
            encoded_account,
        )

        assert (
            mpt.get(
                keccak256(
                    # Address from data/1/inputs/22009357.json::AccessList[0]
                    # TODO: Use an address from the access list
                    Address(bytes.fromhex("30325619135da691a6932b13a19b8928527f8456"))
                )
            )
            == encoded_account
        )

    def test_to_state(self):
        mpt = EthereumState.from_json("data/1/inputs/22009357.json")

        state = mpt.to_state()

        assert state is not None

    def test_to_state_with_diff_testing(self):
        mpt = EthereumState.from_json("data/1/inputs/22009357.json")

        with open("data/1/eels/22009357.json", "r") as f:
            fixture = json.load(f)

        state = mpt.to_state()

        load = Load("Cancun", "cancun")
        expected_state = load.json_to_state(fixture["pre"])

        assert state == expected_state
