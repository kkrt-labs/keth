from ethereum_types.numeric import U256

from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    KeccakBuiltin,
    ModBuiltin,
    PoseidonBuiltin,
)
from starkware.cairo.common.cairo_secp.bigint import uint256_to_bigint

from src.utils.signature import Signature
from src.utils.uint256 import uint256_eq
from cairo_ec.uint384 import uint256_to_uint384
from cairo_ec.curve.secp256k1 import public_key_point_to_eth_address_be

func test__public_key_point_to_eth_address{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*
}(x: U256, y: U256) -> felt {
    let eth_address = public_key_point_to_eth_address_be(x=[x.value], y=[y.value]);

    return eth_address;
}

func test__verify_eth_signature_uint256{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(msg_hash: U256, r: U256, s: U256, y_parity: felt, eth_address: felt) {
    Signature.verify_eth_signature_uint256(
        [msg_hash.value], [r.value], [s.value], y_parity, eth_address
    );
    return ();
}

func test__try_recover_eth_address{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(msg_hash: U256, r: U256, s: U256, y_parity: felt) -> (success: felt, address: felt) {
    let msg_hash_uint384 = uint256_to_uint384([msg_hash.value]);
    let r_uint384 = uint256_to_uint384([r.value]);
    let s_uint384 = uint256_to_uint384([s.value]);

    let (success, address) = Signature.try_recover_eth_address(
        msg_hash=msg_hash_uint384, r=r_uint384, s=s_uint384, y_parity=y_parity
    );

    return (success=success, address=address);
}
