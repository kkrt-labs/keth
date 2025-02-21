from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import uint256_to_felt
from starkware.cairo.common.math_cmp import is_le, is_le_felt
from cairo_core.comparison import is_zero
from ethereum_types.bytes import Bytes, BytesStruct
from ethereum_types.numeric import U256, U256Struct, Uint
from ethereum.utils.numeric import (
    max,
    min,
    U256_from_be_bytes,
    Uint_from_be_bytes,
    U256__eq__,
    U256_add,
    U256_min,
    U256_mul,
    U256_sub,
    divmod,
)
from ethereum.cancun.vm.evm_impl import Evm
from ethereum.cancun.vm.evm_impl import EvmImpl
from ethereum.cancun.vm.gas import charge_gas
from ethereum.cancun.vm.memory import buffer_read
from ethereum.exceptions import EthereumException
from ethereum.cancun.vm.exceptions import OutOfGasError
from legacy.utils.uint256 import uint256_unsigned_div_rem

func modexp{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*, evm: Evm}(
    ) -> EthereumException* {
    alloc_locals;
    let data = evm.value.message.value.data;
    tempvar u256_zero = U256(new U256Struct(0, 0));
    tempvar u256_thirty_two = U256(new U256Struct(32, 0));
    tempvar u256_sixty_four = U256(new U256Struct(64, 0));
    tempvar u256_ninety_six = U256(new U256Struct(96, 0));

    let res = buffer_read(data, u256_zero, u256_thirty_two);
    let base_length = U256_from_be_bytes(res);

    let res = buffer_read(data, u256_thirty_two, u256_thirty_two);
    let exp_length = U256_from_be_bytes(res);

    let res = buffer_read(data, u256_sixty_four, u256_thirty_two);
    let modulus_length = U256_from_be_bytes(res);

    let exp_start = U256_add(u256_ninety_six, base_length);

    let min_len = U256_min(u256_thirty_two, exp_length);
    let res = buffer_read(data, exp_start, min_len);
    let exp_head = U256_from_be_bytes(res);

    tempvar gas;
    %{ modexp_gas %}

    let err = charge_gas(Uint(gas));
    if (cast(err, felt) != 0) {
        return err;
    }

    let base_zero = U256__eq__(base_length, u256_zero);
    let modulus_zero = U256__eq__(modulus_length, u256_zero);
    if (base_zero.value == 1 and modulus_zero.value == 1) {
        tempvar empty_bytes = Bytes(new BytesStruct(cast(0, felt*), 0));
        EvmImpl.set_output(empty_bytes);
        tempvar ok = cast(0, EthereumException*);
        return ok;
    }

    let base_read = buffer_read(data, u256_ninety_six, base_length);
    local base: Bytes;
    assert base = base_read;

    let exp_read = buffer_read(data, exp_start, exp_length);
    local exp: Bytes;
    assert exp = exp_read;

    let modulus_start = U256_add(exp_start, exp_length);
    let modulus_read = buffer_read(data, modulus_start, modulus_length);
    local modulus: Bytes;
    assert modulus = modulus_read;

    tempvar result: Bytes;

    %{ modexp_output %}

    EvmImpl.set_output(result);
    tempvar ok = cast(0, EthereumException*);
    return ok;
}
