from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.vm_consts import VmConsts

from cairo_addons.hints.decorator import register_hint


@register_hint
def find_two_non_null_subnodes(
    memory: MemoryDict,
    ids: VmConsts,
):
    """
    Find two non-null subnodes of a given branch node.
    Inject the found values `first_non_null_index` and `second_non_null_index` the offset of the two subnodes in the range 0-15.
    """
    non_null_branches = [
        idx
        for idx in range(16)
        if (
            # Case subnode is a digest
            # subnode type is Extended
            # its variant is Bytes, len is at offset 1 of BytesStruct
            (
                memory[ids.subnodes_ptr + idx]
                and memory[memory[ids.subnodes_ptr + idx] + 2]
                and memory[memory[memory[ids.subnodes_ptr + idx] + 2] + 1] != 0
            )
            # Case subnode is an embedded node
            # subnode type is Extended
            # its variant is SequenceExtended, len is at offset 1 of SequenceExtendedStruct
            or (
                memory[ids.subnodes_ptr + idx]
                and memory[memory[ids.subnodes_ptr + idx]]
                and memory[memory[memory[ids.subnodes_ptr + idx]] + 1] != 0
            )
        )
    ]

    ids.first_non_null_index = non_null_branches[0] if len(non_null_branches) > 0 else 0
    ids.second_non_null_index = (
        non_null_branches[1] if len(non_null_branches) > 1 else 0
    )


@register_hint
def sort_account_diff(
    memory: MemoryDict,
    ids: VmConsts,
    segments: MemorySegmentManager,
):
    # Extract the list of pointers directly
    pointers = [memory[ids.diffs_ptr.address_ + i] for i in range(ids.diffs_len)]

    # Sort pointers based on the key values they point to, in descending order
    sorted_pointers = sorted(pointers, key=lambda ptr: memory[ptr], reverse=True)

    # Load the sorted pointers into ids.buffer
    segments.load_data(ids.buffer, sorted_pointers)

    indices = list(range(ids.diffs_len))
    sorted_indices = sorted(indices, key=lambda i: memory[pointers[i]], reverse=True)
    segments.load_data(ids.sorted_indexes, sorted_indices)
