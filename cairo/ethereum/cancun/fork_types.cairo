from starkware.cairo.common.alloc import alloc

from ethereum_types.bytes import Bytes20, Bytes32, Bytes256, Bytes, BytesStruct
from ethereum_types.numeric import Uint, U256, U256Struct, bool
from ethereum.crypto.hash import Hash32

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
}

struct MappingAddressAccount {
    value: MappingAddressAccountStruct*,
}

func EMPTY_ACCOUNT() -> Account {
    tempvar balance = U256(new U256Struct(0, 0));
    let (data) = alloc();
    tempvar code = Bytes(new BytesStruct(data=data, len=0));
    tempvar account = Account(value=new AccountStruct(nonce=Uint(0), balance=balance, code=code));
    return account;
}
