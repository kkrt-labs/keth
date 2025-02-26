from ethereum_types.bytes import Bytes, Bytes32, Bytes32Struct
from ethereum.cancun.fork_types import Address
from ethereum.cancun.fork_types import (
    MappingAddressBytes32,
    MappingAddressBytes32Struct,
    AddressBytes32DictAccess,
)
from starkware.cairo.common.dict import DictAccess
from ethereum_types.numeric import SetUint, SetUintStruct, SetUintDictAccess

from legacy.utils.dict import dict_read, dict_write
from ethereum.utils.bytes import Bytes32_to_Bytes

func mapping_address_bytes32_read{range_check_ptr, mapping: MappingAddressBytes32}(
    key: Address
) -> Bytes32 {
    alloc_locals;
    let dict_ptr = cast(mapping.value.dict_ptr, DictAccess*);
    let (value_ptr) = dict_read{dict_ptr=dict_ptr}(key.value);
    let value = Bytes32(cast(value_ptr, Bytes32Struct*));
    tempvar mapping = MappingAddressBytes32(
        new MappingAddressBytes32Struct(
            mapping.value.dict_ptr_start,
            cast(dict_ptr, AddressBytes32DictAccess*),
            mapping.value.parent_dict,
        ),
    );
    return value;
}

func mapping_address_bytes32_write{range_check_ptr, mapping: MappingAddressBytes32}(
    key: Address, value: Bytes32
) {
    alloc_locals;
    let dict_ptr = cast(mapping.value.dict_ptr, DictAccess*);
    let value_felt = cast(value.value, felt);
    dict_write{dict_ptr=dict_ptr}(key.value, value_felt);
    tempvar mapping = MappingAddressBytes32(
        new MappingAddressBytes32Struct(
            dict_ptr_start=mapping.value.dict_ptr_start,
            dict_ptr=cast(dict_ptr, AddressBytes32DictAccess*),
            parent_dict=mapping.value.parent_dict,
        ),
    );
    return ();
}

func set_uint_read{range_check_ptr, set: SetUint}(key: felt) -> felt {
    alloc_locals;
    let dict_ptr = cast(set.value.dict_ptr, DictAccess*);
    let (value) = dict_read{dict_ptr=dict_ptr}(key);
    tempvar set = SetUint(
        new SetUintStruct(
            dict_ptr_start=set.value.dict_ptr_start, dict_ptr=cast(dict_ptr, SetUintDictAccess*)
        ),
    );
    return value;
}
