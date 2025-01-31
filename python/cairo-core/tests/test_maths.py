import pytest
from hypothesis import assume, given, settings
from hypothesis import strategies as st
from src.utils.uint256 import int_to_uint256
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

from cairo_addons.testing.hints import patch_hint
from cairo_addons.testing.strategies import felt, uint128
from tests.utils.errors import cairo_error

pytestmark = pytest.mark.python_vm


class TestMaths:

    class TestSign:
        @given(value=felt)
        def test_sign(self, cairo_run, value):
            assume(value != 0)
            sign = cairo_run("test__sign", value=value)
            assert (
                sign % DEFAULT_PRIME
                == (2 * (0 <= value < DEFAULT_PRIME // 2) - 1) % DEFAULT_PRIME
            )

    class TestScalarToEpns:
        @given(scalar=uint128)
        def test_scalar_to_epns(self, cairo_run, scalar):
            sum_p, sum_n, p_sign, n_sign = cairo_run(
                "test__scalar_to_epns", scalar=scalar
            )
            assert (
                sum_p * p_sign - sum_n * n_sign
            ) % DEFAULT_PRIME == scalar % DEFAULT_PRIME

    class TestAssertUint256Le:
        @given(
            a=st.integers(min_value=0, max_value=2**256 - 1),
            b=st.integers(min_value=0, max_value=2**256 - 1),
        )
        @settings(max_examples=50)
        def test_assert_uint256_le(self, cairo_run, a, b):
            if a > b:
                with pytest.raises(Exception):
                    cairo_run(
                        "test__assert_uint256_le",
                        a=int_to_uint256(a),
                        b=int_to_uint256(b),
                    )
            else:
                cairo_run(
                    "test__assert_uint256_le", a=int_to_uint256(a), b=int_to_uint256(b)
                )

    @given(i=st.integers(min_value=0, max_value=251))
    def test_pow2(self, cairo_run, i):
        res = cairo_run("test__pow2", i=i)
        assert res == 2**i

    @given(i=st.integers(min_value=0, max_value=31))
    def test_pow256(self, cairo_run, i):
        res = cairo_run("test__pow256", i=i)
        assert res == 256**i

    @given(
        value=st.integers(min_value=0, max_value=2**248 - 1),
        len_=st.integers(min_value=0, max_value=31),
    )
    def test_felt252_to_bytes_le(self, cairo_run, value, len_):
        res = cairo_run("test__felt252_to_bytes_le", value=value, len=len_)
        try:
            expected = value.to_bytes(len_, "little")
        except OverflowError:
            # If value doesn't fit in len_ bytes, truncate it
            mask = (1 << (len_ * 8)) - 1
            truncated_value = value & mask
            expected = truncated_value.to_bytes(len_, "little")

        assert bytes(res) == expected

    @given(
        value=st.integers(min_value=0, max_value=2**248 - 1),
        len_=st.integers(min_value=32, max_value=DEFAULT_PRIME - 1),
    )
    def test_felt252_to_bytes_le_should_panic_on_len_too_big(
        self, cairo_run, value, len_
    ):
        with cairo_error(message="felt252_to_bytes_le: len must be < 32"):
            cairo_run("test__felt252_to_bytes_le", value=value, len=len_)

    @given(
        value=st.integers(min_value=1, max_value=2**248 - 1),
        len_=st.integers(min_value=1, max_value=31),
    )
    def test_felt252_to_bytes_le_should_panic_on_wrong_output(
        self, cairo_program, cairo_run, value, len_
    ):
        with patch_hint(
            cairo_program,
            "felt252_to_bytes_le",
            """
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME
current_value = ids.value
for i in range(0, ids.len):
    memory[ids.output + i] = res_i = (int(current_value - 1) % DEFAULT_PRIME) % ids.base
    current_value= current_value // ids.base
            """,
        ), cairo_error(message="felt252_to_bytes_le: bad output"):
            cairo_run("test__felt252_to_bytes_le", value=value, len=len_)

    @given(
        value=st.integers(min_value=0, max_value=2**248 - 1),
        len_=st.integers(min_value=1, max_value=31),
    )
    def test_felt252_to_bytes_be(self, cairo_run, value, len_):
        res = cairo_run("test__felt252_to_bytes_be", value=value, len=len_)
        try:
            expected = value.to_bytes(len_, "big")
        except OverflowError:
            # If value doesn't fit in len_ bytes, truncate it
            mask = (1 << (len_ * 8)) - 1
            truncated_value = value & mask
            expected = truncated_value.to_bytes(len_, "big")

        assert bytes(res) == expected

    @given(
        value=st.integers(min_value=0, max_value=2**248 - 1),
        len_=st.integers(min_value=32, max_value=DEFAULT_PRIME - 1),
    )
    def test_felt252_to_bytes_be_should_panic_on_len_too_big(
        self, cairo_run, value, len_
    ):
        with cairo_error(message="felt252_to_bytes_be: len must be < 32"):
            cairo_run("test__felt252_to_bytes_be", value=value, len=len_)

    @given(
        value=st.integers(min_value=1, max_value=2**248 - 1),
        len_=st.integers(min_value=1, max_value=31),
    )
    def test_felt252_to_bytes_be_should_panic_on_wrong_output(
        self, cairo_program, cairo_run, value, len_
    ):
        with patch_hint(
            cairo_program,
            "felt252_to_bytes_be",
            """
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

current_value = ids.value
for i in range(ids.len - 1, -1, -1):
    memory[ids.output + i] = res_i = (int(current_value - 1) % DEFAULT_PRIME) % ids.base
    assert res_i < ids.bound, f"felt_to_bytes: Limb {res_i} is out of range."
    current_value = current_value // ids.base
""",
        ), cairo_error(message="felt252_to_bytes_be: bad output"):
            cairo_run("test__felt252_to_bytes_be", value=value, len=len_)
