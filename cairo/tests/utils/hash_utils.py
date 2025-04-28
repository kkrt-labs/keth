import hashlib
from typing import List, Tuple, Union

from ethereum.cancun.blocks import Log
from ethereum.cancun.transactions import LegacyTransaction
from ethereum.crypto.hash import Hash32
from ethereum_types.bytes import Bytes, Bytes32


def LegacyTransaction__hash__(tx: LegacyTransaction) -> Hash32:
    nonce_hash = hashlib.blake2s(tx.nonce.to_bytes(32, "little")).digest()
    gas_price_hash = hashlib.blake2s(tx.gas_price.to_bytes(32, "little")).digest()
    gas_hash = hashlib.blake2s(tx.gas.to_bytes(32, "little")).digest()
    to_hash = hashlib.blake2s(tx.to).digest()
    value_hash = hashlib.blake2s(tx.value.to_bytes(32, "little")).digest()
    data_hash = hashlib.blake2s(tx.data).digest()
    v_hash = hashlib.blake2s(tx.v.to_bytes(32, "little")).digest()
    r_hash = hashlib.blake2s(tx.r.to_bytes(32, "little")).digest()
    s_hash = hashlib.blake2s(tx.s.to_bytes(32, "little")).digest()

    input_bytes = (
        nonce_hash
        + gas_price_hash
        + gas_hash
        + to_hash
        + value_hash
        + data_hash
        + v_hash
        + r_hash
        + s_hash
    )
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
