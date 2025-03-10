import json

from ethereum.cancun.blocks import Block, Withdrawal
from ethereum.cancun.fork import (
    BlockChain,
    apply_body,
    calculate_excess_blob_gas,
    get_last_256_block_hashes,
)
from ethereum.cancun.fork_types import Address
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


def main():
    pre_state = EthereumState.from_json("data/1/inputs/22009357.json").to_state()
    with open("data/1/inputs/22009357.json", "r") as f:
        data = json.load(f)

    # Step 6: Create the Blockchain and Block objects
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

    # Step 7: for each new block in blocks, create a Block object and apply the state transition
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


if __name__ == "__main__":
    main()
