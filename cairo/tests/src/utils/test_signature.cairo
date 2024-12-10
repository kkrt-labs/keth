
from ethereum_types.numeric import U256

from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.cairo_secp.bigint import uint256_to_bigint

from src.utils.signature import Signature, Internals

func test__public_key_point_to_eth_address{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*
}(x: U256, y: U256) -> felt {
    let eth_address = Internals.public_key_point_to_eth_address(x=[x.value], y=[y.value]);

    return eth_address;
}

func test__verify_eth_signature_uint256{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*
}(msg_hash: U256, r: U256, s: U256, y_parity: felt, eth_address: felt) {
    Signature.verify_eth_signature_uint256(
        [msg_hash.value], [r.value], [s.value], y_parity, eth_address
    );
    return ();
}

func test__try_recover_eth_address{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*
}(msg_hash: U256, r: U256, s: U256, y_parity: felt) -> (success: felt, address: felt) {
    let (msg_hash_bigint) = uint256_to_bigint([msg_hash.value]);
    let (r_bigint) = uint256_to_bigint([r.value]);
    let (s_bigint) = uint256_to_bigint([s.value]);

    let (success, address) = Signature.try_recover_eth_address(
        msg_hash=msg_hash_bigint, r=r_bigint, s=s_bigint, y_parity=y_parity
    );

    return (success=success, address=address);
}
