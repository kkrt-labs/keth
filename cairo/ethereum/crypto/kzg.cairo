from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U256, U256Struct
from ethereum.utils.numeric import U256_from_be_bytes32, U256_le

using BLSFieldElement = U256;

// BLS modulus as a U256 constant
const BLS_MODULUS_LOW = 111310594309268602877181240610339684353;
const BLS_MODULUS_HIGH = 154095187621958656428822154526901524485;

func bytes_to_bls_field{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    b: Bytes32
) -> BLSFieldElement {
    let field_element = U256_from_be_bytes32(b);
    tempvar bls_modulus = U256(new U256Struct(low=BLS_MODULUS_LOW, high=BLS_MODULUS_HIGH));
    let is_valid = U256_le(field_element, bls_modulus);
    with_attr error_message("AssertionError") {
        assert is_valid.value = 1;
    }
    return field_element;
}
