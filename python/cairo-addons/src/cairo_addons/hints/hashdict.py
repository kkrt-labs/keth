from starkware.cairo.common.dict import DictManager, DictTracker
from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.vm_consts import VmConsts

from cairo_addons.hints.decorator import register_hint


@register_hint
def hashdict_read(dict_manager: DictManager, ids: VmConsts, memory: MemoryDict):
    dict_tracker = dict_manager.get_tracker(ids.dict_ptr)
    dict_tracker.current_ptr += ids.DictAccess.SIZE
    preimage = tuple([memory[ids.key + i] for i in range(ids.key_len)])
    # Not using [] here because it will register the value for that key in the tracker.
    value = dict_tracker.data.get(preimage)
    if value is not None:
        ids.value = value
    else:
        ids.value = dict_tracker.data.default_factory()


@register_hint
def hashdict_read_from_key(
    dict_manager: DictManager,
    ids: VmConsts,
) -> int:
    from cairo_addons.hints.hashdict import _get_preimage_for_hashed_key

    dict_tracker = dict_manager.get_tracker(ids.dict_ptr_stop)
    try:
        preimage = _get_preimage_for_hashed_key(ids.key, dict_tracker) or ids.key
    except Exception:
        ids.value = dict_tracker.data.default_factory()
    else:
        ids.value = dict_tracker.data[preimage]


@register_hint
def hashdict_write(dict_manager: DictManager, ids: VmConsts, memory: MemoryDict):
    dict_tracker = dict_manager.get_tracker(ids.dict_ptr)
    dict_tracker.current_ptr += ids.DictAccess.SIZE
    preimage = tuple([memory[ids.key + i] for i in range(ids.key_len)])
    prev_value = dict_tracker.data.get(preimage)
    if prev_value is not None:
        ids.dict_ptr.prev_value = prev_value
    else:
        ids.dict_ptr.prev_value = dict_tracker.data.default_factory()
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
    from cairo_addons.hints.hashdict import _get_preimage_for_hashed_key

    preimage = list(
        _get_preimage_for_hashed_key(
            ids.key, dict_manager.get_tracker(ids.dict_ptr_stop)
        )
    )
    segments.write_arg(ids.preimage_data, preimage)
    ids.preimage_len = len(preimage)


@register_hint
def copy_hashdict_tracker_entry(dict_manager: DictManager, ids: VmConsts):
    obj_tracker = dict_manager.get_tracker(ids.dict_ptr_stop.address_)
    preimage = _get_preimage_for_hashed_key(ids.dict_ptr.key.value, obj_tracker)
    dict_tracker = dict_manager.get_tracker(ids.branch_ptr.address_)
    dict_tracker.current_ptr += ids.DictAccess.SIZE
    dict_tracker.data[preimage] = obj_tracker.data[preimage]


def _get_preimage_for_hashed_key(
    hashed_key: int,
    dict_tracker: DictTracker,
) -> tuple:
    from starkware.cairo.lang.vm.crypto import poseidon_hash_many

    # Get the key in the dict that matches the hashed value
    preimage = next(
        key
        for key in dict_tracker.data.keys()
        if (
            key[0] == hashed_key
            if len(key) == 1
            else poseidon_hash_many(key) == hashed_key
        )
    )
    return preimage


@register_hint
def track_precompiles(
    dict_manager: DictManager,
    ids: VmConsts,
):
    from ethereum.cancun.vm.precompiled_contracts.mapping import PRE_COMPILED_CONTRACTS

    dict_tracker = dict_manager.get_tracker(ids.dict_ptr)
    for key in PRE_COMPILED_CONTRACTS.keys():
        preimage = (int.from_bytes(key, "little"),)
        dict_tracker.data[preimage] = 1

    dict_tracker.current_ptr += len(PRE_COMPILED_CONTRACTS) * ids.DictAccess.SIZE
