import json

from ethereum.cancun.blocks import Block, Withdrawal
from ethereum.cancun.fork import (
    BlockChain,
    apply_body,
    calculate_excess_blob_gas,
    get_last_256_block_hashes,
)
from ethereum.cancun.fork_types import Address
from ethereum.cancun.state import State, copy_trie
from ethereum.cancun.transactions import LegacyTransaction, encode_transaction
from ethereum.utils.hexadecimal import hex_to_bytes, hex_to_u256, hex_to_uint
from ethereum_spec_tools.evm_tools.loaders.fixture_loader import Load
from ethereum_spec_tools.evm_tools.loaders.fork_loader import ForkLoad
from ethereum_spec_tools.evm_tools.loaders.transaction_loader import TransactionLoad
from ethereum_types.bytes import Bytes, Bytes0
from ethereum_types.numeric import (
    U64,
    U256,
)
from scripts.zkpi_to_eels import normalize_transaction

from mpt import EthereumState
from mpt.state_diff import StateDiff


def main():
    ethereum_state = EthereumState.from_json("data/1/inputs/22009357.json")
    pre_state = ethereum_state.to_state()

    # We make a deep copy of the State to be able to compute State Diffs
    pre_state_copy = State(
        _main_trie=copy_trie(pre_state._main_trie),
        _storage_tries={k: copy_trie(v) for k, v in pre_state._storage_tries.items()},
    )

    with open("data/1/inputs/22009357.json", "r") as f:
        data = json.load(f)

    # Create the Blockchain and Block objects
    load = Load("Cancun", "cancun")
    blocks = [
        Block(
            header=load.json_to_header(ancestor),
            transactions=(),
            ommers=(),
            withdrawals=(),
        )
        for ancestor in data["witness"]["ancestors"][::-1]
    ]
    blockchain = BlockChain(
        blocks=blocks,
        state=pre_state,
        chain_id=U64(data["chainConfig"]["chainId"]),
    )

    # For each new block in blocks, create a Block object and apply the state transition
    for block in data["blocks"]:
        transactions = tuple(
            TransactionLoad(normalize_transaction(tx), ForkLoad("cancun")).read()
            for tx in block["transaction"]
        )
        encoded_transactions = tuple(
            (
                "0x" + encode_transaction(tx).hex()
                if not isinstance(tx, LegacyTransaction)
                else {
                    "nonce": hex(tx.nonce),
                    "gasPrice": hex(tx.gas_price),
                    "gas": hex(tx.gas),
                    "to": "0x" + tx.to.hex() if tx.to else "",
                    "value": hex(tx.value),
                    "data": "0x" + tx.data.hex(),
                    "v": hex(tx.v),
                    "r": hex(tx.r),
                    "s": hex(tx.s),
                }
            )
            for tx in transactions
        )
        block = Block(
            header=load.json_to_header(block["header"]),
            transactions=tuple(
                (
                    LegacyTransaction(
                        nonce=hex_to_u256(tx["nonce"]),
                        gas_price=hex_to_uint(tx["gasPrice"]),
                        gas=hex_to_uint(tx["gas"]),
                        to=(Address(hex_to_bytes(tx["to"])) if tx["to"] else Bytes0()),
                        value=hex_to_u256(tx["value"]),
                        data=Bytes(hex_to_bytes(tx["data"])),
                        v=hex_to_u256(tx["v"]),
                        r=hex_to_u256(tx["r"]),
                        s=hex_to_u256(tx["s"]),
                    )
                    if isinstance(tx, dict)
                    else Bytes(hex_to_bytes(tx))
                )  # Non-legacy txs are hex strings
                for tx in encoded_transactions
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

        _output = apply_body(
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

        print("0x" + _output.state_root.hex())

        post_state = blockchain.state
        state_diff = StateDiff.from_pre_post(pre_state_copy, post_state)
        ethereum_state.update_from_state_diff(state_diff)
        print("0x" + ethereum_state.state_root.hex())


if __name__ == "__main__":
    main()
