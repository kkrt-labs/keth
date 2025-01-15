from starkware.cairo.common.alloc import alloc

from ethereum_types.bytes import Bytes20, Bytes32, Bytes256, Bytes, BytesStruct, HashedBytes32
from ethereum.utils.bytes import Bytes__eq__
from ethereum_types.numeric import Uint, U256, U256Struct, bool
from ethereum.crypto.hash import Hash32
from ethereum.utils.numeric import is_zero

using Address = Bytes20;

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

struct SetTupleAddressBytes32DictAccess {
    key: TupleAddressBytes32,
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
    original_mapping: MappingAddressAccountStruct*,
}

struct MappingAddressAccount {
    value: MappingAddressAccountStruct*,
}

struct Bytes32U256DictAccess {
    // key is hashed.
    key: HashedBytes32,
    prev_value: U256,
    new_value: U256,
}

struct MappingBytes32U256Struct {
    dict_ptr_start: Bytes32U256DictAccess*,
    dict_ptr: Bytes32U256DictAccess*,
    // In case this is a copy of a previous dict,
    // this field points to the address of the original mapping.
    original_mapping: MappingBytes32U256Struct*,
}

struct MappingBytes32U256 {
    value: MappingBytes32U256Struct*,
}

func EMPTY_ACCOUNT() -> Account {
    tempvar balance = U256(new U256Struct(0, 0));
    let (data) = alloc();
    tempvar code = Bytes(new BytesStruct(data=data, len=0));
    tempvar account = Account(value=new AccountStruct(nonce=Uint(0), balance=balance, code=code));
    return account;
}

func Account__eq__(a: Account, b: Account) -> bool {
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
