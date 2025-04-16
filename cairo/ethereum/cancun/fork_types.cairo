from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import split_felt
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.bitwise import BitwiseBuiltin
from starkware.cairo.common.registers import get_label_location
from ethereum_types.bytes import (
    Bytes20,
    Bytes32,
    Bytes256,
    Bytes,
    BytesStruct,
    HashedBytes32,
    Bytes32Struct,
    OptionalBytes,
)
from ethereum.utils.bytes import Bytes__eq__
from ethereum_types.numeric import Uint, U256, U256Struct, bool
from ethereum.crypto.hash import Hash32, EMPTY_ROOT, EMPTY_HASH
from ethereum.utils.numeric import U256_to_be_bytes20
from cairo_core.comparison import is_zero

using Address = Bytes20;

struct OptionalAddress {
    // If `value` is the null ptr, the address is treated as None, else, treat `value` as a felt
    // that represents the underlying address
    value: felt*,
}

struct SetAddressDictAccess {
    key: Address,
    prev_value: bool,
    new_value: bool,
}

struct SetAddressStruct {
    dict_ptr_start: SetAddressDictAccess*,
    dict_ptr: SetAddressDictAccess*,
}

struct SetAddress {
    value: SetAddressStruct*,
}

struct ListHash32Struct {
    data: Hash32*,
    len: felt,
}

struct ListHash32 {
    value: ListHash32Struct*,
}

using Root = Hash32;

struct TupleAddressBytes32Struct {
    address: Address,
    bytes32: Bytes32,
}

struct TupleAddressBytes32 {
    value: TupleAddressBytes32Struct*,
}

struct HashedTupleAddressBytes32 {
    value: felt,
}

struct SetTupleAddressBytes32DictAccess {
    key: HashedTupleAddressBytes32,
    prev_value: bool,
    new_value: bool,
}

struct SetTupleAddressBytes32Struct {
    dict_ptr_start: SetTupleAddressBytes32DictAccess*,
    dict_ptr: SetTupleAddressBytes32DictAccess*,
}

struct SetTupleAddressBytes32 {
    value: SetTupleAddressBytes32Struct*,
}

using VersionedHash = Hash32;

struct TupleVersionedHashStruct {
    data: VersionedHash*,
    len: felt,
}

struct TupleVersionedHash {
    value: TupleVersionedHashStruct*,
}

struct TupleAddressUintTupleVersionedHashStruct {
    address: Address,
    uint: Uint,
    tuple_versioned_hash: TupleVersionedHash,
}

struct TupleAddressUintTupleVersionedHash {
    value: TupleAddressUintTupleVersionedHashStruct*,
}

using Bloom = Bytes256;

struct AccountStruct {
    nonce: Uint,
    balance: U256,
    code_hash: Bytes32,
    storage_root: Hash32,
    // An account with no code is an account whose code is not cached yet.
    // An account with empty code would have EMPTY_BYTES as code.
    code: OptionalBytes,
}

struct Account {
    value: AccountStruct*,
}

struct OptionalAccount {
    value: AccountStruct*,
}

struct AddressAccountDictAccess {
    key: Address,
    prev_value: Account,
    new_value: Account,
}

struct MappingAddressAccountStruct {
    dict_ptr_start: AddressAccountDictAccess*,
    dict_ptr: AddressAccountDictAccess*,
    // In case this is a copy of a previous dict,
    // this field points to the address of the original mapping.
    parent_dict: MappingAddressAccountStruct*,
}

struct MappingAddressAccount {
    value: MappingAddressAccountStruct*,
}

struct AddressBytes32DictAccess {
    key: Address,
    prev_value: Bytes32,
    new_value: Bytes32,
}

struct MappingAddressBytes32Struct {
    dict_ptr_start: AddressBytes32DictAccess*,
    dict_ptr: AddressBytes32DictAccess*,
    // Unused
    parent_dict: MappingAddressBytes32Struct*,
}

struct MappingAddressBytes32 {
    value: MappingAddressBytes32Struct*,
}

struct OptionalMappingAddressBytes32 {
    value: MappingAddressBytes32Struct*,
}

struct ListTupleAddressBytes32 {
    value: ListTupleAddressBytes32Struct*,
}

struct ListTupleAddressBytes32Struct {
    data: TupleAddressBytes32*,
    len: felt,
}

struct TupleAddressBytes32U256DictAccess {
    // key is hashed address
    key: HashedTupleAddressBytes32,
    prev_value: U256,
    new_value: U256,
}

struct MappingTupleAddressBytes32U256Struct {
    dict_ptr_start: TupleAddressBytes32U256DictAccess*,
    dict_ptr: TupleAddressBytes32U256DictAccess*,
    // In case this is a copy of a previous dict,
    // this field points to the address of the original mapping.
    parent_dict: MappingTupleAddressBytes32U256Struct*,
}

struct MappingTupleAddressBytes32U256 {
    value: MappingTupleAddressBytes32U256Struct*,
}

func EMPTY_ACCOUNT() -> Account {
    let (empty_root_ptr) = get_label_location(EMPTY_ROOT);
    let (empty_hash_ptr) = get_label_location(EMPTY_HASH);
    tempvar balance = U256(new U256Struct(0, 0));
    let (data) = alloc();
    tempvar empty_code = OptionalBytes(new BytesStruct(data=data, len=0));
    tempvar account = Account(
        value=new AccountStruct(
            nonce=Uint(0),
            balance=balance,
            code_hash=Hash32(cast(empty_hash_ptr, Bytes32Struct*)),
            storage_root=Hash32(cast(empty_root_ptr, Bytes32Struct*)),
            code=empty_code,
        ),
    );
    return account;
}

// @notice Compares two OptionalAccount instances.
func Account__eq__(a: OptionalAccount, b: OptionalAccount) -> bool {
    let other_fields_eq = account_eq_without_storage_root(a, b);
    if (other_fields_eq.value == 0) {
        return other_fields_eq;
    }
    if (cast(a.value, felt) == 0) {
        return other_fields_eq;
    }
    if (cast(b.value, felt) == 0) {
        return other_fields_eq;
    }
    if (a.value.storage_root.value.low != b.value.storage_root.value.low) {
        tempvar res = bool(0);
        return res;
    }
    if (a.value.storage_root.value.high != b.value.storage_root.value.high) {
        tempvar res = bool(0);
        return res;
    }

    let res = bool(1);
    return res;
}

// @notice Compares two OptionalAccount instances, ignoring their storage_root fields
// @dev When comparing account diffs, we ignore storage_root since storage changes are tracked separately via storage diffs.
//      This allows us to detect account changes independently from storage changes.
func account_eq_without_storage_root(a: OptionalAccount, b: OptionalAccount) -> bool {
    if (cast(a.value, felt) == 0) {
        let b_is_none = is_zero(cast(b.value, felt));
        let res = bool(b_is_none);
        return res;
    }
    if (cast(b.value, felt) == 0) {
        let a_is_none = is_zero(cast(a.value, felt));
        let res = bool(a_is_none);
        return res;
    }
    if (a.value.nonce.value != b.value.nonce.value) {
        tempvar res = bool(0);
        return res;
    }
    if (a.value.balance.value.low != b.value.balance.value.low) {
        tempvar res = bool(0);
        return res;
    }
    if (a.value.balance.value.high != b.value.balance.value.high) {
        tempvar res = bool(0);
        return res;
    }
    if (a.value.code_hash.value.low != b.value.code_hash.value.low) {
        tempvar res = bool(0);
        return res;
    }
    if (a.value.code_hash.value.high != b.value.code_hash.value.high) {
        tempvar res = bool(0);
        return res;
    }
    let res = bool(1);
    return res;
}

// @notice Converts a 20-byte big-endian value into an Address.
// @dev Panics if the value does not fit in 20 bytes.
func Address_from_felt_be{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(value: felt) -> Address {
    let (high, low) = split_felt(value);
    tempvar value_u256 = U256(new U256Struct(low, high));
    // The input being a 20-byte big-endian value, the output will be a 20-byte little-endian value.
    let address = U256_to_be_bytes20(value_u256);
    return address;
}
