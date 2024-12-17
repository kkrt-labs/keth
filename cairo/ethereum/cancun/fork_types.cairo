from starkware.cairo.common.alloc import alloc

from ethereum_types.bytes import Bytes20, Bytes256, Bytes, BytesStruct
from ethereum_types.numeric import Uint, U256, U256Struct
from ethereum.crypto.hash import Hash32

using Address = Bytes20;
using Root = Hash32;

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
