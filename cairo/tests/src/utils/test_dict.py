from typing import List, Mapping, Tuple

import pytest
from ethereum_types.numeric import Uint
from hypothesis import given
from hypothesis import strategies as st

from tests.utils.strategies import felt

pytestmark = pytest.mark.python_vm


@given(dict_entries=st.lists(st.tuples(felt, felt, felt)))
def test_prev_values(cairo_run_py, dict_entries: List[Tuple[int, int, int]]):
    prev_values = cairo_run_py("test_prev_values", dict_entries=dict_entries)

    assert all(
        prev_values[i * 3 : i * 3 + 3] == [key, prev, prev]
        for i, (key, prev, _) in enumerate(dict_entries)
    )


@given(original_mapping=..., merge=...)
def test_hashdict_finalize(
    cairo_run_py, original_mapping: Mapping[Uint, Uint], merge: bool
):
    finalized_dict = cairo_run_py("test_hashdict_finalize", original_mapping, merge)

    for original_value, new_value in zip(
        original_mapping.values(), finalized_dict.values()
    ):
        assert new_value == original_value + Uint(int(merge))
