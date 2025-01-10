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
