from cairo_addons.hints.decorator import register_hint
from starkware.cairo.common.dict import DictManager
from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.vm_consts import VmConsts


@register_hint
def hashdict_read(dict_manager: DictManager, ids: VmConsts, memory: MemoryDict):
    dict_tracker = dict_manager.get_tracker(ids.dict_ptr)
    dict_tracker.current_ptr += ids.DictAccess.SIZE
    preimage = tuple([memory[ids.key + i] for i in range(ids.key_len)])
    # Not using [] here because it will register the value for that key in the tracker.
    ids.value = dict_tracker.data.get(preimage, dict_tracker.data.default_factory())


@register_hint
def hashdict_get(dict_manager: DictManager, ids: VmConsts, memory: MemoryDict):
    from collections import defaultdict

    dict_tracker = dict_manager.get_tracker(ids.dict_ptr)
    dict_tracker.current_ptr += ids.DictAccess.SIZE
    preimage = tuple([memory[ids.key + i] for i in range(ids.key_len)])
    if isinstance(dict_tracker.data, defaultdict):
        ids.value = dict_tracker.data[preimage]
    else:
        ids.value = dict_tracker.data.get(preimage, 0)


@register_hint
def hashdict_write(dict_manager: DictManager, ids: VmConsts, memory: MemoryDict):
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
def get_keys_for_address_prefix(
    dict_manager: DictManager,
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
):
    dict_tracker = dict_manager.get_tracker(ids.dict_ptr)
    prefix = tuple([memory[ids.prefix + i] for i in range(ids.prefix_len)])
    matching_preimages = [
        key for key in dict_tracker.data.keys() if key[: len(prefix)] == prefix
    ]
    base = segments.add()
    for i, preimage in enumerate(matching_preimages):
        ptr = segments.add()
        bytes32_base = segments.add()
        segments.write_arg(bytes32_base, preimage[1:])
        segments.write_arg(ptr, [preimage[0], bytes32_base])
        memory[base + i] = ptr
    ids.keys_len = len(matching_preimages)
    ids.keys = base


@register_hint
def get_preimage_for_key(
    dict_manager: DictManager, ids: VmConsts, segments: MemorySegmentManager
):
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
def copy_hashdict_tracker_entry(dict_manager: DictManager, ids: VmConsts):
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
