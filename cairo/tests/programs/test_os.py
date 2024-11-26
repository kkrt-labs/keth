from eth_abi import encode

from ethereum.crypto.hash import keccak256
from tests.utils.constants import COINBASE, OTHER, OWNER
from tests.utils.data import block
from tests.utils.models import State
from tests.utils.solidity import get_contract


class TestOs:

    def test_os(self, cairo_run, state):
        cairo_run("test_os", block=block(), state=state())

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
                [v["low"] for v in state["accounts"][erc20.address]["storage"].values()]
            )
            == amount + 2**128 - 1
        )
        assert len(state["accounts"][erc20.address]["storage"].keys()) == 3

    def test_block_hint(self, cairo_run):
        output = cairo_run("test_block_hint", block=block())
        block_header = block().block_header

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
            len(block.transactions),
            # First transaction
            *(
                [
                    block.transactions[0].rlp_len,
                    *[int(byte) for byte in block.transactions[0].rlp],
                    block.transactions[0].signature_len,
                    *block.transactions[0].signature,
                    block.transactions[0].sender,
                ]
                if len(block.transactions) > 0
                else []
            ),
        ]
