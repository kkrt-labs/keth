"""
This file contains hints for the bytes.cairo file.

Added the _hint suffix to the hints to avoid conflicts with the bytes python object.
"""

from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.relocatable import RelocatableValue
from starkware.cairo.lang.vm.vm_consts import VmConsts

from cairo_addons.hints.decorator import register_hint


@register_hint
def bytes_len_less_than_8(ids: VmConsts):
    ids.less_than_8 = int(ids.bytes_len < 8)


@register_hint
def remaining_bytes_greater_than_8(
    ids: VmConsts, memory: MemoryDict, fp: RelocatableValue
):
    ids.continue_loop = int(ids.bytes_len - (ids.bytes8 - memory[fp - 5]) * 8 >= 8)


@register_hint
def remaining_bytes_jmp_offset(ids: VmConsts, memory: MemoryDict, fp: RelocatableValue):
    ids.remaining_offset = 2 * (ids.bytes_len - (ids.bytes8 - memory[fp - 5]) * 8) + 1
