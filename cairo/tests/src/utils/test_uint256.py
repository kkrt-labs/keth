import pytest
from hypothesis import given, settings
from hypothesis.strategies import integers

from src.utils.uint256 import int_to_uint256, uint256_to_int

pytestmark = pytest.mark.python_vm


class TestUint256:
    class TestUint256ToUint160:
        @pytest.mark.parametrize("n", [0, 2**128, 2**160 - 1, 2**160, 2**256])
        def test_should_cast_value(self, cairo_run, n):
            cairo_run(
                "test__uint256_to_uint160", x=int_to_uint256(n), expected=n % 2**160
            )

    class TestUint256Add:
        @given(
            a=integers(min_value=0, max_value=2**256 - 1),
            b=integers(min_value=0, max_value=2**256 - 1),
        )
        @settings(max_examples=50)
        def test_add(self, cairo_run, a, b):
            low, high, carry = cairo_run(
                "test__uint256_add", a=int_to_uint256(a), b=int_to_uint256(b)
            )
            assert uint256_to_int(low, high) == (a + b) % 2**256
            assert carry == (a + b) // 2**256

    class TestUint256Sub:
        @given(
            a=integers(min_value=0, max_value=2**256 - 1),
            b=integers(min_value=0, max_value=2**256 - 1),
        )
        @settings(max_examples=50)
        def test_sub(self, cairo_run, a, b):
            res = cairo_run(
                "test__uint256_sub", a=int_to_uint256(a), b=int_to_uint256(b)
            )
            assert res["low"] + res["high"] * 2**128 == (a - b) % 2**256

    class TestAssertUint256Le:
        @given(
            a=integers(min_value=0, max_value=2**256 - 1),
            b=integers(min_value=0, max_value=2**256 - 1),
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
