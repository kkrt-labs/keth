import hashlib
from dataclasses import fields
from typing import List, Tuple, Union

from ethereum.crypto.hash import Hash32
from ethereum.prague.blocks import Header, Log, Withdrawal
from ethereum.prague.transactions import LegacyTransaction
from ethereum_types.bytes import Bytes, Bytes32


def LegacyTransaction__hash__(tx: LegacyTransaction) -> Hash32:
    field_hashes = []
    for field in fields(tx):
        field_value = getattr(tx, field.name)
        if isinstance(field_value, bytes):
            field_bytes = field_value
        else:
            field_bytes = field_value.to_bytes(32, "little")
        field_hashes.append(hashlib.blake2s(field_bytes).digest())

    input_bytes = b"".join(field_hashes)
    return hashlib.blake2s(input_bytes).digest()


def UnionBytesLegacyTransaction__hash__(tx: Union[Bytes, LegacyTransaction]) -> Hash32:
    if isinstance(tx, Bytes):
        return hashlib.blake2s(tx).digest()
    else:
        return LegacyTransaction__hash__(tx)


def TupleUnionBytesLegacyTransaction__hash__(
    tx: Tuple[Union[Bytes, LegacyTransaction], ...],
) -> Hash32:
    acc = []
    for item in tx:
        acc.append(UnionBytesLegacyTransaction__hash__(item))
    return hashlib.blake2s(b"".join(acc)).digest()


def ListHash32__hash__(list_hash32: List[Hash32]) -> Hash32:
    acc = []
    for item in list_hash32:
        acc.append(item)
    return hashlib.blake2s(b"".join(acc)).digest()


def TupleBytes32__hash__(tuple_bytes32: Tuple[Bytes32, ...]) -> Hash32:
    acc = []
    for item in tuple_bytes32:
        acc.append(hashlib.blake2s(item).digest())
    return hashlib.blake2s(b"".join(acc)).digest()


def Log__hash__(log: Log) -> Hash32:
    acc = []
    acc.append(hashlib.blake2s(log.address).digest())
    acc.append(TupleBytes32__hash__(log.topics))
    acc.append(hashlib.blake2s(log.data).digest())
    return hashlib.blake2s(b"".join(acc)).digest()


def TupleLog__hash__(tuple_log: Tuple[Log, ...]) -> Hash32:
    acc = []
    for item in tuple_log:
        acc.append(Log__hash__(item))
    return hashlib.blake2s(b"".join(acc)).digest()


def Header__hash__(header: Header) -> Hash32:
    acc = []

    # Iterate through all fields in the dataclass
    for field in fields(header):
        value = getattr(header, field.name)

        # Convert non-bytes instances to 32-byte representations
        if isinstance(value, bytes):
            # Special handling for fields that need hashing or padding
            if field.name == "bloom":
                acc.append(hashlib.blake2s(value).digest())
            elif field.name == "extra_data":
                acc.append(hashlib.blake2s(value).digest())
            elif field.name == "coinbase":
                acc.append(value + b"\x00" * 12)  # Pad 20-byte address to 32 bytes
            elif field.name == "nonce":
                acc.append(value + b"\x00" * 24)  # Pad 8-byte nonce to 32 bytes
            else:
                acc.append(value)
        else:
            # Convert numeric types to 32-byte little-endian representation
            acc.append(value.to_bytes(32, "little"))

    return hashlib.blake2s(b"".join(acc)).digest()


def Withdrawal__hash__(withdrawal: Withdrawal) -> Hash32:
    acc = []

    # Iterate through all fields in the dataclass
    for field in fields(withdrawal):
        value = getattr(withdrawal, field.name)

        # Convert non-bytes instances to 32-byte representations
        if isinstance(value, bytes):
            if field.name == "address":
                acc.append(value + b"\x00" * 12)  # Pad 20-byte address to 32 bytes
            else:
                acc.append(value)
        else:
            # Convert numeric types to 32-byte little-endian representation
            acc.append(value.to_bytes(32, "little"))

    return hashlib.blake2s(b"".join(acc)).digest()


def TupleWithdrawal__hash__(tuple_withdrawal: Tuple[Withdrawal, ...]) -> Hash32:
    acc = []
    for item in tuple_withdrawal:
        acc.append(Withdrawal__hash__(item))
    return hashlib.blake2s(b"".join(acc)).digest()


def TupleBytes__hash__(tuple_bytes: Tuple[Bytes, ...]) -> Hash32:
    acc = []
    for item in tuple_bytes:
        acc.append(hashlib.blake2s(item).digest())
    return hashlib.blake2s(b"".join(acc)).digest()
