from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.vm_consts import VmConsts

from cairo_addons.hints.decorator import register_hint


@register_hint
def felt252_to_bytes_le(ids: VmConsts, segments: MemorySegmentManager):
    # If value doesn't fit in ids.len bytes, truncate it
    mask = (1 << (ids.len * 8)) - 1
    truncated_value = ids.value & mask
    segments.load_data(
        ids.output,
        [b for b in truncated_value.to_bytes(length=ids.len, byteorder="little")],
    )


@register_hint
def felt252_to_bytes_be(ids: VmConsts, segments: MemorySegmentManager):
    # If value doesn't fit in ids.len bytes, truncate it
    mask = (1 << (ids.len * 8)) - 1
    truncated_value = ids.value & mask
    segments.load_data(
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
    """
    Hint to write the `len` least significant bits of `value`
    to the memory segment starting at `dst` in reversed order.
    """
    value = ids.value
    length = ids.len
    dst_ptr = ids.dst

    if length != 0:
        # Ensure we only work with the bits relevant to the requested length
        # Python's integers handle large numbers automatically
        mask = (1 << length) - 1
        value_masked = value & mask
        bits_used = value_masked.bit_length() or 1

        # Generate the 'length' bits in reversed order
        bits = [int(bit) for bit in bin(value_masked)[2:].zfill(length)[::-1]]

        # Load the generated bits into the specified memory segment
        ids.bits_used = min(bits_used, length)
        segments.load_data(dst_ptr, bits)
    else:
        ids.bits_used = 0
