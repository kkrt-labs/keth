from collections import defaultdict

from eth_account import Account

from tests.utils.constants import (
    BASE_FEE_PER_GAS,
    COINBASE,
    TRANSACTION_GAS_LIMIT,
    signers,
)
from tests.utils.models import Block


def block(transactions=None):
    nonces = defaultdict(int)
    transactions = transactions or []

    for transaction in transactions:
        signer = transaction.pop("signer")
        transaction["gas"] = TRANSACTION_GAS_LIMIT
        transaction["gasPrice"] = BASE_FEE_PER_GAS
        transaction["nonce"] = nonces[signer]
        nonces[signer] += 1
        signed_tx = Account.sign_transaction(transaction, signers[signer])
        transaction["sender"] = signer
        transaction["r"] = signed_tx.r
        transaction["s"] = signed_tx.s
        transaction["v"] = signed_tx.v

    return Block.model_validate(
        {
            "blockHeader": {
                "parentHash": "0x02a4bfb03275efd1bf926bcbccc1c12ef1ed723414c1196b75c33219355c7180",
                "uncleHash": "0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347",
                "coinbase": COINBASE,
                "stateRoot": "0x2f79dbc20b78bcd7a771a9eb6b25a4af69724085c97be69a95ba91187e66a9c0",
                "transactionsTrie": "0x5f3c4c1da4f0b2351fbb60b9e720d481ce0706b5aa697f10f28efbbab54e6ac8",
                "receiptTrie": "0xf44202824894394d28fa6c8c8e3ef83e1adf05405da06240c2ce9ca461e843d1",
                "withdrawalsRoot": "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
                "bloom": "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
                "difficulty": "0x00",
                "number": "0x01",
                "gasLimit": hex(TRANSACTION_GAS_LIMIT),
                "gasUsed": "0x0156f8",
                "timestamp": "0x64903c57",
                "mixHash": "0x0000000000000000000000000000000000000000000000000000000000020000",
                "nonce": "0x0000000000000000",
                "baseFeePerGas": hex(BASE_FEE_PER_GAS),
                "blobGasUsed": "0x00",
                "excessBlobGas": "0x00",
                "parentBeaconBlockRoot": "0x0000000000000000000000000000000000000000000000000000000000000000",
                "extraData": "0x00",
            },
            "transactions": transactions,
        }
    )
