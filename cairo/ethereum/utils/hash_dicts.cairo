from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.registers import get_fp_and_pc

from legacy.utils.dict import hashdict_read, hashdict_write
from ethereum.cancun.fork_types import SetAddress, SetAddressStruct, SetAddressDictAccess, Address

func set_address_contains{range_check_ptr, poseidon_ptr: PoseidonBuiltin*, set: SetAddress}(
    address: Address
) -> felt {
    alloc_locals;

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let dict_ptr = cast(set.value.dict_ptr, DictAccess*);
    let (value) = hashdict_read{dict_ptr=dict_ptr}(1, &address.value);

    tempvar set = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=set.value.dict_ptr_start, dict_ptr=cast(dict_ptr, SetAddressDictAccess*)
        ),
    );

    return value;
}

func set_address_add{poseidon_ptr: PoseidonBuiltin*, set_address: SetAddress}(address: Address) {
    alloc_locals;

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let dict_ptr = cast(set_address.value.dict_ptr, DictAccess*);
    hashdict_write{dict_ptr=dict_ptr}(1, &address.value, 1);
    tempvar set_address = SetAddress(
        new SetAddressStruct(
            set_address.value.dict_ptr_start, cast(dict_ptr, SetAddressDictAccess*)
        ),
    );

    return ();
}

// Returns a boolean indicating if the value was present in the set before the update.
func set_address_contains_or_add{poseidon_ptr: PoseidonBuiltin*, set_address: SetAddress}(
    address: Address
) -> felt {
    alloc_locals;

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let dict_ptr = cast(set_address.value.dict_ptr, DictAccess*);
    let (is_present) = hashdict_read{dict_ptr=dict_ptr}(1, &address.value);

    if (is_present == 0) {
        hashdict_write{dict_ptr=dict_ptr}(1, &address.value, 1);
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar dict_ptr = dict_ptr;
    } else {
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar dict_ptr = dict_ptr;
    }

    let poseidon_ptr = cast([ap - 2], PoseidonBuiltin*);
    let set_address_dict_ptr = cast([ap - 1], SetAddressDictAccess*);
    tempvar set_address = SetAddress(
        new SetAddressStruct(set_address.value.dict_ptr_start, set_address_dict_ptr)
    );

    return is_present;
}
