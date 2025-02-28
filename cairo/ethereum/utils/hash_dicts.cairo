from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.registers import get_fp_and_pc

from legacy.utils.dict import hashdict_read
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
