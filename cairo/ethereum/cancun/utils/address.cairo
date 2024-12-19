from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.math_cmp import is_nn, is_not_zero

from ethereum_types.bytes import Bytes32, Bytes, BytesStruct
from ethereum_types.numeric import Uint, UnionUintU256
from ethereum.cancun.fork_types import Address
from ethereum.crypto.hash import keccak256
from ethereum.utils.numeric import divmod

from src.utils.bytes import (
    felt_to_bytes20_little,
    bytes_to_felt,
    felt_to_bytes,
    uint256_to_bytes32_little,
)

func to_address{range_check_ptr}(data: UnionUintU256) -> Address {
    alloc_locals;
    let (local bytes_data) = alloc();

    if (cast(data.value.uint, felt) != 0) {
        felt_to_bytes20_little(bytes_data, data.value.uint.value);
        let res = bytes_to_felt(20, bytes_data);
        tempvar address = Address(res);
        return address;
    }

    if (cast(data.value.u256.value, felt) != 0) {
        uint256_to_bytes32_little(bytes_data, [data.value.u256.value]);
        let res = bytes_to_felt(20, bytes_data);
        tempvar address = Address(res);
        return address;
    }

    with_attr error_message("Type not valid") {
        assert 0 = 1;
        tempvar address = Address(0);
        return address;
    }
}

func compute_contract_address{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*
}(address: Address, nonce: Uint) -> Address {
    alloc_locals;
    local message_len;
    let (message: felt*) = alloc();

    assert [message + 1] = 0x80 + 20;
    felt_to_bytes20_little(message + 2, address.value);
    let encode_nonce = is_nn(nonce.value - 0x80);

    if (encode_nonce != FALSE) {
        let nonce_len = felt_to_bytes(message + 2 + 20 + 1, nonce.value);
        assert [message + 2 + 20] = 0x80 + nonce_len;
        assert message_len = 1 + 1 + 20 + 1 + nonce_len;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        let is_nonce_not_zero = is_not_zero(nonce.value);
        let encoded_nonce = nonce.value * is_nonce_not_zero + (1 - is_nonce_not_zero) * 0x80;
        assert [message + 2 + 20] = encoded_nonce;
        assert message_len = 1 + 1 + 20 + 1;
        tempvar range_check_ptr = range_check_ptr;
    }

    let range_check_ptr = [ap - 1];
    assert message[0] = message_len + 0xc0 - 1;
    tempvar encoded_bytes = Bytes(new BytesStruct(message, message_len));
    let computed_address = keccak256(encoded_bytes);
    let (low, _) = divmod(computed_address.value.low, 256 ** 12);
    let padded_address = low + computed_address.value.high * 256 ** 4;

    tempvar contract_address = Address(padded_address);
    return contract_address;
}

func compute_create2_contract_address{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*
}(address: Address, salt: Bytes32, call_data: Bytes) -> Address {
    alloc_locals;
    let (preimage: felt*) = alloc();

    assert [preimage] = 0xff;
    felt_to_bytes20_little(preimage + 1, address.value);
    uint256_to_bytes32_little(preimage + 1 + 20, [salt.value]);
    let call_data_hash = keccak256(call_data);
    uint256_to_bytes32_little(preimage + 1 + 20 + 32, [call_data_hash.value]);
    let preimage_len = 1 + 20 + 32 + 32;
    tempvar preimage_bytes = Bytes(new BytesStruct(preimage, preimage_len));
    let computed_address = keccak256(preimage_bytes);
    let (low, _) = divmod(computed_address.value.low, 256 ** 12);
    let padded_address = low + computed_address.value.high * 256 ** 4;

    tempvar contract_address = Address(padded_address);
    return contract_address;
}
