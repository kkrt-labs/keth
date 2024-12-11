from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.memcpy import memcpy
from src.utils.bytes import felt_to_bytes_little, uint256_to_bytes32_little, felt_to_bytes20_little
from ethereum.crypto.hash import Hash32, keccak256
from ethereum_types.bytes import Bytes20, Bytes256, Bytes, BytesStruct
from ethereum_types.numeric import Uint, U256
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
