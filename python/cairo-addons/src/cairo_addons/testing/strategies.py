from hypothesis import strategies as st
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

uint128 = st.integers(min_value=0, max_value=2**128 - 1)
felt = st.integers(min_value=0, max_value=DEFAULT_PRIME - 1)
uint256 = st.integers(min_value=0, max_value=2**256 - 1)
uint384 = st.integers(min_value=0, max_value=2**384 - 1)
