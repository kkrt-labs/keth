import pytest
from hypothesis import given
from starkware.cairo.lang.vm.relocatable import RelocatableValue

from cairo_addons.testing.hints import patch_hint
from cairo_addons.vm import Relocatable as RustRelocatable
from tests.utils.strategies import felt


class TestComparison:
    @given(value=felt)
    def test_is_zero(self, cairo_run, value):
        assert (value == 0) == cairo_run("is_zero", value)

    def test_is_ptr_equal_on_equal_pointers(self, cairo_run):
        lhs_ptr = RustRelocatable(0, 0)
        rhs_ptr = RustRelocatable(0, 0)
        is_eq, comparison_ok = cairo_run("is_ptr_equal", lhs_ptr, rhs_ptr)
        assert is_eq and comparison_ok

    def test_is_ptr_equal_unequal_pointers_same_segment(self, cairo_run):
        lhs_ptr = RustRelocatable(0, 0)
        rhs_ptr = RustRelocatable(0, 1)
        is_eq, comparison_ok = cairo_run("is_ptr_equal", lhs_ptr, rhs_ptr)
        assert not is_eq and comparison_ok

    def test_is_ptr_equal_diff_segments(self, cairo_run):
        lhs_ptr = RustRelocatable(0, 0)
        rhs_ptr = RustRelocatable(1, 0)
        is_eq, comparison_ok = cairo_run("is_ptr_equal", lhs_ptr, rhs_ptr)
        assert not is_eq and not comparison_ok

    def test_bad_hint_should_fail_on_unequal_segments(
        self, cairo_run, cairo_programs, rust_programs
    ):
        lhs_ptr = RelocatableValue(0, 0)
        rhs_ptr = RelocatableValue(1, 0)
        with patch_hint(
            cairo_programs,
            rust_programs,
            "compare_relocatable_segment_index",
            "ids.segment_equal = 1",
        ):
            with pytest.raises(Exception) as e:
                cairo_run("is_ptr_equal", lhs_ptr, rhs_ptr)
            assert (
                "Can only subtract two relocatable values of the same segment"
                in str(e.value)
            )
