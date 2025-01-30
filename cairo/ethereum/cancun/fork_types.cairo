from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import split_felt
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.bitwise import BitwiseBuiltin
from ethereum_types.bytes import Bytes20, Bytes32, Bytes256, Bytes, BytesStruct, HashedBytes32
from ethereum.utils.bytes import Bytes__eq__
from ethereum_types.numeric import Uint, U256, U256Struct, bool
from ethereum.crypto.hash import Hash32
from ethereum.utils.numeric import is_zero, U256_to_be_bytes20

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

using Bloom = Bytes256;

struct AccountStruct {
    nonce: Uint,
    balance: U256,
    code: Bytes,
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
    tempvar balance = U256(new U256Struct(0, 0));
    let (data) = alloc();
    tempvar code = Bytes(new BytesStruct(data=data, len=0));
    tempvar account = Account(value=new AccountStruct(nonce=Uint(0), balance=balance, code=code));
    return account;
}

func Account__eq__(a: OptionalAccount, b: OptionalAccount) -> bool {
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
    if (a.value.code.value.len != b.value.code.value.len) {
        tempvar res = bool(0);
        return res;
    }

    let code_eq = Bytes__eq__(a.value.code, b.value.code);

    return code_eq;
}

func Address_from_felt_be{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(value: felt) -> Address {
    let (high, low) = split_felt(value);
    tempvar value_u256 = U256(new U256Struct(low, high));
    let address = U256_to_be_bytes20(value_u256);
    return address;
}
