from hypothesis import given, assume
from hypothesis.strategies import integers

from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME
from ethereum.base_types import U256
from tests.utils.errors import cairo_error
from tests.utils.strategies import felt

class TestSignature:
    @given(msg_hash=..., r=..., s=..., y_parity=integers(min_value=2, max_value=DEFAULT_PRIME - 1), eth_address=felt)
    def test_should_raise_with_invalid_y_parity(
        self, cairo_run, msg_hash: U256, r: U256, s: U256, y_parity, eth_address
    ):
        assume(r != 0 and s != 0)
        with cairo_error("Invalid y_parity"):
            cairo_run("test__verify_eth_signature_uint256", msg_hash, r, s, y_parity, eth_address)
