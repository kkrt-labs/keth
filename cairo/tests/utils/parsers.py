import re
from typing import Annotated, Optional, Union

from ethereum_types.bytes import Bytes, Bytes0, Bytes32
from ethereum_types.numeric import U64, U256, Uint
from pydantic import BeforeValidator

from ethereum.cancun.fork_types import Address

hex_pattern = re.compile(r"^(0x)?[0-9a-fA-F]+$")


def to_int(v: Optional[Union[str, int]]) -> Optional[int]:
    if v is None:
        return v
    if isinstance(v, str):
        if hex_pattern.match(v):
            return int(v, 16)
        return int(v)
    if isinstance(v, bytes):
        return int.from_bytes(v, "big")
    return v


def to_bytes(v: Optional[Union[str, bytes, list[int]]]) -> Optional[bytes]:
    if v is None:
        return v
    if isinstance(v, bytes):
        return v
    elif isinstance(v, str):
        if v.startswith("0x"):
            return bytes.fromhex(v[2:])
        return v.encode()
    else:
        return bytes(v)


def to_fixed_bytes(length: int):
    def _parser(v: Union[str, bytes, int, list[int]]):
        if isinstance(v, int):
            return v.to_bytes(length, byteorder="big")

        res = to_bytes(v)
        if res is None or len(res) > length:
            raise ValueError(f"Value {v} is too big for a {length} bytes fixed bytes")
        return res.ljust(length, b"\x00")

    return _parser


int_parser = BeforeValidator(to_int)
bytes_parser = BeforeValidator(to_bytes)
bytes0_parser = BeforeValidator(to_fixed_bytes(0))
bytes32_parser = BeforeValidator(to_fixed_bytes(32))
bytes20_parser = BeforeValidator(to_fixed_bytes(20))

u256_validator = BeforeValidator(U256)
u64_validator = BeforeValidator(U64)
u128_validator = BeforeValidator(
    lambda v: v if v < 2**128 else ValueError("Value is too big for a 128 bit uint")
)
uint_validator = BeforeValidator(Uint)
bytes0_validator = BeforeValidator(lambda b: Bytes0(b))
address_validator = BeforeValidator(lambda b: Address(b))
destination_validator = BeforeValidator(
    lambda b: Bytes0() if len(b) == 0 else Address(to_fixed_bytes(20)(b))
)
bytes32_validator = BeforeValidator(lambda b: Bytes32(b))
bytes_validator = BeforeValidator(lambda b: Bytes(b))

uint256 = Annotated[int, u256_validator, int_parser]
uint128 = Annotated[int, u128_validator, int_parser]
uint64 = Annotated[int, u64_validator, int_parser]
uint = Annotated[int, uint_validator, int_parser]
bytes32 = Annotated[bytes, bytes32_validator, bytes32_parser]
bytes0 = Annotated[bytes, bytes0_validator, bytes0_parser]
bytes_ = Annotated[list, BeforeValidator(list), bytes_parser]
address = Annotated[bytes, address_validator, bytes20_parser]
destination = Annotated[Union[Address, Bytes0], destination_validator, bytes_parser]
