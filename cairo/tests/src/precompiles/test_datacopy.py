import hypothesis.strategies as st
import pytest
from hypothesis import given, settings

pytestmark = pytest.mark.python_vm


class TestDataCopy:
    @given(calldata=st.binary(max_size=100))
    @settings(max_examples=20)
    def test_datacopy(self, cairo_run, calldata):
        cairo_run("test__datacopy_impl", calldata=list(calldata))
