from collections import defaultdict
from itertools import chain
from typing import Annotated, DefaultDict, Tuple, Union

from eth_utils import keccak
from ethereum.cancun.vm.runtime import get_valid_jump_destinations
from pydantic import (
    AliasChoices,
    AliasGenerator,
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)
from pydantic.alias_generators import to_camel
from starkware.cairo.lang.vm.crypto import pedersen_hash

from src.utils.uint256 import int_to_uint256
from tests.utils.helpers import rlp_encode_signed_data


def to_int(v: Union[str, int]) -> int:
    if isinstance(v, str):
        if v.startswith("0x"):
            return int(v, 16)
        return int(v)
    return v


def to_bytes(v: Union[str, bytes, list[int]]) -> bytes:
    if isinstance(v, bytes):
        return v
    elif isinstance(v, str):
        if v.startswith("0x"):
            return bytes.fromhex(v[2:])
        return v.encode()
    else:
        return bytes(v)


class BaseModelIterValuesOnly(BaseModel):
    model_config = ConfigDict(
        populate_by_name=True,
        alias_generator=AliasGenerator(
            validation_alias=lambda name: AliasChoices(
                to_camel(name.replace("_low", "")),
                name.replace("_low", ""),
                to_camel(name),
                name,
            )
        ),
    )

    def __iter__(self):
        for value in self.__dict__.values():
            yield value


class BlockHeader(BaseModelIterValuesOnly):
    @field_validator(
        "base_fee_per_gas",
        "blob_gas_used",
        "coinbase",
        "difficulty",
        "excess_blob_gas",
        "gas_limit",
        "gas_used",
        "nonce",
        "number",
        "timestamp",
        mode="before",
    )
    def parse_hex_to_int(cls, v):
        return to_int(v)

    @field_validator("extra_data", "bloom", mode="before")
    def parse_hex_to_bytes(cls, v):
        return to_bytes(v)

    @model_validator(mode="before")
    def split_uint256(cls, values):
        values = values.copy()
        for key in [
            "hash",
            "mix_hash",
            "parent_beacon_block_root",
            "parent_hash",
            "receipt_trie",
            "state_root",
            "transactions_trie",
            "uncle_hash",
            "withdrawals_root",
        ]:
            if key not in values:
                key = to_camel(key)
            if key not in values:
                continue

            values[key], values[to_camel(key) + "High"] = int_to_uint256(
                to_int(values[key])
            )
        return values

    @model_validator(mode="before")
    def add_len_to_bytes(cls, values):
        values = values.copy()
        for key in ["bloom", "extra_data"]:
            if key not in values:
                key = to_camel(key)
            if key not in values:
                continue

            value = to_bytes(values[key])
            values[key] = value
            values[to_camel(key) + "Len"] = len(value)
        return values

    base_fee_per_gas: int
    blob_gas_used: int
    bloom_len: int
    bloom: bytes
    coinbase: int
    difficulty: int
    excess_blob_gas: int
    extra_data_len: int
    extra_data: bytes
    gas_limit: int
    gas_used: int
    hash_low: int
    hash_high: int
    mix_hash_low: int
    mix_hash_high: int
    nonce: int
    number: int
    parent_beacon_block_root_low: int
    parent_beacon_block_root_high: int
    parent_hash_low: int
    parent_hash_high: int
    receipt_trie_low: int
    receipt_trie_high: int
    state_root_low: int
    state_root_high: int
    timestamp: int
    transactions_trie_low: int
    transactions_trie_high: int
    uncle_hash_low: int
    uncle_hash_high: int
    withdrawals_root_low: int
    withdrawals_root_high: int


class TransactionEncoded(BaseModelIterValuesOnly):
    @model_validator(mode="before")
    def encode_rlp_and_signature(cls, values):
        values = values.copy()
        if set(values.keys()) == {"rlp_len", "rlp", "signature_len", "signature"}:
            return values

        signature = [
            *int_to_uint256(to_int(values["r"])),
            *int_to_uint256(to_int(values["s"])),
            to_int(values["v"]),
        ]
        del values["r"]
        del values["s"]
        del values["v"]
        rlp = rlp_encode_signed_data(values)

        values["rlp"] = rlp
        values["rlp_len"] = len(rlp)
        values["signature"] = signature
        values["signature_len"] = len(signature)
        return values

    @field_validator("rlp", mode="before")
    def parse_hex_to_bytes(cls, v):
        return to_bytes(v)

    rlp_len: int
    rlp: bytes
    signature_len: int
    signature: list[int]


class Block(BaseModelIterValuesOnly):
    block_header: BlockHeader
    transactions: list[TransactionEncoded]

    def __iter__(self):
        yield self.block_header
        yield len(self.transactions)
        yield chain.from_iterable(self.transactions)


class Account(BaseModelIterValuesOnly):
    code_len: int
    code: bytes
    code_hash: tuple[int, int]
    storage: DefaultDict[
        int, Annotated[Union[int, Tuple[int, int]], Field(default_factory=int)]
    ] = defaultdict(int)
    transient_storage: DefaultDict[
        int, Annotated[Union[int, Tuple[int, int]], Field(default_factory=int)]
    ] = defaultdict(int)
    valid_jumpdests: DefaultDict[int, Annotated[bool, Field(default_factory=bool)]] = (
        defaultdict(bool)
    )
    nonce: int
    balance: tuple[int, int]
    selfdestruct: int = 0
    created: int = 0

    @field_validator("nonce", mode="before")
    def parse_hex_to_int(cls, v):
        return to_int(v)

    @field_validator("code_hash", "balance", mode="before")
    def parse_hex_to_uint256(cls, v):
        return int_to_uint256(to_int(v))

    @field_validator("code", mode="before")
    def parse_hex_to_bytes(cls, v):
        return to_bytes(v)

    @model_validator(mode="before")
    def split_uint256_and_hash_storage(cls, values):
        values = values.copy()
        values["code_len"] = len(to_bytes(values["code"]))
        values["code_hash"] = int.from_bytes(
            keccak(to_bytes(values["code"])), byteorder="big"
        )
        values["storage"] = defaultdict(
            int,
            {
                pedersen_hash(*int_to_uint256(to_int(k))): int_to_uint256(to_int(v))
                for k, v in values["storage"].items()
            },
        )
        values["valid_jumpdests"] = defaultdict(
            int,
            {
                key: True
                for key in get_valid_jump_destinations(to_bytes(values["code"]))
            },
        )
        return values


class State(BaseModelIterValuesOnly):
    accounts: DefaultDict[
        int, Annotated[Union[int, Account], Field(default_factory=int)]
    ] = defaultdict(int)
    events_len: int = 0
    events: list = []
    transfers_len: int = 0
    transfers: list = []

    @model_validator(mode="before")
    def parse_addresses(cls, values):
        values = values.copy()
        values["accounts"] = defaultdict(int, {to_int(k): v for k, v in values.items()})
        return values
