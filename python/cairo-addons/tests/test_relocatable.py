from cairo_addons.vm import Relocatable as RustRelocatable
from hypothesis import assume, given
from hypothesis import strategies as st
from starkware.cairo.lang.vm.relocatable import RelocatableValue as SWRelocatable


# Strategy for generating valid relocatable values
@st.composite
def relocatable_values(draw):
    segment_index = draw(st.integers(min_value=-(2**15), max_value=2**15 - 1))
    offset = draw(st.integers(min_value=-(2**46), max_value=2**46 - 1))
    return SWRelocatable(segment_index, offset)


class TestRelocatable:
    @given(relocatable=...)
    def test_init(self, relocatable: SWRelocatable):
        rust_relocatable = RustRelocatable(
            relocatable.segment_index, relocatable.offset
        )
        assert rust_relocatable.segment_index == relocatable.segment_index
        assert rust_relocatable.offset == relocatable.offset

    @given(rel1=..., rel2=...)
    def test_eq(self, rel1: SWRelocatable, rel2: SWRelocatable):
        rust_rel1 = RustRelocatable(rel1.segment_index, rel1.offset)
        rust_rel2 = RustRelocatable(rel2.segment_index, rel2.offset)
        assert (rust_rel1 == rust_rel2) == (rel1 == rel2)
        assert (rust_rel1 != rust_rel2) == (rel1 != rel2)

    @given(rel=..., integer=st.integers(min_value=0, max_value=2**32 - 1))
    def test_add(self, rel: SWRelocatable, integer: int):
        rust_rel = RustRelocatable(rel.segment_index, rel.offset)
        sw_result = rel + integer
        rust_result = rust_rel + integer
        assert rust_result.segment_index == sw_result.segment_index
        assert rust_result.offset == sw_result.offset

    @given(rel=..., integer=st.integers(min_value=0, max_value=2**32 - 1))
    def test_sub(self, rel: SWRelocatable, integer: int):
        assume(integer <= rel.offset)
        rust_rel = RustRelocatable(rel.segment_index, rel.offset)
        sw_result = rel - integer
        rust_result = rust_rel - integer
        assert rust_result.segment_index == sw_result.segment_index
        assert rust_result.offset == sw_result.offset

    @given(off0=st.integers(0, 2**32 - 1), off1=st.integers(0, 2**32 - 1))
    def test_sub_relocatable(self, off0: int, off1: int):
        assume(off1 <= off0)
        rust_rel = RustRelocatable(0, off0) - RustRelocatable(0, off1)
        sw_result = SWRelocatable(0, off0) - SWRelocatable(0, off1)
        assert rust_rel == sw_result

    @given(rel1=..., rel2=...)
    def test_comparison(self, rel1: SWRelocatable, rel2: SWRelocatable):
        rust_rel1 = RustRelocatable(rel1.segment_index, rel1.offset)
        rust_rel2 = RustRelocatable(rel2.segment_index, rel2.offset)

        assert (rust_rel1 < rust_rel2) == (rel1 < rel2)
        assert (rust_rel1 <= rust_rel2) == (rel1 <= rel2)
        assert (rust_rel1 > rust_rel2) == (rel1 > rel2)
        assert (rust_rel1 >= rust_rel2) == (rel1 >= rel2)

    @given(rel=...)
    def test_format_and_str(self, rel: SWRelocatable):
        rust_rel = RustRelocatable(rel.segment_index, rel.offset)
        assert str(rust_rel) == str(rel)
        assert format(rust_rel) == format(rel)

    @given(rel=...)
    def test_hash(self, rel: SWRelocatable):
        rust_rel = RustRelocatable(rel.segment_index, rel.offset)
        # Test that hash behavior matches by using as dict keys
        sw_dict = {rel: "value"}
        rust_dict = {rust_rel: "value"}

        assert (RustRelocatable(rel.segment_index, rel.offset) in rust_dict) == (
            SWRelocatable(rel.segment_index, rel.offset) in sw_dict
        )
