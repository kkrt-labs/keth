from starkware.cairo.common.dict import DictManager
from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.relocatable import RelocatableValue
from starkware.cairo.lang.vm.vm_consts import VmConsts

from cairo_addons.hints.decorator import register_hint


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
def print_maybe_relocatable_hint(
    dict_manager: DictManager,
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
    ap: RelocatableValue,
):
    maybe_relocatable = ids.x
    print(f"maybe_relocatable: {maybe_relocatable}")


@register_hint
def precompile_index_from_address(
    ids: VmConsts,
):

    from ethereum.cancun.vm.precompiled_contracts import (
        ALT_BN128_ADD_ADDRESS,
        ALT_BN128_MUL_ADDRESS,
        ALT_BN128_PAIRING_CHECK_ADDRESS,
        BLAKE2F_ADDRESS,
        ECRECOVER_ADDRESS,
        IDENTITY_ADDRESS,
        MODEXP_ADDRESS,
        POINT_EVALUATION_ADDRESS,
        RIPEMD160_ADDRESS,
        SHA256_ADDRESS,
    )

    # The index associated to the precompile can be anything, provided it matches the location
    # of the precompile in the precompile table.
    ADDRESS_TO_INDEX = {
        ECRECOVER_ADDRESS: 0 * 3,
        SHA256_ADDRESS: 1 * 3,
        RIPEMD160_ADDRESS: 2 * 3,
        IDENTITY_ADDRESS: 3 * 3,
        MODEXP_ADDRESS: 4 * 3,
        ALT_BN128_ADD_ADDRESS: 5 * 3,
        ALT_BN128_MUL_ADDRESS: 6 * 3,
        ALT_BN128_PAIRING_CHECK_ADDRESS: 7 * 3,
        BLAKE2F_ADDRESS: 8 * 3,
        POINT_EVALUATION_ADDRESS: 9 * 3,
    }

    ids.index = ADDRESS_TO_INDEX[ids.address.to_bytes(20, "little")]


@register_hint
def initialize_jumpdests(
    dict_manager: DictManager,
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
    ap: RelocatableValue,
):
    from collections import defaultdict

    from ethereum.cancun.vm.runtime import get_valid_jump_destinations
    from starkware.cairo.common.dict import DictTracker

    bytecode = bytes([memory[ids.bytecode + i] for i in range(ids.bytecode_len)])
    valid_jumpdest = get_valid_jump_destinations(bytecode)

    data = defaultdict(int, {(int(dest),): 1 for dest in valid_jumpdest})
    base = segments.add()
    assert base.segment_index not in dict_manager.trackers
    dict_manager.trackers[base.segment_index] = DictTracker(data=data, current_ptr=base)
    memory[ap] = base


@register_hint
def jumpdest_check_push_last_32_bytes(ids: VmConsts, memory: MemoryDict):
    # Get the 32 previous bytes
    bytecode = [
        memory[ids.bytecode + ids.valid_jumpdest.key - i - 1]
        for i in range(min(ids.valid_jumpdest.key, 32))
    ]
    # Check if any PUSH may prevent this to be a JUMPDEST
    ids.is_no_push_case = int(
        not any([0x60 + i <= byte <= 0x7F for i, byte in enumerate(bytecode)])
    )


@register_hint
def jumpdest_continue_general_case(
    ids: VmConsts,
):
    ids.cond = 1 if ids.i < ids.valid_jumpdest.key else 0


@register_hint
def jumpdest_continue_no_push_case(
    ids: VmConsts,
):
    ids.cond = 0 if ids.offset > 32 or ids.valid_jumpdest.key < ids.offset else 1
