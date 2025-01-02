from cairo_addons.vm import MaybeRelocatable, MemorySegmentManager, Relocatable


class TestMemorySegmentManager:
    def test_create_memory_segment_manager(self):
        memory = MemorySegmentManager()
        assert memory is not None

    def test_add_segment(self):
        memory = MemorySegmentManager()
        ptr = memory.add()
        assert isinstance(ptr, Relocatable)
        assert ptr.segment_index == 0
        assert ptr.offset == 0

    def test_add_temporary_segment(self):
        memory = MemorySegmentManager()
        ptr = memory.add_temporary_segment()
        assert isinstance(ptr, Relocatable)
        assert ptr.segment_index == -1
        assert ptr.offset == 0

    def test_load_data(self):
        memory = MemorySegmentManager()
        ptr = memory.add()
        data = [MaybeRelocatable.from_int(x) for x in [1, 2, 3, 4]]
        next_ptr = memory.load_data(ptr, data)
        assert isinstance(next_ptr, Relocatable)
        assert next_ptr.segment_index == ptr.segment_index
        assert next_ptr.offset == 4

    def test_compute_effective_sizes(self):
        memory = MemorySegmentManager()
        ptr = memory.add()
        data = [MaybeRelocatable.from_int(x) for x in [1, 2, 3, 4]]
        memory.load_data(ptr, data)
        memory.compute_effective_sizes()
        assert memory.get_segment_used_size(0) == 4
        assert memory.get_segment_size(0) == 4
