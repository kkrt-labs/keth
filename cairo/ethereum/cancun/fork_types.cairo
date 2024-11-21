from ethereum.crypto.hash import Hash32
from ethereum.base_types import Bytes20, Bytes256, Uint, U256, Bytes, bytes, bool

using Address = Bytes20;
struct OptionalAddressStruct {
    is_some: bool,
    value: Address*,
}

struct OptionalAddress {
    value: OptionalAddressStruct*,
}

struct TupleAddressStruct {
    value: Address*,
    len: felt,
}

struct TupleAddress {
    value: TupleAddressStruct*,
}

using Root = Hash32;

using VersionedHash = Hash32;
struct TupleVersionedHashStruct {
    value: VersionedHash*,
    len: felt,
}

struct TupleVersionedHash {
    value: TupleVersionedHashStruct*,
}

using Bloom = Bytes256;

struct AccountStruct {
    nonce: Uint,
    balance: U256,
    code: bytes,
}

struct Account {
    value: AccountStruct*,
}
