import json
import logging
from pathlib import Path

import pytest
from eth_abi.abi import encode
from ethereum_types.numeric import U256
from hexbytes import HexBytes
from hypothesis import given, settings
from hypothesis.strategies import integers

from ethereum.crypto.elliptic_curve import SECP256K1N
from ethereum.crypto.hash import keccak256
from src.utils.uint256 import int_to_uint256
from tests.utils.constants import COINBASE, OTHER, OWNER
from tests.utils.data import block
from tests.utils.errors import cairo_error
from tests.utils.helpers import get_internal_storage_key
from tests.utils.models import Block, State
from tests.utils.solidity import get_contract

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

pytestmark = pytest.mark.python_vm


class TestOs:

    @pytest.mark.slow
    def test_erc20_transfer(self, cairo_run):
        erc20 = get_contract("ERC20", "KethToken")
        amount = int(1e18)
        initial_state = {
            erc20.address: {
                "code": list(erc20.bytecode_runtime),
                "storage": {
                    "0x0": encode(["string"], ["KethToken"]),  # name
                    "0x1": encode(["string"], ["KETH"]),  # symbol
                    "0x2": amount,  # totalSupply
                    # balanceOf[OWNER]
                    keccak256(encode(["address", "uint8"], [OWNER, 3])).hex(): amount,
                },
                "balance": 0,
                "nonce": 0,
            },
            OTHER: {
                "code": [],
                "storage": {},
                "balance": int(1e18),
                "nonce": 0,
            },
            OWNER: {
                "code": [],
                "storage": {},
                "balance": int(1e18),
                "nonce": 0,
            },
            COINBASE: {
                "code": [],
                "storage": {},
                "balance": int(1e18),
                "nonce": 0,
            },
        }
        transactions = [
            erc20.transfer(OWNER, amount, signer=OTHER),
            erc20.transfer(OTHER, amount, signer=OWNER),
            erc20.transfer(OTHER, amount, signer=OWNER),
            erc20.approve(OWNER, 2**256 - 1, signer=OTHER),
            erc20.transferFrom(OTHER, OWNER, amount // 3, signer=OWNER),
        ]

        state = cairo_run(
            "test_os",
            block=block(transactions),
            state=State.model_validate(initial_state),
        )
        # TODO: parse the storage keys to check the values properly
        assert (
            sum(
                [
                    v["low"]
                    for k, v in state["accounts"][erc20.address]["storage"].items()
                    if k not in [get_internal_storage_key(i) for i in range(3)]
                ]
            )
            == amount + 2**128 - 1
        )
        # name, symbol, totalSupply, balanceOf[OWNER], allowance[OTHER][OWNER], balanceOf[OTHER]
        assert len(state["accounts"][erc20.address]["storage"].keys()) == 6

    @pytest.mark.skip("Only for debugging")
    @pytest.mark.slow
    @pytest.mark.parametrize("block_number", [21421739])
    def test_eth_block(self, cairo_run, block_number):
        prover_input_path = Path(f"cache/{block_number}_long.json")
        with open(prover_input_path, "r") as f:
            prover_input = json.load(f)

        transactions = [
            tx
            for tx in prover_input["block"]["transactions"]
            if int(tx["type"], 16) != 3
        ]
        logger.info(
            f"Number of non-blob transactions: {len(transactions)} / {len(prover_input['block']['transactions'])}"
        )

        header = prover_input["block"].copy()
        del header["transactions"]
        del header["withdrawals"]
        del header["size"]

        codes = {
            keccak256(HexBytes(code)): HexBytes(code) for code in prover_input["codes"]
        }
        pre_state = {
            account["address"]: {
                "nonce": account.get("nonce", 0),
                "balance": int(account.get("balance", 0), 16),
                "code": list(codes.get(HexBytes(account.get("codeHash", b"")), b"")),
                "storage": {
                    slot["key"]: int(slot["value"], 16)
                    for slot in account.get("storageProof", [])
                },
            }
            for account in prover_input["preStateProofs"]
        }

        post_state = cairo_run(
            "test_os",
            block=Block.model_validate(
                {"block_header": header, "transactions": transactions}
            ),
            state=State.model_validate(pre_state),
        )

        expected = {
            account["address"]: {
                "nonce": account.get("nonce", 0),
                "balance": int(account.get("balance", 0), 16),
                "code": list(codes.get(HexBytes(account.get("codeHash", b"")), b"")),
                "storage": {
                    slot["key"]: int(slot["value"], 16)
                    for slot in account.get("storageProof", [])
                },
            }
            for account in prover_input["postStateProofs"]
        }
        assert post_state == expected

    def test_block_hint(self, cairo_run):
        output = cairo_run("test_block_hint", block=block())
        block_header = block().block_header
        transactions = block().transactions

        assert output == [
            block_header.parent_hash_low,
            block_header.parent_hash_high,
            block_header.uncle_hash_low,
            block_header.uncle_hash_high,
            block_header.coinbase,
            block_header.state_root_low,
            block_header.state_root_high,
            block_header.transactions_trie_low,
            block_header.transactions_trie_high,
            block_header.receipt_trie_low,
            block_header.receipt_trie_high,
            block_header.withdrawals_root_is_some,
            *block_header.withdrawals_root_value,
            *block_header.bloom,
            block_header.difficulty_low,
            block_header.difficulty_high,
            block_header.number,
            block_header.gas_limit,
            block_header.gas_used,
            block_header.timestamp,
            block_header.mix_hash_low,
            block_header.mix_hash_high,
            block_header.nonce,
            block_header.base_fee_per_gas_is_some,
            block_header.base_fee_per_gas_value,
            block_header.blob_gas_used_is_some,
            block_header.blob_gas_used_value,
            block_header.excess_blob_gas_is_some,
            block_header.excess_blob_gas_value,
            block_header.parent_beacon_block_root_is_some,
            *block_header.parent_beacon_block_root_value,
            block_header.requests_root_is_some,
            *block_header.requests_root_value,
            block_header.extra_data_len,
            *[int(byte) for byte in block_header.extra_data],
            len(transactions),
            # First transaction
            *(
                [
                    transactions[0].rlp_len,
                    *[int(byte) for byte in transactions[0].rlp],
                    transactions[0].signature_len,
                    *transactions[0].signature,
                    transactions[0].sender,
                ]
                if len(transactions) > 0
                else []
            ),
        ]

    @given(
        s_value=integers(
            min_value=int(SECP256K1N // U256(2) + U256(1)), max_value=int(SECP256K1N)
        )
    )
    def test_should_raise_on_invalid_s_value(self, cairo_run, s_value):
        initial_state = {
            OWNER: {
                "code": [],
                "storage": {},
                "balance": int(1e18),
                "nonce": 0,
            }
        }
        transactions = [{"to": OTHER, "data": "0x6001", "value": 0, "signer": OWNER}]

        low, high = int_to_uint256(s_value)
        block_to_pass = block(transactions)
        block_to_pass.transactions[0].signature[2] = low
        block_to_pass.transactions[0].signature[3] = high

        with cairo_error("Invalid s value"):
            cairo_run(
                "test_os",
                block=block_to_pass,
                state=State.model_validate(initial_state),
            )

    @pytest.mark.slow
    def test_create_tx_returndata(self, cairo_run):
        initial_state = {
            OWNER: {
                "code": [],
                "storage": {},
                "balance": int(1e18),
                "nonce": 0,
            },
            COINBASE: {
                "code": [],
                "storage": {},
                "balance": 0,
                "nonce": 0,
            },
            "0x32dCAB0EF3FB2De2fce1D2E0799D36239671F04A": {
                "code": [],
                "storage": {},
                "balance": 0,
                "nonce": 0,
            },
        }
        transaction = {
            "to": None,
            "data": "0x604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3",
            "value": 0,
            "signer": OWNER,
        }
        state = cairo_run(
            "test_os",
            block=block([transaction]),
            state=State.model_validate(initial_state),
        )

        assert (
            bytes.fromhex(
                "7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3"
            )
            == state["accounts"]["0x32dCAB0EF3FB2De2fce1D2E0799D36239671F04A"]["code"]
        )

    @pytest.mark.slow
    @settings(max_examples=1)  # for max_examples=2, it takes 1773.25s in local
    @given(nonce=integers(min_value=2**64, max_value=2**248 - 1))
    def test_should_raise_when_nonce_is_greater_u64(self, cairo_run, nonce):
        initial_state = {
            OWNER: {
                "code": [],
                "storage": {},
                "balance": int(1e18),
                "nonce": nonce,
            },
            OTHER: {
                "code": [],
                "storage": {},
                "balance": int(1e18),
                "nonce": 0,
            },
            COINBASE: {
                "code": [],
                "storage": {},
                "balance": 0,
                "nonce": 0,
            },
        }
        transaction = {
            "to": OTHER,
            "data": "",
            "value": 0,
            "signer": OWNER,
        }

        with cairo_error("Invalid nonce"):
            cairo_run(
                "test_os",
                block=block([transaction], nonces={OWNER: nonce}),
                state=State.model_validate(initial_state),
            )
