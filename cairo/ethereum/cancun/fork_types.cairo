from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.memcpy import memcpy
from src.utils.bytes import felt_to_bytes_little, uint256_to_bytes32_little
from ethereum.crypto.hash import Hash32, keccak256
from ethereum.base_types import Bytes20, Bytes256, Uint, U256, Bytes, BytesStruct
from ethereum.rlp import (
    encode_sequence,
    SequenceExtended,
    _encode_uint,
    _encode_bytes,
    _encode_uint256,
    _encode_uint256_little,
)

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
    code: Bytes,
}

struct Account {
    value: AccountStruct*,
}

func encode_account{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}(
    raw_account_data: Account, storage_root: Bytes
) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    // Leave space for the length encoding
    let dst = dst + 10;
    let nonce_len = _encode_uint(dst, raw_account_data.value.nonce.value);
    let balance_len = _encode_uint256(dst + nonce_len, raw_account_data.value.balance);
    let storage_root_len = _encode_bytes(dst + nonce_len + balance_len, storage_root);
    let code_hash = keccak256(raw_account_data.value.code);
    let (code_hash_le: felt*) = alloc();
    uint256_to_bytes32_little(code_hash_le, [code_hash.value]);
    let code_hash_len = _encode_bytes(
        dst + nonce_len + balance_len + storage_root_len, Bytes(new BytesStruct(code_hash_le, 32))
    );
    let len = nonce_len + balance_len + storage_root_len + code_hash_len;
    let cond = is_le(len, 0x38 - 1);
    if (cond != 0) {
        let dst = dst - 1;
        assert [dst] = 0xC0 + len;
        tempvar result = Bytes(new BytesStruct(dst, 1 + len));
        return result;
    }

    let (len_joined_encodings_as_le: felt*) = alloc();
    let len_joined_encodings_as_le_len = felt_to_bytes_little(len_joined_encodings_as_le, len);

    // Write the length encoding
    // Length encoding is 1 byte for the prefix and then the length in little endian
    let dst = dst - 1 - len_joined_encodings_as_le_len;
    assert [dst] = 0xF7 + len_joined_encodings_as_le_len;
    // Copy the length encoding
    memcpy(dst + 1, len_joined_encodings_as_le, len_joined_encodings_as_le_len);

    tempvar result = Bytes(new BytesStruct(dst, 1 + len_joined_encodings_as_le_len + len));
    return result;
}
