from typing import Optional, Union


def to_int(v: Optional[Union[str, int]]) -> Optional[int]:
    if v is None:
        return v
    if isinstance(v, str):
        if v.startswith("0x"):
            return int(v, 16)
        return int(v)
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
