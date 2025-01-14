from cairo_addons.hints.decorator import register_hint
from starkware.cairo.common.dict import DictManager
from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.relocatable import RelocatableValue
from starkware.cairo.lang.vm.vm_consts import VmConsts


@register_hint
def dict_new_empty(
    dict_manager: DictManager,
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
    ap: RelocatableValue,
):
    if "__dict_manager" not in globals():
        from starkware.cairo.common.dict import DictManager

        __dict_manager = DictManager()

    memory[ap] = __dict_manager.new_dict(segments, {})


@register_hint
def dict_copy(dict_manager: DictManager, ids: VmConsts):
    from starkware.cairo.common.dict import DictTracker

    if ids.new_start.address_.segment_index in dict_manager.trackers:
        raise ValueError(
            f"Segment {ids.new_start.address_.segment_index} already exists in dict_manager.trackers"
        )

    data = dict_manager.trackers[ids.dict_start.address_.segment_index].data.copy()
    dict_manager.trackers[ids.new_start.address_.segment_index] = DictTracker(
        data=data,
        current_ptr=ids.new_end.address_,
    )


@register_hint
def dict_squash(
    dict_manager: DictManager,
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
    ap: RelocatableValue,
):
    from starkware.cairo.common.dict import DictTracker

    data = dict_manager.get_dict(ids.dict_accesses_end).copy()
    base = segments.add()
    assert base.segment_index not in dict_manager.trackers
    dict_manager.trackers[base.segment_index] = DictTracker(data=data, current_ptr=base)
    memory[ap] = base


@register_hint
def copy_dict_segment(
    dict_manager: DictManager,
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
    ap: RelocatableValue,
):
    dict_tracker = dict_manager.get_tracker(ids.original_mapping.dict_ptr)
    copied_data = dict_tracker.data
    ids.new_dict_ptr = dict_manager.new_dict(segments, copied_data)
