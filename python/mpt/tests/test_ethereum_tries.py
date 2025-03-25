import logging
from pathlib import Path

import pytest
from ethereum.cancun.blocks import Block, Header, Withdrawal
from ethereum.cancun.fork import (
    BlockChain,
    apply_body,
    calculate_excess_blob_gas,
    get_last_256_block_hashes,
    state_transition,
)
from ethereum.cancun.fork_types import Address
from ethereum.cancun.transactions import LegacyTransaction, encode_transaction
from ethereum.crypto.hash import Hash32, keccak256
from ethereum.utils.hexadecimal import hex_to_bytes
from ethereum_spec_tools.evm_tools.loaders.fixture_loader import Load
from ethereum_spec_tools.evm_tools.loaders.fork_loader import ForkLoad
from ethereum_spec_tools.evm_tools.loaders.transaction_loader import TransactionLoad
from ethereum_types.bytes import Bytes, Bytes32
from ethereum_types.numeric import U64, U256
from scripts.zkpi_to_eels import normalize_transaction

from mpt import EthereumTries
from mpt.utils import decode_node

logger = logging.getLogger(__name__)


@pytest.fixture
def ethereum_tries(zkpi):
    return EthereumTries.from_data(zkpi)


@pytest.mark.parametrize(
    "data_path", [Path("test_data/22079718.json")], scope="session"
)
class TestEthereumTries:
    def test_preimages(self, ethereum_tries, zkpi):
        access_list = zkpi["accessList"]
        assert len(access_list) == len(ethereum_tries.address_preimages.keys())
        for access in access_list:
            address = Address.fromhex(access["address"][2:])
            address_hash = keccak256(address)
            for storage_key in access["storageKeys"] or []:
                key = Bytes32.fromhex(storage_key[2:])
                key_hash = keccak256(key)
                assert ethereum_tries.address_preimages[address_hash] == address
                assert ethereum_tries.storage_key_preimages[key_hash] == key

    def test_state_root(self, ethereum_tries, zkpi):
        assert ethereum_tries.state_root == Hash32.fromhex(
            zkpi["witness"]["ancestors"][0]["stateRoot"][2:]
        )

    def test_nodes(self, ethereum_tries, zkpi):
        nodes = zkpi["witness"]["state"]
        for node in nodes:
            node = Bytes.fromhex(node[2:])
            node_hash = keccak256(node)
            assert ethereum_tries.nodes[node_hash] == decode_node(node)

    def test_codes(self, ethereum_tries, zkpi):
        codes = zkpi["witness"]["codes"]
        for code in codes:
            code = Bytes.fromhex(code[2:])
            code_hash = keccak256(code)
            assert ethereum_tries.codes[code_hash] == code

    def test_to_state(self, zkpi, ethereum_tries: EthereumTries):

        load = Load("Cancun", "cancun")
        # Create blockchain from ancestors
        blocks = [
            Block(
                header=load.json_to_header(ancestor),
                transactions=(),
                ommers=(),
                withdrawals=(),
            )
            for ancestor in zkpi["witness"]["ancestors"][::-1]
        ]
        blockchain = BlockChain(
            blocks=blocks,
            state=ethereum_tries.to_state(),
            chain_id=U64(zkpi["chainConfig"]["chainId"]),
        )

        if len(zkpi["blocks"]) != 1:
            raise ValueError("Only one block is supported")

        block = zkpi["blocks"][0]
        transactions = tuple(
            TransactionLoad(normalize_transaction(tx), ForkLoad("cancun")).read()
            for tx in block["transaction"]
        )

        # Create new block to process
        block = Block(
            header=load.json_to_header(block["header"]),
            transactions=tuple(
                (tx if isinstance(tx, LegacyTransaction) else encode_transaction(tx))
                for tx in transactions
            ),
            ommers=(),
            withdrawals=tuple(
                Withdrawal(
                    index=U64(int(w["index"], 16)),
                    validator_index=U64(int(w["validatorIndex"], 16)),
                    address=Address(hex_to_bytes(w["address"])),
                    amount=U256(int(w["amount"], 16)),
                )
                for w in block["withdrawals"]
            ),
        )

        # TODO: Need to patch state_root, remove when we have a working partial MPT
        output = apply_body(
            state=blockchain.state,
            block_hashes=get_last_256_block_hashes(blockchain),
            coinbase=block.header.coinbase,
            block_number=block.header.number,
            base_fee_per_gas=block.header.base_fee_per_gas,
            block_gas_limit=block.header.gas_limit,
            block_time=block.header.timestamp,
            prev_randao=block.header.prev_randao,
            transactions=block.transactions,
            chain_id=blockchain.chain_id,
            withdrawals=block.withdrawals,
            parent_beacon_block_root=block.header.parent_beacon_block_root,
            excess_blob_gas=calculate_excess_blob_gas(blockchain.blocks[-1].header),
        )
        # We recreate the block to apply with the updated state root, which is a partial state root
        block = Block(
            header=Header(
                parent_hash=block.header.parent_hash,
                ommers_hash=block.header.ommers_hash,
                coinbase=block.header.coinbase,
                state_root=output.state_root,  # Updated state root
                transactions_root=block.header.transactions_root,
                receipt_root=block.header.receipt_root,
                bloom=block.header.bloom,
                difficulty=block.header.difficulty,
                number=block.header.number,
                gas_limit=block.header.gas_limit,
                gas_used=block.header.gas_used,
                timestamp=block.header.timestamp,
                extra_data=block.header.extra_data,
                prev_randao=block.header.prev_randao,
                nonce=block.header.nonce,
                base_fee_per_gas=block.header.base_fee_per_gas,
                withdrawals_root=block.header.withdrawals_root,
                blob_gas_used=block.header.blob_gas_used,
                excess_blob_gas=block.header.excess_blob_gas,
                parent_beacon_block_root=block.header.parent_beacon_block_root,
            ),
            transactions=block.transactions,
            ommers=(),
            withdrawals=block.withdrawals,
        )
        # We recreate the chain with a new pre-state
        chain = BlockChain(
            blocks=blockchain.blocks,
            state=ethereum_tries.to_state(),
            chain_id=blockchain.chain_id,
        )
        # TODO: end of tmp section
        state_transition(chain, block)
