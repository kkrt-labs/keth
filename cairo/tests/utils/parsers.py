from typing import Union


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
