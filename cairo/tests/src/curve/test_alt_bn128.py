import hypothesis.strategies as st
import pytest

from ethereum.crypto.alt_bn128 import ALT_BN128_CURVE_ORDER as AltBn128N
from ethereum.crypto.alt_bn128 import BNF as AltBn128P
from ethereum.crypto.alt_bn128 import BNP as AltBn128
from src.utils.uint256 import uint256_to_int
from src.utils.uint384 import uint384_to_int

pytestmark = pytest.mark.python_vm


uint384 = st.integers(min_value=0, max_value=2**384 - 1)
uint256 = st.integers(min_value=0, max_value=2**256 - 1)


class TestAltBn128:

    class TestConstants:
        def test_get_P(self, cairo_run):
            assert uint384_to_int(*cairo_run("test__get_P").values()) == AltBn128P.PRIME

        def test_get_P_256(self, cairo_run):
            assert (
                uint256_to_int(*cairo_run("test__get_P_256").values())
                == AltBn128P.PRIME
            )

        def test_get_N(self, cairo_run):
            assert uint384_to_int(*cairo_run("test__get_N").values()) == AltBn128N

        def test_get_N_256(self, cairo_run):
            assert uint256_to_int(*cairo_run("test__get_N_256").values()) == AltBn128N

        def test_get_A(self, cairo_run):
            assert uint384_to_int(*cairo_run("test__get_A").values()) == AltBn128.A

        def test_get_B(self, cairo_run):
            assert uint384_to_int(*cairo_run("test__get_B").values()) == AltBn128.B

        def test_get_G(self, cairo_run):
            assert uint384_to_int(*cairo_run("test__get_G").values()) == 3

        def test_get_P_MIN_ONE(self, cairo_run):
            assert (
                uint384_to_int(*cairo_run("test__get_P_MIN_ONE").values())
                == AltBn128P.PRIME - 1
            )
