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
