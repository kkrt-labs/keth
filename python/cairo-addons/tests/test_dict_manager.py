import pytest
from cairo_addons.vm import CairoRunner, DictTracker


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
            DictTracker(
                keys=list(data.keys()),
                values=list(data.values()),
                current_ptr=current_ptr,
            ),
        )
        assert runner.dict_manager.get_value(current_ptr.segment_index, 1) == data[1]
        assert runner.dict_manager.get_value(current_ptr.segment_index, 2) == data[2]

    def test_should_insert_default_dict(self, runner):
        dict_ptr = runner.segments.add()
        runner.dict_manager.insert(
            dict_ptr.segment_index,
            DictTracker(
                keys=[], values=[], current_ptr=dict_ptr, default_value=0xABDE1
            ),
        )
        assert runner.dict_manager.get_value(dict_ptr.segment_index, 1) == 0xABDE1

    def test_should_raise_existing_dict(self, runner):
        dict_ptr = runner.segments.add()
        runner.dict_manager.insert(
            dict_ptr.segment_index,
            DictTracker(keys=[], values=[], current_ptr=dict_ptr),
        )
        with pytest.raises(ValueError, match="Segment index already exists"):
            runner.dict_manager.insert(
                dict_ptr.segment_index,
                DictTracker(keys=[], values=[], current_ptr=dict_ptr),
            )
