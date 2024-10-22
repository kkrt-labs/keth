import re
from typing import Optional, Union

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
