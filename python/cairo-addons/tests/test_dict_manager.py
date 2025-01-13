import pytest
from cairo_addons.vm import CairoRunner
from cairo_addons.vm import DictManager as RustDictManager
from cairo_addons.vm import DictTracker as RustDictTracker
from cairo_addons.vm import Relocatable as RustRelocatable
from starkware.cairo.common.dict import DictManager, DictTracker


@pytest.fixture
def runner(rust_program):
    return CairoRunner(rust_program)


class TestDictManager:

    def test_should_insert_dict(self, runner):
        data = {1: 3, 2: 4}
        initial_data = [1, 3, 3, 2, 4, 4]
        dict_ptr = runner.segments.add()
        runner.segments.load_data(dict_ptr, initial_data)
        current_ptr = dict_ptr + len(initial_data)
        runner.dict_manager.insert(
            dict_ptr.segment_index,
            RustDictTracker(
                data=data,
                current_ptr=current_ptr,
            ),
        )
        assert runner.dict_manager.get_value(current_ptr.segment_index, 1) == data[1]
        assert runner.dict_manager.get_value(current_ptr.segment_index, 2) == data[2]

    def test_should_insert_default_dict(self, runner):
        dict_ptr = runner.segments.add()
        runner.dict_manager.insert(
            dict_ptr.segment_index,
            RustDictTracker(data={}, current_ptr=dict_ptr, default_value=0xABDE1),
        )
        assert runner.dict_manager.get_value(dict_ptr.segment_index, 1) == 0xABDE1

    def test_should_raise_existing_dict(self, runner):
        dict_ptr = runner.segments.add()
        runner.dict_manager.insert(
            dict_ptr.segment_index,
            RustDictTracker(data={}, current_ptr=dict_ptr),
        )
        with pytest.raises(ValueError, match="Segment index already exists"):
            runner.dict_manager.insert(
                dict_ptr.segment_index,
                RustDictTracker(data={}, current_ptr=dict_ptr),
            )

    def test_api_compatibility(self):
        rust_manager = RustDictManager()
        python_manager = DictManager()
        data = {1: 4, 2: 5, 3: 6}
        dict_ptr = RustRelocatable(segment_index=0, offset=0)

        rust_tracker = RustDictTracker(
            data=data, current_ptr=dict_ptr, default_value=None
        )
        python_tracker = DictTracker(data=data, current_ptr=dict_ptr)

        assert rust_tracker.current_ptr == python_tracker.current_ptr
        assert rust_tracker.data == python_tracker.data
        assert str(rust_tracker) == str(python_tracker)
        rust_manager.trackers[dict_ptr.segment_index] = rust_tracker
        python_manager.trackers[dict_ptr.segment_index] = python_tracker
        assert str(rust_manager.trackers[dict_ptr.segment_index]) == str(
            python_manager.trackers[dict_ptr.segment_index]
        )
