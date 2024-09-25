from typing import Union

from pydantic import (
    AliasChoices,
    AliasGenerator,
    BaseModel,
    ConfigDict,
    field_validator,
    model_validator,
)
from pydantic.alias_generators import to_camel

from src.utils.uint256 import int_to_uint256


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


class BlockHeader(BaseModel):
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
