from starkware.cairo.common.dict import DictManager
from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.relocatable import RelocatableValue
from starkware.cairo.lang.vm.vm_consts import VmConsts

from cairo_addons.hints.decorator import register_hint


@register_hint
def dict_new_empty(
    dict_manager: DictManager,
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
    ap: RelocatableValue,
):
    memory[ap] = dict_manager.new_dict(segments, {})


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
def copy_tracker_to_new_ptr(
    dict_manager: DictManager,
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
    ap: RelocatableValue,
):
    """
    Creates a new, empty dictionary segment with a copy of the tracker of the parent dictionary.

    This can be used in two ways:
    1. By copying the memory segment data in the new dict segment, which is expensive.
    2. By using a "fork" mechanism, in which the new dict segment is empty but associated with the
       tracker of the parent dictionary. When the forked dictionary is no longer needed, it should be properly disposed by either:
        a. Squashing and appending to the parent dictionary (to discard updates)
        b. Merging with the parent dictionary (to preserve updates)

    """
    from collections import defaultdict

    from starkware.cairo.common.dict import DictTracker

    current_tracker = dict_manager.get_tracker(ids.parent_dict_end)
    if isinstance(current_tracker.data, defaultdict):
        # Same as new_dict but supports a default value
        base = segments.add()
        assert base.segment_index not in dict_manager.trackers
        copied_data = {
            key: segments.gen_arg(value) for key, value in current_tracker.data.items()
        }
        dict_manager.trackers[base.segment_index] = DictTracker(
            data=defaultdict(
                current_tracker.data.default_factory,
                copied_data,
            ),
            current_ptr=base,
        )
        ids.new_dict_ptr = base
    else:
        ids.new_dict_ptr = dict_manager.new_dict(segments, current_tracker.data)


@register_hint
def merge_dict_tracker_with_parent(
    dict_manager: DictManager,
    ids: VmConsts,
):
    current_dict_tracker = dict_manager.get_tracker(ids.dict_ptr)
    parent_dict_tracker = dict_manager.get_tracker(ids.parent_dict_end)
    parent_dict_tracker.data.update(current_dict_tracker.data)


@register_hint
def update_dict_tracker(
    dict_manager: DictManager,
    ids: VmConsts,
):
    dict_tracker = dict_manager.get_tracker(ids.current_tracker_ptr)
    dict_tracker.current_ptr = ids.new_tracker_ptr.address_
