import pytest
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

from cairo_addons.rust_bindings.vm import CairoRunner, Relocatable


@pytest.fixture
def runner(rust_program):
    return CairoRunner(rust_program)


class TestMemorySegmentManager:
    def test_add_segment(self, runner):
        ptr = runner.segments.add()
        assert isinstance(ptr, Relocatable)
        assert ptr.segment_index == 0
        assert ptr.offset == 0

    def test_add_temporary_segment(self, runner):
        ptr = runner.segments.add_temporary_segment()
        assert isinstance(ptr, Relocatable)
        assert ptr.segment_index == -1
        assert ptr.offset == 0

    def test_load_data_int(self, runner):
        ptr = runner.segments.add()
        data = [1, 2, 3, 4]
        next_ptr = runner.segments.load_data(ptr, data)
        assert isinstance(next_ptr, Relocatable)
        assert next_ptr.segment_index == ptr.segment_index
        assert next_ptr.offset == 4

    def test_load_data_biguint(self, runner):
        ptr = runner.segments.add()
        data = [2**128, DEFAULT_PRIME - 1]
        next_ptr = runner.segments.load_data(ptr, data)
        assert isinstance(next_ptr, Relocatable)
        assert next_ptr.segment_index == ptr.segment_index
        assert next_ptr.offset == 2

    def test_compute_effective_sizes(self, runner):
        ptr = runner.segments.add()
        data = [1, 2, 3, 4]
        runner.segments.load_data(ptr, data)
        sizes = runner.segments.compute_effective_sizes()
        assert sizes == [4]
        assert runner.segments.get_segment_used_size(0) == 4
        assert runner.segments.get_segment_size(0) == 4

    def test_memory_wrapper(self, runner):
        ptr = runner.segments.add()
        runner.segments.load_data(ptr, [1, 2, 3, 4])
        assert runner.segments.memory.get(ptr) == 1
