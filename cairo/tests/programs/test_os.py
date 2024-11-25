from eth_abi import encode
from eth_keys import keys

from ethereum.crypto.hash import keccak256
from tests.utils.constants import COINBASE
from tests.utils.data import block
from tests.utils.models import Block, State
from tests.utils.solidity import get_contract

OWNER = keys.PrivateKey(b"1" * 32)
OTHER = keys.PrivateKey(b"2" * 32)


class TestOs:

    def test_os(self, cairo_run, block, state):
        cairo_run("test_os", block=block(), state=state())

    def test_erc20_transfer(self, cairo_run):
        erc20 = get_contract("ERC20", "KethToken")
        amount = int(1e18)
        initial_state = {
            erc20.address: {
                "code": list(erc20.bytecode_runtime),
                "storage": {
                    "0x2": 18,
                    "0x3": amount,
                    keccak256(
                        encode(
                            ["address", "uint8"],
                            [OWNER.public_key.to_checksum_address(), 3],
                        )
                    ).hex(): amount,
                },
                "balance": 0,
                "nonce": 0,
            },
            OTHER.public_key.to_checksum_address(): {
                "code": [],
                "storage": {},
                "balance": int(1e18),
                "nonce": 0,
            },
            OWNER.public_key.to_checksum_address(): {
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
            erc20.transfer(
                OWNER.public_key.to_checksum_address(), amount, signer=OTHER
            ),
            erc20.transfer(
                OTHER.public_key.to_checksum_address(), amount, signer=OWNER
            ),
            erc20.transfer(
                OTHER.public_key.to_checksum_address(), amount, signer=OWNER
            ),
            erc20.approve(OWNER.public_key.to_checksum_address(), amount, signer=OTHER),
            erc20.transferFrom(
                OTHER.public_key.to_checksum_address(),
                OWNER.public_key.to_checksum_address(),
                amount,
                signer=OWNER,
            ),
        ]

        cairo_run(
            "test_os",
            block=block(transactions),
            state=State.model_validate(initial_state),
        )

    def test_block_hint(self, cairo_run, block: Block):
        output = cairo_run("test_block_hint", block=block)
        block_header = block.block_header

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
