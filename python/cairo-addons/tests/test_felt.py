from cairo_addons.vm import Felt
from hypothesis import given
from hypothesis import strategies as st
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

felt = st.integers(min_value=0, max_value=DEFAULT_PRIME - 1)


class TestFelt:
    @given(value=felt)
    def test_init(self, value: int):
        felt = Felt(value)
        assert int(felt) == value

    @given(a=felt, b=felt)
    def test_addition(self, a: int, b: int):
        felt_a = Felt(a)
        felt_b = Felt(b)
        assert int(felt_a + felt_b) == (a + b) % DEFAULT_PRIME

    @given(a=felt, b=felt)
    def test_subtraction(self, a: int, b: int):
        felt_a = Felt(a)
        felt_b = Felt(b)
        assert int(felt_a - felt_b) == (a - b) % DEFAULT_PRIME

    @given(a=felt, b=felt)
    def test_multiplication(self, a: int, b: int):
        felt_a = Felt(a)
        felt_b = Felt(b)
        assert int(felt_a * felt_b) == (a * b) % DEFAULT_PRIME

    @given(a=felt, b=felt)
    def test_comparison_operations(self, a: int, b: int):
        felt_a = Felt(a)
        felt_b = Felt(b)
        assert (felt_a == felt_b) == (a == b)
        assert (felt_a != felt_b) == (a != b)

    @given(value=felt)
    def test_hash(self, value: int):
        felt = Felt(value)
        # Test that hash behavior matches by using as dict keys
        int_dict = {value: "value"}
        felt_dict = {felt: "value"}

        assert (Felt(value) in felt_dict) == (value in int_dict)
        assert felt_dict[felt] == int_dict[value]

    @given(value=felt)
    def test_format_and_str(self, value: int):
        felt = Felt(value)
        assert str(felt) == str(value)
        assert format(felt) == format(value)

    @given(value=felt)
    def test_neg(self, value: int):
        felt = Felt(value)
        assert int(-felt) == (-value) % DEFAULT_PRIME
