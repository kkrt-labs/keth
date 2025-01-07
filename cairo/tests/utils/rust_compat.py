from typing import Optional, Union

from cairo_addons.vm import DictManager as RustDictManager
from cairo_addons.vm import DictTracker as RustDictTracker
from cairo_addons.vm import MemorySegmentManager as RustMemorySegmentManager
from starkware.cairo.common.dict import DictManager, DictTracker
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.relocatable import MaybeRelocatable, RelocatableValue


class SegmentsCompat:
    py_segments_manager: MemorySegmentManager
    rust_segments_manager: RustMemorySegmentManager

    def __init__(self, segments: Union[RustMemorySegmentManager, MemorySegmentManager]):
        if isinstance(segments, RustMemorySegmentManager):
            self.py_segments_manager = None
            self.rust_segments_manager = segments
        else:
            self.py_segments_manager = segments
            self.rust_segments_manager = None

    def get(self, addr) -> Optional[MaybeRelocatable]:
        if self.rust_segments_manager:
            return self.rust_segments_manager.get(addr)
        else:
            return self.py_segments_manager.memory.get(addr)


class DictManagerCompat:
    py_dict_manager: DictManager
    rust_dict_manager: RustDictManager

    def __init__(self, dict_manager: Union[DictManager, RustDictManager]):
        if isinstance(dict_manager, RustDictManager):
            self.py_dict_manager = None
            self.rust_dict_manager = dict_manager
        else:
            self.py_dict_manager = dict_manager
            self.rust_dict_manager = None

    def insert(
        self, dict_ptr: RelocatableValue, tracker: Union[DictTracker, RustDictTracker]
    ):
        if self.rust_dict_manager:
            self.rust_dict_manager.insert(dict_ptr, tracker)
        else:
            self.py_dict_manager.trackers[dict_ptr.segment_index] = tracker
