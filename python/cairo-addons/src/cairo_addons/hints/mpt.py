from starkware.cairo.lang.vm.memory_dict import MemoryDict
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
    if len(non_null_branches) >= 2:
        ids.first_non_null_index, ids.second_non_null_index = non_null_branches[0:2]
