import random
from typing import Iterable, Tuple, Union

import rlp
from eth_account._utils.transaction_utils import transaction_rpc_to_rlp_structure
from eth_account.typed_transactions.typed_transaction import TypedTransaction
from eth_keys.main import lazy_key_api as keys
from eth_utils.address import to_checksum_address
from eth_utils.crypto import keccak
from eth_utils.hexadecimal import decode_hex
from ethereum_types.numeric import U256
from starkware.cairo.lang.vm.crypto import pedersen_hash

from src.utils.uint256 import int_to_uint256
from tests.utils.parsers import to_bytes, to_int


def rlp_encode_signed_data(tx: dict):
    if "type" in tx:
        typed_transaction = TypedTransaction.from_dict(tx)

        sanitized_transaction = transaction_rpc_to_rlp_structure(
            typed_transaction.transaction.dictionary
        )

        # RPC-structured transaction to rlp-structured transaction
        rlp_serializer = (
            typed_transaction.transaction.__class__._unsigned_transaction_serializer
        )
        return [
            typed_transaction.transaction_type,
            *rlp.encode(rlp_serializer.from_dict(sanitized_transaction)),
        ]
    else:
        legacy_tx = [
            to_int(tx["nonce"]),
            to_int(tx["gasPrice"]),
            to_int(tx["gas"] if "gas" in tx else tx["gasLimit"]),
            bytes.fromhex(f"{to_int(tx['to']):040x}") if tx["to"] else b"",
            to_int(tx["value"]),
            to_bytes(tx["data"]),
        ] + ([to_int(tx["chainId"]), 0, 0] if "chainId" in tx else [])

        return rlp.encode(legacy_tx)


def get_create_address(sender_address: Union[int, str], nonce: int) -> str:
    """
    See [CREATE](https://www.evm.codes/#f0).
    """
    return to_checksum_address(
        keccak(rlp.encode([decode_hex(to_checksum_address(sender_address)), nonce]))[
            -20:
        ]
    )


def generate_random_private_key():
    return keys.PrivateKey(int.to_bytes(random.getrandbits(256), 32, "big"))


def ec_sign(
    digest: bytes, owner_private_key: keys.PrivateKey
) -> Tuple[int, bytes, bytes]:
    signature = owner_private_key.sign_msg_hash(digest)
    return (
        signature.v + 27,
        int.to_bytes(signature.r, 32, "big"),
        int.to_bytes(signature.s, 32, "big"),
    )


def flatten(data):
    result = []

    def _flatten(item):
        if isinstance(item, Iterable) and not isinstance(item, (str, bytes, bytearray)):
            for sub_item in item:
                _flatten(sub_item)
        else:
            result.append(item)

    _flatten(data)
    return result


def flatten_tx_access_list(access_list):
    """
    Transform the access list from the transaction dict into a flattened list of
    [address, storage_keys, ...].
    """
    result = []
    for item in access_list:
        result.append(int(item["address"], 16))
        result.append(len(item["storageKeys"]))
        for key in item["storageKeys"]:
            result.extend(int_to_uint256(int(key, 16)))
    return result


def get_internal_storage_key(key: U256) -> int:
    low, high = int_to_uint256(int(key))
    return pedersen_hash(low, high)
