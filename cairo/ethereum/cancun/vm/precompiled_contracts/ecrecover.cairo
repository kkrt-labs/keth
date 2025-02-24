from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    KeccakBuiltin,
    ModBuiltin,
    PoseidonBuiltin,
)
from starkware.cairo.common.math_cmp import is_le_felt
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memset import memset
from ethereum.cancun.vm.evm_impl import Evm, EvmImpl
from ethereum.exceptions import EthereumException
from ethereum.cancun.vm.exceptions import OutOfGasError
from ethereum.utils.numeric import ceil32
from ethereum.cancun.vm.gas import GasConstants, charge_gas
from ethereum_types.numeric import Uint, U256, U256Struct
from ethereum.cancun.vm.memory import buffer_read
from ethereum.utils.bytes import Bytes_to_Bytes32, Bytes20_to_Bytes, Bytes, BytesStruct
from ethereum.utils.numeric import U256_from_be_bytes, U256__eq__, U256_le
from cairo_ec.curve.secp256k1 import secp256k1
from ethereum.crypto.elliptic_curve import secp256k1_recover, public_key_point_to_eth_address
from legacy.utils.bytes import felt_to_bytes20_little

func ecrecover{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    let data = evm.value.message.value.data;

    let err = charge_gas(Uint(GasConstants.GAS_ECRECOVER));
    if (cast(err, felt) != 0) {
        return err;
    }

    // Operation
    tempvar u256_0 = U256(new U256Struct(0, 0));
    tempvar u256_32 = U256(new U256Struct(32, 0));
    tempvar u256_64 = U256(new U256Struct(64, 0));
    tempvar u256_96 = U256(new U256Struct(96, 0));

    let message_hash_bytes = buffer_read(data, u256_0, u256_32);
    let v_bytes = buffer_read(data, u256_32, u256_32);
    let r_bytes = buffer_read(data, u256_64, u256_32);
    let s_bytes = buffer_read(data, u256_96, u256_32);

    let message_hash = Bytes_to_Bytes32(message_hash_bytes);
    let v = U256_from_be_bytes(v_bytes);
    let r = U256_from_be_bytes(r_bytes);
    let s = U256_from_be_bytes(s_bytes);

    let is_v_27 = U256__eq__(v, U256(new U256Struct(27, 0)));
    let is_v_28 = U256__eq__(v, U256(new U256Struct(28, 0)));

    let is_v_valid = is_v_27.value + is_v_28.value;

    if (is_v_valid == 0) {
        tempvar ok = cast(0, EthereumException*);
        return ok;
    }

    tempvar y_parity = U256(new U256Struct(v.value.low - 27, 0));

    tempvar SECP256K1N = U256(new U256Struct(low=secp256k1.N_LOW_128, high=secp256k1.N_HIGH_128));

    let is_r_invalid = U256_le(SECP256K1N, r);
    if (is_r_invalid.value != 0) {
        tempvar ok = cast(0, EthereumException*);
        return ok;
    }

    let is_s_invalid = U256_le(SECP256K1N, s);
    if (is_s_invalid.value != 0) {
        tempvar ok = cast(0, EthereumException*);
        return ok;
    }

    let (public_key_x, public_key_y, error) = secp256k1_recover(r, s, y_parity, message_hash);
    if (cast(error, felt) != 0) {
        tempvar ok = cast(0, EthereumException*);
        return ok;
    }

    let sender = public_key_point_to_eth_address(public_key_x, public_key_y);

    let (buffer: felt*) = alloc();
    memset(buffer, 0, 12);
    felt_to_bytes20_little(buffer + 12, sender.value);
    tempvar output = Bytes(new BytesStruct(data=buffer, len=32));
    EvmImpl.set_output(output);
    tempvar ok = cast(0, EthereumException*);
    return ok;
}
