from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

from ethereum.base_types import U256
from src.utils.signature import Signature

func test__verify_eth_signature_uint256{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    msg_hash: U256, r: U256, s: U256, y_parity: felt, eth_address: felt
) {
    Signature.verify_eth_signature_uint256(
        [msg_hash.value], [r.value], [s.value], y_parity, eth_address
    );
    return ();
}
