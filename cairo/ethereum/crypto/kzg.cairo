from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U256, U256Struct
from ethereum.utils.numeric import U256_from_be_bytes32, U256_le

using BLSScalar = U256;

// BLS scalar field modulus as a U256 constant (curve order)
const BLS_MODULUS_LOW = 0x53bda402fffe5bfeffffffff00000001;
const BLS_MODULUS_HIGH = 0x73eda753299d7d483339d80809a1d805;

func bytes_to_bls_field{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(b: Bytes32) -> BLSScalar {
    let field_element = U256_from_be_bytes32(b);
    tempvar bls_modulus = U256(new U256Struct(low=BLS_MODULUS_LOW, high=BLS_MODULUS_HIGH));
    let is_valid = U256_le(field_element, bls_modulus);
    with_attr error_message("AssertionError") {
        assert is_valid.value = 1;
    }
    tempvar result = BLSScalar(field_element.value);
    return result;
}
