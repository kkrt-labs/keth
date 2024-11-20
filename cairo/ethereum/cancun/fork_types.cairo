from ethereum.crypto.hash import Hash32
from ethereum.base_types import Bytes20, Bytes256, Uint, U256, Bytes, bytes

using Address = Bytes20;
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
