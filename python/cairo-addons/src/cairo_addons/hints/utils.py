from cairo_addons.hints.decorator import register_hint
from starkware.cairo.common.dict import DictManager
from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.relocatable import RelocatableValue
from starkware.cairo.lang.vm.vm_consts import VmConsts


@register_hint
def Bytes__eq__(
    dict_manager: DictManager,
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
    ap: RelocatableValue,
):
    self_bytes = b"".join(
        [
            memory[ids._self.value.data + i].to_bytes(1, "little")
            for i in range(ids._self.value.len)
        ]
    )
    other_bytes = b"".join(
        [
            memory[ids.other.value.data + i].to_bytes(1, "little")
            for i in range(ids.other.value.len)
        ]
    )
    diff_index = next(
        (
            i
            for i, (b_self, b_other) in enumerate(zip(self_bytes, other_bytes))
            if b_self != b_other
        ),
        None,
    )
    if diff_index is not None:
        ids.is_diff = 1
        ids.diff_index = diff_index
    else:
        # No differences found in common prefix. Lengths were checked before
        ids.is_diff = 0
        ids.diff_index = 0


@register_hint
def b_le_a(
    dict_manager: DictManager,
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
    ap: RelocatableValue,
):
    ids.is_min_b = 1 if ids.b <= ids.a else 0


@register_hint
def fp_plus_2_or_0(
    dict_manager: DictManager,
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
    ap: RelocatableValue,
    fp: RelocatableValue,
):
    ids.value_set = memory.get(fp + 2) or 0


@register_hint
def print_maybe_relocatable(
    dict_manager: DictManager,
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
    ap: RelocatableValue,
):
    maybe_relocatable = ids.x
    print(f"maybe_relocatable: {maybe_relocatable}")
