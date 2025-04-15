from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.relocatable import RelocatableValue
from starkware.cairo.lang.vm.vm_consts import VmConsts

from cairo_addons.hints.decorator import register_hint


@register_hint
def common_prefix_length_hint(ids: VmConsts, memory: MemoryDict, ap: RelocatableValue):
    from ethereum.cancun.trie import common_prefix_length

    bytes_a = (
        bytes([memory[ids.a.value.data + i] for i in range(0, ids.a.value.len)]) or []
    )
    bytes_b = (
        bytes([memory[ids.b.value.data + i] for i in range(0, ids.b.value.len)]) or []
    )

    memory[ap - 1] = common_prefix_length(bytes_a, bytes_b)


@register_hint
def bytes_to_nibble_list_hint(
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
    ap: RelocatableValue,
):
    from ethereum.cancun.trie import bytes_to_nibble_list

    bytes_ = (
        bytes(
            [memory[ids.bytes_.value.data + i] for i in range(0, ids.bytes_.value.len)]
        )
        or []
    )
    nibble_list = bytes_to_nibble_list(bytes_)
    data_ptr = segments.add()
    segments.load_data(data_ptr, nibble_list)
    bytes_ptr = segments.add()
    segments.load_data(bytes_ptr, [data_ptr, len(nibble_list)])
    memory[ap - 1] = bytes_ptr
