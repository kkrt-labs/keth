from collections import defaultdict
from pathlib import Path
from typing import List, Optional, Tuple, Union

import pytest
from ethereum.cancun import vm
from ethereum.cancun.blocks import Block, Log, Receipt, Withdrawal
from ethereum.cancun.fork import (
    BEACON_ROOTS_ADDRESS,
    SYSTEM_ADDRESS,
    SYSTEM_TRANSACTION_GAS,
    get_last_256_block_hashes,
)
from ethereum.cancun.fork_types import Address, Root
from ethereum.cancun.state import (
    State,
    TransientStorage,
    destroy_touched_empty_accounts,
    get_account,
)
from ethereum.cancun.transactions import (
    LegacyTransaction,
)
from ethereum.cancun.trie import Trie
from ethereum.cancun.vm import Message
from ethereum.cancun.vm.gas import (
    calculate_excess_blob_gas,
)
from ethereum.cancun.vm.interpreter import process_message_call
from ethereum.crypto.hash import Hash32
from ethereum_types.bytes import Bytes, Bytes32
from ethereum_types.numeric import U64, U256, Uint

from utils.fixture_loader import load_zkpi_fixture

pytestmark = pytest.mark.cairo_file(
    f"{Path().cwd()}/cairo/tests/ethereum/cancun/keth/test_body.cairo"
)


@pytest.fixture
def program_input(zkpi_path):
    return load_zkpi_fixture(zkpi_path)


class TestMain:
    @pytest.mark.parametrize(
        "zkpi_path",
        [Path("test_data/22188088.json")],
    )
    @pytest.mark.slow
    def test_body(self, cairo_run, zkpi_path, program_input):
        chain = program_input["blockchain"]
        parent_header = chain.blocks[-1].header
        excess_blob_gas = calculate_excess_blob_gas(parent_header)
        block = program_input["block"]

        body_program_input = init_apply_body(
            block,
            chain.state,
            get_last_256_block_hashes(chain),
            block.header.coinbase,
            block.header.number,
            block.header.base_fee_per_gas,
            block.header.gas_limit,
            block.header.timestamp,
            block.header.prev_randao,
            block.transactions,
            chain.chain_id,
            block.withdrawals,
            block.header.parent_beacon_block_root,
            excess_blob_gas,
        )

        program_input = {
            **body_program_input,
            **program_input,
            "start_index": 0,
            "len": len(block.transactions),
        }

        cairo_run("test_body", verify_squashed_dicts=True, **program_input)


def init_apply_body(
    block: Block,
    state: State,
    block_hashes: List[Hash32],
    coinbase: Address,
    block_number: Uint,
    base_fee_per_gas: Uint,
    block_gas_limit: Uint,
    block_time: U256,
    prev_randao: Bytes32,
    transactions: Tuple[Union[LegacyTransaction, Bytes], ...],
    chain_id: U64,
    withdrawals: Tuple[Withdrawal, ...],
    parent_beacon_block_root: Root,
    excess_blob_gas: U64,
):
    blob_gas_used = Uint(0)
    gas_available = block_gas_limit
    transactions_trie: Trie[Bytes, Optional[Union[Bytes, LegacyTransaction]]] = Trie(
        secured=False, default=None, _data=defaultdict(lambda: None)
    )
    receipts_trie: Trie[Bytes, Optional[Union[Bytes, Receipt]]] = Trie(
        secured=False, default=None, _data=defaultdict(lambda: None)
    )
    Trie(secured=False, default=None, _data=defaultdict(lambda: None))
    block_logs: Tuple[Log, ...] = ()

    beacon_block_roots_contract_code = get_account(state, BEACON_ROOTS_ADDRESS).code

    system_tx_message = Message(
        caller=SYSTEM_ADDRESS,
        target=BEACON_ROOTS_ADDRESS,
        gas=SYSTEM_TRANSACTION_GAS,
        value=U256(0),
        data=parent_beacon_block_root,
        code=beacon_block_roots_contract_code,
        depth=Uint(0),
        current_target=BEACON_ROOTS_ADDRESS,
        code_address=BEACON_ROOTS_ADDRESS,
        should_transfer_value=False,
        is_static=False,
        accessed_addresses=set(),
        accessed_storage_keys=set(),
        parent_evm=None,
    )

    system_tx_env = vm.Environment(
        caller=SYSTEM_ADDRESS,
        origin=SYSTEM_ADDRESS,
        block_hashes=block_hashes,
        coinbase=coinbase,
        number=block_number,
        gas_limit=block_gas_limit,
        base_fee_per_gas=base_fee_per_gas,
        gas_price=base_fee_per_gas,
        time=block_time,
        prev_randao=prev_randao,
        state=state,
        chain_id=chain_id,
        traces=[],
        excess_blob_gas=excess_blob_gas,
        blob_versioned_hashes=(),
        transient_storage=TransientStorage(),
    )

    system_tx_output = process_message_call(system_tx_message, system_tx_env)

    destroy_touched_empty_accounts(
        system_tx_env.state, system_tx_output.touched_accounts
    )

    program_input = {
        "block_header": block.header,
        "block_transactions": block.transactions,
        "state": state,
        "transactions_trie": transactions_trie,
        "receipts_trie": receipts_trie,
        "block_logs": block_logs,
        "block_hashes": block_hashes,
        "gas_available": gas_available,
        "chain_id": chain_id,
        "base_fee_per_gas": base_fee_per_gas,
        "blob_gas_used": blob_gas_used,
        "excess_blob_gas": excess_blob_gas,
    }

    return program_input
