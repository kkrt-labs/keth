from collections import defaultdict
from itertools import chain
from textwrap import wrap
from typing import Annotated, DefaultDict, Tuple, Union

from eth_hash.auto import keccak
from eth_utils.address import to_checksum_address
from ethereum_types.numeric import U256
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

from ethereum.crypto.elliptic_curve import secp256k1_recover
from ethereum.crypto.hash import Hash32
from src.utils.uint256 import int_to_uint256
from tests.utils.helpers import flatten, rlp_encode_signed_data
from tests.utils.parsers import address, bytes_, to_bytes, to_int, uint, uint64, uint128


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
            "ommers_hash",
            "sha3_uncles",
            "state_root",
            "transactions_trie",
            "transactions_root",
            "receipt_trie",
            "receipt_root",
            "receipts_root",
            "withdrawals_root",
            "difficulty",
            "mix_hash",
            "prev_randao",
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
            "withdrawals_root",
            "base_fee_per_gas",
            "blob_gas_used",
            "excess_blob_gas",
            "parent_beacon_block_root",
            "requests_root",
        ]:
            if key not in values:
                key = to_camel(key)
            is_some = key in values and values[key] is not None
            # it's possible that values[key] exists and is None, that why we can't use get default value
            value = to_int(values.get(key) or 0)
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
        return tuple(int(chunk, 16) for chunk in wrap(bloom.hex(), 32))

    parent_hash_low: int = Field(
        validation_alias=AliasChoices("parentHash", "parent_hash", "parent_hash_low")
    )
    parent_hash_high: int = Field(
        validation_alias=AliasChoices("parentHashHigh", "parent_hash_high")
    )
    uncle_hash_low: int = Field(
        validation_alias=AliasChoices(
            "ommersHash",
            "uncleHash",
            "sha3Uncles",
            "ommers_hash",
            "uncle_hash",
            "sha3_uncles",
            "ommers_hash_low",
            "uncle_hash_low",
            "sha3_uncles_low",
        )
    )
    uncle_hash_high: int = Field(
        validation_alias=AliasChoices(
            "ommersHashHigh",
            "uncleHashHigh",
            "sha3UnclesHigh",
            "ommers_hash_high",
            "uncle_hash_high",
            "sha3_uncles_high",
        )
    )
    coinbase: int = Field(
        validation_alias=AliasChoices("coinbase", "miner", "miner_address")
    )
    state_root_low: int
    state_root_high: int
    transactions_trie_low: int = Field(
        validation_alias=AliasChoices(
            "transactionsTrie",
            "transactionsRoot",
            "transactions_trie",
            "transactions_root",
            "transactions_root_low",
        )
    )
    transactions_trie_high: int = Field(
        validation_alias=AliasChoices(
            "transactionsTrieHigh", "transactionsRootHigh", "transactions_root_high"
        )
    )
    receipt_trie_low: int = Field(
        validation_alias=AliasChoices(
            "transactionsTrie",
            "transactionsRoot",
            "transactions_trie",
            "transactions_root",
            "transactions_root_low",
            "receiptsRoot",
            "receipts_root",
            "receipts_root_low",
        )
    )
    receipt_trie_high: int = Field(
        validation_alias=AliasChoices(
            "receiptTrieHigh",
            "receiptRootHigh",
            "receipt_root_high",
            "receiptsRootHigh",
            "receipts_root_high",
        )
    )
    withdrawals_root_is_some: bool
    withdrawals_root_value: Tuple[int, int]
    bloom: Tuple[int, ...] = Field(
        validation_alias=AliasChoices("bloom", "logsBloom", "logs_bloom")
    )
    difficulty_low: int
    difficulty_high: int
    number: int
    gas_limit: int
    gas_used: int
    timestamp: int
    mix_hash_low: int = Field(
        validation_alias=AliasChoices(
            "mix_hash", "mixHash", "prev_randao", "prevRandao"
        )
    )
    mix_hash_high: int = Field(
        validation_alias=AliasChoices(
            "mixHashHigh", "prev_randao_high", "prevRandaoHigh"
        )
    )
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

        # Legacy transaction wrongly labeled as type 0
        if int(values.get("type", "0x1"), 16) == 0:
            del values["type"]

        values["v"] = values.pop("v", values.pop("yParity", None))
        values.pop("hash", None)
        r = to_int(values["r"])
        s = to_int(values["s"])
        v = to_int(values["v"])
        y_parity = (
            v
            if v in [0, 1]
            else (
                (v - 27) if v in [27, 28] else (v - 2 * int(values["chainId"], 16) - 35)
            )
        )
        signature = [*int_to_uint256(r), *int_to_uint256(s), v]
        del values["r"]
        del values["s"]
        del values["v"]
        if "maxFeePerGas" in values and values["maxFeePerGas"] is not None:
            assert values.pop("gasPrice", None) is None
        else:
            assert values.pop("maxFeePerGas", None) is None
            assert values.pop("maxPriorityFeePerGas", None) is None
        values["data"] = values.pop(
            "data", values.pop("payload", values.pop("input", None))
        )
        if values.get("to") is not None:
            values["to"] = to_checksum_address(values["to"])

        rlp = rlp_encode_signed_data(values)

        values["rlp"] = list(rlp)
        values["rlp_len"] = len(rlp)
        values["signature"] = signature
        values["signature_len"] = len(signature)
        recovered_sender = int.from_bytes(
            keccak(
                secp256k1_recover(
                    U256(r), U256(s), U256(y_parity), Hash32(keccak(bytes(rlp)))
                )
            )[-20:],
            "big",
        )
        if "sender" not in values:
            values["sender"] = recovered_sender
        else:
            assert to_int(values["sender"]) == recovered_sender
        return values

    @field_validator("sender", mode="before")
    def parse_hex_to_int(cls, v):
        return to_int(v)

    rlp_len: int
    rlp: list[int]
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
        return values


class State(BaseModelIterValuesOnly):
    accounts: DefaultDict[
        int, Annotated[Union[int, Account], Field(default_factory=int)]
    ] = defaultdict(int)
    events_len: int = 0
    events: list = []

    @model_validator(mode="before")
    def parse_addresses(cls, values):
        values = values.copy()
        values["accounts"] = defaultdict(int, {to_int(k): v for k, v in values.items()})
        return values


class Transaction(BaseModelIterValuesOnly):
    @model_validator(mode="before")
    def split_uint256(cls, values):
        values = values.copy()
        for key in ["amount", "value"]:
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
        for key in ["destination", "chain_id"]:
            if key not in values:
                key = to_camel(key)
            if key not in values and "to" in values:
                key = "to"
            is_some = key in values and values[key] is not None
            # it's possible that values[key] exists and is None, that why we can't use get default value
            value = to_int(values.get(key) or 0)
            values[to_camel(key) + "IsSome"] = is_some
            values[to_camel(key) + "Value"] = value
        return values

    @model_validator(mode="before")
    def parse_access_list(cls, values):
        values = values.copy()
        if "access_list" not in values:
            return values

        value = flatten(
            [
                (
                    int.from_bytes(key, "big"),
                    len(addresses),
                    *[
                        int_to_uint256(int.from_bytes(address, "big"))
                        for address in addresses
                    ],
                )
                for key, addresses in values["access_list"]
            ]
        )
        if value is None:
            return values
        values["access_list"] = value
        values["access_list_len"] = len(value)
        return values

    @model_validator(mode="before")
    def add_len(cls, values):
        values = values.copy()
        for key in ["payload", "data"]:
            if key not in values:
                key = to_camel(key)
            if key not in values:
                continue

            values[to_camel(key) + "Len"] = len(values[key])
        return values

    signer_nonce: uint64 = Field(validation_alias="nonce")
    gas_limit: uint = Field(validation_alias="gas")
    max_priority_fee_per_gas: uint = Field(validation_alias="gas_price")
    max_fee_per_gas: uint = Field(validation_alias="gas_price")
    destination_is_some: uint = Field(validation_alias="toIsSome")
    destination_value: address = Field(validation_alias="toValue")
    amount_low: uint128 = Field(validation_alias="value")
    amount_high: uint128 = Field(validation_alias="valueHigh")
    payload_len: uint = Field(validation_alias="dataLen")
    payload: bytes_ = Field(validation_alias="data")
    access_list_len: uint
    access_list: list[uint]
    chain_id_is_some: uint
    chain_id_value: uint64
