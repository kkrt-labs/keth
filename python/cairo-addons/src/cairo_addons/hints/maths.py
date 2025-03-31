from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.vm_consts import VmConsts

from cairo_addons.hints.decorator import register_hint


@register_hint
def felt252_to_bytes_le(ids: VmConsts, segments: MemorySegmentManager):
    # If value doesn't fit in ids.len bytes, truncate it
    mask = (1 << (ids.len * 8)) - 1
    truncated_value = ids.value & mask
    segments.write_arg(
        ids.output,
        [b for b in truncated_value.to_bytes(length=ids.len, byteorder="little")],
    )


@register_hint
def felt252_to_bytes_be(ids: VmConsts, segments: MemorySegmentManager):
    # If value doesn't fit in ids.len bytes, truncate it
    mask = (1 << (ids.len * 8)) - 1
    truncated_value = ids.value & mask
    segments.write_arg(
        ids.output,
        [b for b in truncated_value.to_bytes(length=ids.len, byteorder="big")],
    )


@register_hint
def is_positive_hint(ids: VmConsts):
    from starkware.cairo.common.math_utils import as_int
    from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

    ids.is_positive = 1 if as_int(ids.value, DEFAULT_PRIME) >= 0 else 0


@register_hint
def value_len_mod_two(ids: VmConsts):
    ids.remainder = ids.len % 2


@register_hint
def felt252_to_bits_rev(ids: VmConsts, segments: MemorySegmentManager):
    value = ids.value
    dst = ids.dst

    # Convert to binary representation and strip the leading '0b' prefix
    # also, pad with leading zeros if necessary (if value has less bits than len)
    binary = bin(value)[2:].zfill(ids.len)

    last_one = len(binary) - binary.rfind("1") - 1

    segments.load_data(dst, [int(bit) for bit in binary][::-1])
