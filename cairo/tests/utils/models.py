from collections import defaultdict
from itertools import chain
from textwrap import wrap
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
from pydantic.alias_generators import to_camel, to_snake
from starkware.cairo.lang.vm.crypto import pedersen_hash

from src.utils.uint256 import int_to_uint256
from tests.utils.helpers import rlp_encode_signed_data
from tests.utils.parsers import to_bytes, to_int


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
        "coinbase",
        "number",
        "gas_limit",
        "gas_used",
        "timestamp",
        "nonce",
        mode="before",
    )
    def parse_hex_to_int(cls, v):
        return to_int(v)

    @model_validator(mode="before")
    def split_uint256(cls, values):
        values = values.copy()
        for key in [
            "parent_hash",
            "uncle_hash",
            "state_root",
            "transactions_trie",
            "receipt_trie",
            "withdrawals_root",
            "difficulty",
            "mix_hash",
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
    def split_option(cls, values):
        values = values.copy()
        for key in [
            "base_fee_per_gas",
            "blob_gas_used",
            "excess_blob_gas",
            "parent_beacon_block_root",
            "requests_root",
        ]:
            if key not in values:
                key = to_camel(key)
            is_some = key in values
            value = to_int(values.get(key, 0))
            values[to_camel(key) + "IsSome"] = is_some
            value_type = cls.model_fields[to_snake(key) + "_value"].annotation
            values[to_camel(key) + "Value"] = (
                int_to_uint256(value) if value_type == Tuple[int, int] else value
            )
        return values

    @model_validator(mode="before")
    def add_len_to_extra_data(cls, values):
        values = values.copy()
        for key in ["extra_data"]:
            if key not in values:
                key = to_camel(key)
            if key not in values:
                continue

            value = to_bytes(values[key])
            if value is None:
                continue
            values[key] = value
            values[to_camel(key) + "Len"] = len(value)
        return values

    @field_validator("bloom", mode="before")
    def parse_bloom(cls, v):
        bloom = to_bytes(v)
        if bloom is None:
            raise ValueError("Bloom cannot be empty")
        if len(bloom) != 256:
            raise ValueError("Bloom must be 256 bytes")
        return tuple(int(chunk) for chunk in wrap(bloom.hex(), 32))

    parent_hash_low: int
    parent_hash_high: int
    uncle_hash_low: int
    uncle_hash_high: int
    coinbase: int
    state_root_low: int
    state_root_high: int
    transactions_trie_low: int
    transactions_trie_high: int
    receipt_trie_low: int
    receipt_trie_high: int
    withdrawals_root_low: int
    withdrawals_root_high: int
    bloom: Tuple[int, ...]
    difficulty_low: int
    difficulty_high: int
    number: int
    gas_limit: int
    gas_used: int
    timestamp: int
    mix_hash_low: int
    mix_hash_high: int
    nonce: int
    base_fee_per_gas_is_some: bool
    base_fee_per_gas_value: int
    blob_gas_used_is_some: bool
    blob_gas_used_value: int
    excess_blob_gas_is_some: bool
    excess_blob_gas_value: int
    parent_beacon_block_root_is_some: bool
    parent_beacon_block_root_value: Tuple[int, int]
    requests_root_is_some: bool
    requests_root_value: Tuple[int, int]
    extra_data_len: int
    extra_data: bytes


class TransactionEncoded(BaseModelIterValuesOnly):
    @model_validator(mode="before")
    def encode_rlp_and_signature(cls, values):
        values = values.copy()
        if set(values.keys()) == {
            "rlp_len",
            "rlp",
            "signature_len",
            "signature",
            "sender",
        }:
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

    @field_validator("sender", mode="before")
    def parse_hex_to_int(cls, v):
        return to_int(v)

    rlp_len: int
    rlp: bytes
    signature_len: int
    signature: list[int]
    sender: int


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
