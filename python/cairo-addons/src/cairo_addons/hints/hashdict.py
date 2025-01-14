from cairo_addons.hints.decorator import register_hint
from starkware.cairo.common.dict import DictManager
from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.relocatable import RelocatableValue
from starkware.cairo.lang.vm.vm_consts import VmConsts


@register_hint
def hashdict_read(
    dict_manager: DictManager,
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
    ap: RelocatableValue,
) -> int:
    dict_tracker = dict_manager.get_tracker(ids.dict_ptr)
    dict_tracker.current_ptr += ids.DictAccess.SIZE
    preimage = tuple([memory[ids.key + i] for i in range(ids.key_len)])
    # Not using [] here because it will register the value for that key in the tracker.
    ids.value = dict_tracker.data.get(preimage, dict_tracker.data.default_factory())


@register_hint
def hashdict_write(
    dict_manager: DictManager,
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
    ap: RelocatableValue,
) -> int:
    from collections import defaultdict
    dict_tracker = dict_manager.get_tracker(ids.dict_ptr)
    dict_tracker.current_ptr += ids.DictAccess.SIZE
    preimage = tuple([memory[ids.key + i] for i in range(ids.key_len)])
    if isinstance(dict_tracker.data, defaultdict):
        ids.dict_ptr.prev_value = dict_tracker.data[preimage]
    else:
        ids.dict_ptr.prev_value = 0
    dict_tracker.data[preimage] = ids.new_value


@register_hint
def get_preimage_for_key(
    dict_manager: DictManager,
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
    ap: RelocatableValue,
) -> int:
    from starkware.cairo.lang.vm.crypto import poseidon_hash_many

    hashed_value = ids.key
    dict_tracker = dict_manager.get_tracker(ids.dict_ptr_stop)
    # Get the key in the dict that matches the hashed value
    preimage = bytes(
        next(
            key
            for key in dict_tracker.data.keys()
            if poseidon_hash_many(key) == hashed_value
        )
    )
    segments.write_arg(ids.preimage_data, preimage)
    ids.preimage_len = len(preimage)


@register_hint
def copy_hashdict_tracker_entry(
    dict_manager: DictManager,
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
    ap: RelocatableValue,
) -> int:
    from starkware.cairo.lang.vm.crypto import poseidon_hash_many

    obj_tracker = dict_manager.get_tracker(ids.dict_ptr_stop.address_)
    dict_tracker = dict_manager.get_tracker(ids.branch_ptr.address_)
    dict_tracker.current_ptr += ids.DictAccess.SIZE
    preimage = next(
        key
        for key in obj_tracker.data.keys()
        if poseidon_hash_many(key) == ids.dict_ptr.key.value
    )
    dict_tracker.data[preimage] = obj_tracker.data[preimage]
