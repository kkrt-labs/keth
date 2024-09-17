import random
from collections import defaultdict
from textwrap import wrap
from typing import List, Tuple, Union

import rlp
from eth_account._utils.transaction_utils import transaction_rpc_to_rlp_structure
from eth_account.typed_transactions import TypedTransaction
from eth_keys import keys
from eth_utils import decode_hex, keccak, to_checksum_address
from src.utils.uint256 import int_to_uint256
from starkware.cairo.lang.vm.crypto import pedersen_hash


def rlp_encode_signed_data(tx: dict) -> bytes:
    if "type" in tx:
        typed_transaction = TypedTransaction.from_dict(tx)

        sanitized_transaction = transaction_rpc_to_rlp_structure(
            typed_transaction.transaction.dictionary
        )

        # RPC-structured transaction to rlp-structured transaction
        rlp_serializer = (
            typed_transaction.transaction.__class__._unsigned_transaction_serializer
        )
        encoded_unsigned_tx = [
            typed_transaction.transaction_type,
            *rlp.encode(rlp_serializer.from_dict(sanitized_transaction)),
        ]

        return encoded_unsigned_tx
    else:
        legacy_tx = (
            [
                tx["nonce"],
                tx["gasPrice"],
                tx["gas"],
                int(tx["to"], 16),
                tx["value"],
                tx["data"],
                tx["chainId"],
                0,
                0,
            ]
            if "chainId" in tx
            else [
                tx["nonce"],
                tx["gasPrice"],
                tx["gas"],
                int(tx["to"], 16),
                tx["value"],
                tx["data"],
            ]
        )
        encoded_unsigned_tx = rlp.encode(legacy_tx)

        return encoded_unsigned_tx


def get_create_address(sender_address: Union[int, str], nonce: int) -> str:
    """
    See [CREATE](https://www.evm.codes/#f0).
    """
    return to_checksum_address(
        keccak(rlp.encode([decode_hex(to_checksum_address(sender_address)), nonce]))[
            -20:
        ]
    )


def get_create2_address(
    sender_address: Union[int, str], salt: int, initialization_code: bytes
) -> str:
    """
    See [CREATE2](https://www.evm.codes/#f5).
    """
    return to_checksum_address(
        keccak(
            b"\xff"
            + decode_hex(to_checksum_address(sender_address))
            + salt.to_bytes(32, "big")
            + keccak(initialization_code)
        )[-20:]
    )


def private_key_from_hex(hex_key: str):
    return keys.PrivateKey(bytes.fromhex(hex_key))


def generate_random_private_key():
    return keys.PrivateKey(int.to_bytes(random.getrandbits(256), 32, "big"))


def generate_random_evm_address():
    return generate_random_private_key().public_key.to_checksum_address()


def ec_sign(
    digest: bytes, owner_private_key: keys.PrivateKey
) -> Tuple[int, bytes, bytes]:
    signature = owner_private_key.sign_msg_hash(digest)
    return (
        signature.v + 27,
        int.to_bytes(signature.r, 32, "big"),
        int.to_bytes(signature.s, 32, "big"),
    )


def pack_64_bits_little(input: List[int]):
    return sum([x * 256**i for (i, x) in enumerate(input)])


def flatten(data):
    result = []

    def _flatten(item):
        if isinstance(item, list):
            for sub_item in item:
                _flatten(sub_item)
        else:
            result.extend(item)

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


def merge_access_list(access_list):
    """
    Merge all entries of the access list to get one entry per account with all its storage keys.
    """
    merged_list = defaultdict(set)
    for access in access_list:
        merged_list[access["address"]] = merged_list[access["address"]].union(
            {
                pedersen_hash(*int_to_uint256(int(key, 16)))
                for key in access["storageKeys"]
            }
        )
    return merged_list


def pack_calldata(data: bytes) -> List[int]:
    """
    Pack the incoming calldata bytes 31-bytes at a time in big-endian order.
    Returns a serialized array with the following elements:
    - data_len: full length of input data
    - full_words: full 31-byte words
    - last_word: the last word taking less than or equal to 31 bytes.
    """

    return [len(data), *[int(chunk, 16) for chunk in wrap(data.hex(), 2 * 31)]]
