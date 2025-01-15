from ethereum.cancun.vm.stack import pop, push
from ethereum.cancun.vm import Evm, EvmImpl, Environment, EnvImpl
from ethereum.cancun.vm.exceptions import ExceptionalHalt
from ethereum.cancun.vm.gas import charge_gas, GasConstants
from ethereum.cancun.state import get_storage
from ethereum.cancun.fork_types import (
    SetTupleAddressBytes32,
    SetTupleAddressBytes32DictAccess,
    SetTupleAddressBytes32Struct,
    TupleAddressBytes32,
    TupleAddressBytes32Struct,
    Address,
)
from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import Uint, U256, U256Struct
from ethereum.utils.numeric import U256_to_be_bytes
from src.utils.dict import hashdict_read, hashdict_write
from src.utils.utils import Helpers

from starkware.cairo.common.cairo_builtins import PoseidonBuiltin, BitwiseBuiltin
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.dict_access import DictAccess

// @notice Loads to the stack, the value corresponding to a certain key from the
// storage of the current account.
func sload{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, poseidon_ptr: PoseidonBuiltin*, evm: Evm}(
    ) -> ExceptionalHalt* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (key, err) = pop();
        if (cast(err, felt) != 0) {
            return err;
        }
    }
    // Gas
    // Get the entry from the accessed storage keys
    let key_bytes32 = U256_to_be_bytes(key);
    tempvar accessed_tuple = TupleAddressBytes32(
        new TupleAddressBytes32Struct(evm.value.message.value.current_target, key_bytes32)
    );
    let (serialized_keys: felt*) = alloc();
    assert serialized_keys[0] = accessed_tuple.value.address.value;
    assert serialized_keys[1] = accessed_tuple.value.bytes32.value.low;
    assert serialized_keys[2] = accessed_tuple.value.bytes32.value.high;
    let dict_ptr = cast(evm.value.accessed_storage_keys.value.dict_ptr, DictAccess*);
    with dict_ptr {
        let (is_present) = hashdict_read(3, serialized_keys);
        if (is_present == 0) {
            // If the entry is not in the accessed storage keys, add it
            hashdict_write(3, serialized_keys, 1);
            tempvar poseidon_ptr = poseidon_ptr;
            tempvar dict_ptr = dict_ptr;
        } else {
            tempvar poseidon_ptr = poseidon_ptr;
            tempvar dict_ptr = dict_ptr;
        }
        let poseidon_ptr = cast([ap - 2], PoseidonBuiltin*);
        let dict_ptr = cast([ap - 1], DictAccess*);

        let access_gas_cost = (is_present * GasConstants.GAS_WARM_ACCESS) + (1 - is_present) *
            GasConstants.GAS_COLD_SLOAD;
        let err = charge_gas(Uint(access_gas_cost));
        if (cast(err, felt) != 0) {
            return err;
        }
    }
    let new_dict_ptr = cast(dict_ptr, SetTupleAddressBytes32DictAccess*);
    tempvar new_accessed_storage_keys = SetTupleAddressBytes32(
        new SetTupleAddressBytes32Struct(
            evm.value.accessed_storage_keys.value.dict_ptr_start, new_dict_ptr
        ),
    );

    // OPERATION
    let state = evm.value.env.value.state;
    with state, stack {
        let value = get_storage(evm.value.message.value.current_target, Bytes32(key.value));
        let err = push(value);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // PROGRAM COUNTER
    let env = evm.value.env;
    EnvImpl.set_state{env=env}(state);
    EvmImpl.set_env(env);
    EvmImpl.set_pc_stack(Uint(evm.value.pc.value + 1), stack);
    EvmImpl.set_accessed_storage_keys(new_accessed_storage_keys);
    let ok = cast(0, ExceptionalHalt*);
    return ok;
}
