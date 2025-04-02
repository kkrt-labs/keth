from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from ethereum_types.bytes import Bytes32, Bytes
from ethereum_types.numeric import U256, U256Struct, U384
from ethereum.utils.numeric import U256_from_be_bytes32, U256_le, U384_from_be_bytes
from cairo_ec.curve.bls12_381 import bls12_381

using BLSScalar = U256;

func bytes_to_bls_field{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(b: Bytes32) -> BLSScalar {
    let field_element = U256_from_be_bytes32(b);
    tempvar bls_modulus = U256(new U256Struct(low=bls12_381.N_LOW_128, high=bls12_381.N_HIGH_128));
    let is_valid = U256_le(field_element, bls_modulus);
    with_attr error_message("AssertionError") {
        assert is_valid.value = 1;
    }
    tempvar result = BLSScalar(field_element.value);
    return result;
}

// Diverge from specs: limited to 48 bytes
func os2ip{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(b: Bytes) -> U384 {
    let result = U384_from_be_bytes(b);
    return result;
}
