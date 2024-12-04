from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.math_cmp import is_le, is_not_zero
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.memcpy import memcpy

from ethereum.base_types import (
    Bool,
    Bytes,
    BytesStruct,
    Bytes32,
    TupleBytes,
    TupleBytesStruct,
    Uint,
    U256,
    String,
    StringStruct,
    TupleBytes32,
)
from ethereum.cancun.blocks import Log
from ethereum.cancun.fork_types import Address, Account
from ethereum.cancun.transactions import LegacyTransaction, To
from ethereum.crypto.hash import keccak256, Hash32
from ethereum.utils.numeric import is_zero
from src.utils.array import reverse
from src.utils.bytes import (
    felt_to_bytes,
    felt_to_bytes_little,
    bytes_to_felt,
    uint256_to_bytes32_little,
    felt_to_bytes20_little,
    uint256_to_bytes_little,
    uint256_to_bytes,
)

struct SequenceSimple {
    value: SequenceSimpleStruct*,
}

struct SequenceSimpleStruct {
    value: Simple*,
    len: felt,
}

struct Simple {
    value: SimpleStruct*,
}

struct SimpleStruct {
    sequence: SequenceSimple,
    bytes: Bytes,
}

struct SequenceExtended {
    value: SequenceExtendedStruct*,
}

struct SequenceExtendedStruct {
    value: Extended*,
    len: felt,
}

struct Extended {
    value: ExtendedStruct*,
}

struct ExtendedStruct {
    sequence: SequenceExtended,
    bytearray: Bytes,
    bytes: Bytes,
    uint: Uint*,
    fixed_uint: Uint*,
    str: String,
    bool: Bool*,
}

namespace ExtendedImpl {
    func sequence(value: SequenceExtended) -> Extended {
        tempvar extended = Extended(
            new ExtendedStruct(
                sequence=value,
                bytearray=Bytes(cast(0, BytesStruct*)),
                bytes=Bytes(cast(0, BytesStruct*)),
                uint=cast(0, Uint*),
                fixed_uint=cast(0, Uint*),
                str=String(cast(0, StringStruct*)),
                bool=cast(0, Bool*),
            ),
        );
        return extended;
    }

    func bytearray(value: Bytes) -> Extended {
        tempvar extended = Extended(
            new ExtendedStruct(
                sequence=SequenceExtended(cast(0, SequenceExtendedStruct*)),
                bytearray=value,
                bytes=Bytes(cast(0, BytesStruct*)),
                uint=cast(0, Uint*),
                fixed_uint=cast(0, Uint*),
                str=String(cast(0, StringStruct*)),
                bool=cast(0, Bool*),
            ),
        );
        return extended;
    }

    func bytes(value: Bytes) -> Extended {
        tempvar extended = Extended(
            new ExtendedStruct(
                sequence=SequenceExtended(cast(0, SequenceExtendedStruct*)),
                bytearray=Bytes(cast(0, BytesStruct*)),
                bytes=value,
                uint=cast(0, Uint*),
                fixed_uint=cast(0, Uint*),
                str=String(cast(0, StringStruct*)),
                bool=cast(0, Bool*),
            ),
        );
        return extended;
    }

    func uint(value: Uint) -> Extended {
        tempvar extended = Extended(
            new ExtendedStruct(
                sequence=SequenceExtended(cast(0, SequenceExtendedStruct*)),
                bytearray=Bytes(cast(0, BytesStruct*)),
                bytes=Bytes(cast(0, BytesStruct*)),
                uint=value,
                fixed_uint=cast(0, Uint*),
                str=String(cast(0, StringStruct*)),
                bool=cast(0, Bool*),
            ),
        );
        return extended;
    }

    func fixed_uint(value: Uint) -> Extended {
        tempvar extended = Extended(
            new ExtendedStruct(
                sequence=SequenceExtended(cast(0, SequenceExtendedStruct*)),
                bytearray=Bytes(cast(0, BytesStruct*)),
                bytes=Bytes(cast(0, BytesStruct*)),
                uint=cast(0, Uint*),
                fixed_uint=value,
                str=String(cast(0, StringStruct*)),
                bool=cast(0, Bool*),
            ),
        );
        return extended;
    }

    func string(value: String) -> Extended {
        tempvar extended = Extended(
            new ExtendedStruct(
                sequence=SequenceExtended(cast(0, SequenceExtendedStruct*)),
                bytearray=Bytes(cast(0, BytesStruct*)),
                bytes=Bytes(cast(0, BytesStruct*)),
                uint=cast(0, Uint*),
                fixed_uint=cast(0, Uint*),
                str=value,
                bool=cast(0, Bool*),
            ),
        );
        return extended;
    }

    func bool(value: Bool*) -> Extended {
        tempvar extended = Extended(
            new ExtendedStruct(
                sequence=SequenceExtended(cast(0, SequenceExtendedStruct*)),
                bytearray=Bytes(cast(0, BytesStruct*)),
                bytes=Bytes(cast(0, BytesStruct*)),
                uint=cast(0, Uint*),
                fixed_uint=cast(0, Uint*),
                str=String(cast(0, StringStruct*)),
                bool=value,
            ),
        );
        return extended;
    }
}

//
// RLP Encode
//

func encode{range_check_ptr}(raw_data: Extended) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode(dst, raw_data);
    tempvar value = new BytesStruct(dst, len);
    let encoded_bytes = Bytes(value);
    return encoded_bytes;
}

func encode_uint{range_check_ptr}(raw_uint: Uint) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode_uint(dst, raw_uint.value);
    tempvar value = new BytesStruct(dst, len);
    let encoded_uint = Bytes(value);
    return encoded_uint;
}

func encode_uint256{range_check_ptr}(raw_uint: U256) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode_uint256(dst, raw_uint);
    tempvar value = new BytesStruct(dst, len);
    let encoded_uint = Bytes(value);
    return encoded_uint;
}

func encode_uint256_little{range_check_ptr}(raw_uint: U256) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode_uint256_little(dst, raw_uint);
    tempvar value = new BytesStruct(dst, len);
    let encoded_uint = Bytes(value);
    return encoded_uint;
}

func encode_bytes{range_check_ptr}(raw_bytes: Bytes) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode_bytes(dst, raw_bytes);
    tempvar value = new BytesStruct(dst, len);
    let encoded_bytes = Bytes(value);
    return encoded_bytes;
}

func encode_sequence{range_check_ptr}(raw_sequence: SequenceExtended) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode_sequence(dst, raw_sequence);
    tempvar value = new BytesStruct(dst, len);
    let encoded_bytes = Bytes(value);
    return encoded_bytes;
}

func get_joined_encodings{range_check_ptr}(raw_sequence: SequenceExtended) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _get_joined_encodings(dst, raw_sequence.value.value, raw_sequence.value.len);
    tempvar value = new BytesStruct(dst, len);
    let encoded_bytes = Bytes(value);
    return encoded_bytes;
}

func encode_bytes32{range_check_ptr}(raw_bytes32: Bytes32) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode_bytes32(dst, raw_bytes32);
    tempvar value = Bytes(new BytesStruct(dst, len));
    return value;
}

func encode_tuple_bytes32{range_check_ptr}(raw_tuple_bytes32: TupleBytes32) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode_tuple_bytes32(dst, raw_tuple_bytes32);
    tempvar value = Bytes(new BytesStruct(dst, len));
    return value;
}

func encode_to{range_check_ptr}(to: To) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode_to(dst, to);
    tempvar result = Bytes(new BytesStruct(dst, len));
    return result;
}

func encode_address{range_check_ptr}(address: Address) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode_address(dst, address);
    tempvar result = Bytes(new BytesStruct(dst, len));
    return result;
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

    // Encoding the code hash is encoding 32 bytes, so we know the prefix is 0x80 + 32
    // code_hash_len is 33 bytes and we can directly copy the bytes into the buffer
    let code_hash = keccak256(raw_account_data.value.code);
    let code_hash_ptr = dst + nonce_len + balance_len + storage_root_len;
    assert [code_hash_ptr] = 0x80 + 32;
    uint256_to_bytes32_little(code_hash_ptr + 1, [code_hash.value]);
    let code_hash_len = 33;

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

func encode_legacy_transaction{range_check_ptr}(transaction: LegacyTransaction) -> Bytes {
    alloc_locals;
    let (local dst_start) = alloc();
    // Leave space for the length encoding
    let dst = dst_start + 10;
    let nonce_len = _encode_uint256(dst, transaction.value.nonce);
    let dst = dst + nonce_len;
    let gas_price_len = _encode_uint(dst, transaction.value.gas_price.value);
    let dst = dst + gas_price_len;
    let gas_len = _encode_uint(dst, transaction.value.gas.value);
    let dst = dst + gas_len;
    let to_len = _encode_to(dst, transaction.value.to);
    let dst = dst + to_len;
    let value_len = _encode_uint256(dst, transaction.value.value);
    let dst = dst + value_len;
    let data_len = _encode_bytes(dst, transaction.value.data);
    let dst = dst + data_len;
    let v_len = _encode_uint256(dst, transaction.value.v);
    let dst = dst + v_len;
    let r_len = _encode_uint256(dst, transaction.value.r);
    let dst = dst + r_len;
    let s_len = _encode_uint256(dst, transaction.value.s);
    let dst = dst + s_len;

    let len = dst - dst_start - 10;
    let cond = is_le(len, 0x38 - 1);
    let dst = dst_start + 9;
    if (cond != 0) {
        assert [dst] = 0xC0 + len;
        tempvar result = Bytes(new BytesStruct(dst, 1 + len));
        return result;
    }

    let (len_joined_encodings_as_le: felt*) = alloc();
    let len_joined_encodings_as_le_len = felt_to_bytes_little(len_joined_encodings_as_le, len);

    // Write the length encoding
    // Length encoding is 1 byte for the prefix and then the length in little endian
    let dst = dst - len_joined_encodings_as_le_len;
    assert [dst] = 0xF7 + len_joined_encodings_as_le_len;
    // Copy the length encoding
    memcpy(dst + 1, len_joined_encodings_as_le, len_joined_encodings_as_le_len);

    tempvar result = Bytes(new BytesStruct(dst, 1 + len_joined_encodings_as_le_len + len));
    return result;
}

func encode_log{range_check_ptr}(raw_log: Log) -> Bytes {
    alloc_locals;

    let (local dst) = alloc();

    tempvar offset = 10;
    let dst = dst + offset;
    let len = _encode_address(dst, raw_log.value.address);
    let dst = dst + len;
    let len = _encode_tuple_bytes32(dst, raw_log.value.topics);
    let dst = dst + len;
    let len = _encode_bytes(dst, raw_log.value.data);
    let dst = dst + len;

    let dst_start = cast([fp], felt*);
    let len = dst - dst_start - offset;
    let dst = dst_start + offset - 1;

    let cond = is_le(len, 0x38 - 1);
    if (cond != 0) {
        assert [dst] = 0xC0 + len;
        tempvar result = Bytes(new BytesStruct(dst, 1 + len));
        return result;
    }

    let (len_joined_encodings_as_le: felt*) = alloc();
    let len_joined_encodings_as_le_len = felt_to_bytes(len_joined_encodings_as_le, len);

    let dst = dst - len_joined_encodings_as_le_len;
    assert [dst] = 0xF7 + len_joined_encodings_as_le_len;
    memcpy(dst + 1, len_joined_encodings_as_le, len_joined_encodings_as_le_len);
    let len = 1 + len_joined_encodings_as_le_len + len;
    tempvar result = Bytes(new BytesStruct(dst, len));
    return result;
}

//
// RLP Decode
//

func decode{range_check_ptr}(encoded_data: Bytes) -> Simple {
    alloc_locals;
    assert [range_check_ptr] = encoded_data.value.len;
    let range_check_ptr = range_check_ptr + 1;
    assert_not_zero(encoded_data.value.len);

    let cond = is_le(encoded_data.value.data[0], 0xbf);
    if (cond != 0) {
        let decoded_data = decode_to_bytes(encoded_data);
        tempvar value = Simple(
            new SimpleStruct(
                sequence=SequenceSimple(cast(0, SequenceSimpleStruct*)), bytes=decoded_data
            ),
        );
        return value;
    }

    let decoded_sequence = decode_to_sequence(encoded_data);
    tempvar value = Simple(
        new SimpleStruct(sequence=decoded_sequence, Bytes(cast(0, BytesStruct*)))
    );
    return value;
}

// @dev The reference function doesn't handle the case where encoded_bytes.len == 0
func decode_to_bytes{range_check_ptr}(encoded_bytes: Bytes) -> Bytes {
    alloc_locals;
    assert_not_zero(encoded_bytes.value.len);
    assert [range_check_ptr] = encoded_bytes.value.len;
    let range_check_ptr = range_check_ptr + 1;

    let cond = is_le(encoded_bytes.value.data[0], 0x80 - 1);
    if (encoded_bytes.value.len == 1 and cond != 0) {
        return encoded_bytes;
    }

    let cond = is_le(encoded_bytes.value.data[0], 0xB7);
    if (cond != 0) {
        let len_raw_data = encoded_bytes.value.data[0] - 0x80;
        assert [range_check_ptr] = len_raw_data;
        let range_check_ptr = range_check_ptr + 1;
        assert [range_check_ptr] = encoded_bytes.value.len - len_raw_data;
        let range_check_ptr = range_check_ptr + 1;
        let raw_data = encoded_bytes.value.data + 1;
        if (len_raw_data == 1) {
            assert [range_check_ptr] = raw_data[0] - 0x80;
            tempvar range_check_ptr = range_check_ptr + 1;
        } else {
            tempvar range_check_ptr = range_check_ptr;
        }
        let range_check_ptr = [ap - 1];
        tempvar value = new BytesStruct(raw_data, len_raw_data);
        let decoded_bytes = Bytes(value);
        return decoded_bytes;
    }

    let decoded_data_start_idx = 1 + encoded_bytes.value.data[0] - 0xB7;
    assert [range_check_ptr] = encoded_bytes.value.len - decoded_data_start_idx;
    let range_check_ptr = range_check_ptr + 1;
    assert_not_zero(encoded_bytes.value.data[1]);
    let len_decoded_data = bytes_to_felt(decoded_data_start_idx - 1, encoded_bytes.value.data + 1);
    assert [range_check_ptr] = len_decoded_data - 0x38;
    let range_check_ptr = range_check_ptr + 1;

    let decoded_data_end_idx = decoded_data_start_idx + len_decoded_data;
    assert [range_check_ptr] = encoded_bytes.value.len - decoded_data_end_idx;
    let range_check_ptr = range_check_ptr + 1;

    let raw_data = encoded_bytes.value.data + decoded_data_start_idx;
    tempvar value = new BytesStruct(raw_data, decoded_data_end_idx - decoded_data_start_idx);
    let decoded_bytes = Bytes(value);

    return decoded_bytes;
}

func decode_to_sequence{range_check_ptr}(encoded_sequence: Bytes) -> SequenceSimple {
    alloc_locals;

    let cond = is_le(encoded_sequence.value.data[0], 0xF7);
    if (cond == 1) {
        let len_joined_encodings = encoded_sequence.value.data[0] - 0xC0;
        assert [range_check_ptr] = len_joined_encodings;
        let range_check_ptr = range_check_ptr + 1;
        assert [range_check_ptr] = encoded_sequence.value.len - len_joined_encodings - 1;
        let range_check_ptr = range_check_ptr + 1;

        tempvar value = new BytesStruct(encoded_sequence.value.data + 1, len_joined_encodings);
        let joined_encodings = Bytes(value);
        return decode_joined_encodings(joined_encodings);
    }

    let joined_encodings_start_idx = 1 + encoded_sequence.value.data[0] - 0xF7;
    assert [range_check_ptr] = encoded_sequence.value.len - joined_encodings_start_idx;
    let range_check_ptr = range_check_ptr + 1;
    assert_not_zero(encoded_sequence.value.data[1]);

    let len_joined_encodings = bytes_to_felt(
        joined_encodings_start_idx - 1, encoded_sequence.value.data + 1
    );
    assert [range_check_ptr] = len_joined_encodings - 0x38;
    let range_check_ptr = range_check_ptr + 1;

    let joined_encodings_end_idx = joined_encodings_start_idx + len_joined_encodings;
    assert [range_check_ptr] = encoded_sequence.value.len - joined_encodings_end_idx;
    let range_check_ptr = range_check_ptr + 1;

    tempvar value = new BytesStruct(
        encoded_sequence.value.data + joined_encodings_start_idx,
        joined_encodings_end_idx - joined_encodings_start_idx,
    );
    let joined_encodings = Bytes(value);
    return decode_joined_encodings(joined_encodings);
}

func decode_joined_encodings{range_check_ptr}(joined_encodings: Bytes) -> SequenceSimple {
    alloc_locals;

    let (dst: Simple*) = alloc();
    let len = _decode_joined_encodings(dst, joined_encodings);
    tempvar decoded_sequence = SequenceSimple(new SequenceSimpleStruct(dst, len));
    return decoded_sequence;
}

func decode_item_length{range_check_ptr}(encoded_data: Bytes) -> felt {
    alloc_locals;
    assert [range_check_ptr] = encoded_data.value.len;
    let range_check_ptr = range_check_ptr + 1;

    let first_rlp_byte = encoded_data.value.data[0];

    let cond = is_le(first_rlp_byte, 0x80 - 1);
    if (cond != 0) {
        return 1;
    }

    let cond = is_le(first_rlp_byte, 0xB7);
    if (cond != 0) {
        let decoded_data_length = first_rlp_byte - 0x80;
        return 1 + decoded_data_length;
    }

    let cond = is_le(first_rlp_byte, 0xBF);
    if (cond != 0) {
        let length_length = first_rlp_byte - 0xB7;
        assert [range_check_ptr] = encoded_data.value.len - length_length - 1;
        let range_check_ptr = range_check_ptr + 1;
        assert_not_zero(encoded_data.value.data[1]);
        let decoded_data_length = bytes_to_felt(length_length, encoded_data.value.data + 1);
        return 1 + length_length + decoded_data_length;
    }

    let cond = is_le(first_rlp_byte, 0xF7);
    if (cond != 0) {
        let decoded_data_length = first_rlp_byte - 0xC0;
        return 1 + decoded_data_length;
    }

    let length_length = first_rlp_byte - 0xF7;
    assert [range_check_ptr] = encoded_data.value.len - length_length - 1;
    let range_check_ptr = range_check_ptr + 1;
    assert_not_zero(encoded_data.value.data[1]);
    let decoded_data_length = bytes_to_felt(length_length, encoded_data.value.data + 1);
    return 1 + length_length + decoded_data_length;
}

func rlp_hash{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}(
    data: Extended
) -> Hash32 {
    let encoded_bytes = encode(data);
    return keccak256(encoded_bytes);
}

//
// RLP Encode Helper Functions
//

func _encode{range_check_ptr}(dst: felt*, raw_data: Extended) -> felt {
    alloc_locals;

    if (cast(raw_data.value.sequence.value, felt) != 0) {
        return _encode_sequence(dst, raw_data.value.sequence);
    }

    if (cast(raw_data.value.bytearray.value, felt) != 0) {
        return _encode_bytes(dst, raw_data.value.bytearray);
    }

    if (cast(raw_data.value.bytes.value, felt) != 0) {
        return _encode_bytes(dst, raw_data.value.bytes);
    }

    if (cast(raw_data.value.uint, felt) != 0) {
        return _encode_uint(dst, raw_data.value.uint.value);
    }

    if (cast(raw_data.value.fixed_uint, felt) != 0) {
        return _encode_uint(dst, raw_data.value.fixed_uint.value);
    }

    if (cast(raw_data.value.str.value, felt) != 0) {
        return _encode_string(dst, raw_data.value.str);
    }

    if (cast(raw_data.value.bool, felt) != 0) {
        return _encode_uint(dst, raw_data.value.bool.value);
    }

    with_attr error_message("RLP Encoding type is not supported") {
        assert 0 = 1;
        return 0;
    }
}

func _encode_uint{range_check_ptr}(dst: felt*, raw_uint: felt) -> felt {
    alloc_locals;
    if (raw_uint == 0) {
        assert [dst] = 0x80;
        return 1;
    }
    let (raw_uint_as_bytes_be) = alloc();
    let raw_uint_as_bytes_be_len = felt_to_bytes(raw_uint_as_bytes_be, raw_uint);
    tempvar raw_uint_as_bytes = Bytes(
        new BytesStruct(raw_uint_as_bytes_be, raw_uint_as_bytes_be_len)
    );
    return _encode_bytes(dst, raw_uint_as_bytes);
}

func _encode_uint256{range_check_ptr}(dst: felt*, raw_uint: U256) -> felt {
    alloc_locals;
    if (raw_uint.value.high == 0 and raw_uint.value.low == 0) {
        assert [dst] = 0x80;
        return 1;
    }
    let (raw_uint_as_bytes_be) = alloc();
    let raw_uint_as_bytes_be_len = uint256_to_bytes(raw_uint_as_bytes_be, [raw_uint.value]);
    tempvar raw_uint_as_bytes = Bytes(
        new BytesStruct(raw_uint_as_bytes_be, raw_uint_as_bytes_be_len)
    );
    return _encode_bytes(dst, raw_uint_as_bytes);
}

func _encode_uint256_little{range_check_ptr}(dst: felt*, raw_uint: U256) -> felt {
    alloc_locals;
    if (raw_uint.value.high == 0 and raw_uint.value.low == 0) {
        assert [dst] = 0x80;
        return 1;
    }
    let (raw_uint_as_bytes_le) = alloc();
    let raw_uint_as_bytes_le_len = uint256_to_bytes_little(raw_uint_as_bytes_le, [raw_uint.value]);
    tempvar raw_uint_as_bytes = Bytes(
        new BytesStruct(raw_uint_as_bytes_le, raw_uint_as_bytes_le_len)
    );
    return _encode_bytes(dst, raw_uint_as_bytes);
}

func _encode_string{range_check_ptr}(dst: felt*, raw_string: String) -> felt {
    return _encode_bytes(dst, Bytes(cast(raw_string.value, BytesStruct*)));
}

func _encode_bytes{range_check_ptr}(dst: felt*, raw_bytes: Bytes) -> felt {
    alloc_locals;

    let len_raw_data = raw_bytes.value.len;

    if (len_raw_data == 0) {
        assert [dst] = 0x80;
        tempvar value = new BytesStruct(dst, 1);
        return 1;
    }

    let cond_1 = is_le(raw_bytes.value.data[0], 0x80 - 1);
    let cond_2 = is_zero(len_raw_data - 1);
    if (cond_1 * cond_2 != 0) {
        memcpy(dst, raw_bytes.value.data, raw_bytes.value.len);
        return raw_bytes.value.len;
    }

    let cond = is_le(len_raw_data, 0x38 - 1);
    if (cond != 0) {
        assert [dst] = 0x80 + len_raw_data;
        memcpy(dst + 1, raw_bytes.value.data, len_raw_data);
        tempvar value = new BytesStruct(dst, len_raw_data + 1);
        return len_raw_data + 1;
    }

    let len_raw_data_as_be = felt_to_bytes(dst + 1, len_raw_data);
    assert [dst] = 0xB7 + len_raw_data_as_be;

    memcpy(dst + 1 + len_raw_data_as_be, raw_bytes.value.data, raw_bytes.value.len);
    return 1 + len_raw_data_as_be + raw_bytes.value.len;
}

func _get_joined_encodings{range_check_ptr}(dst: felt*, raw_bytes: Extended*, len: felt) -> felt {
    alloc_locals;

    if (len == 0) {
        return 0;
    }

    let current_len = _encode(dst, raw_bytes[0]);
    let len = _get_joined_encodings(dst + current_len, raw_bytes + 1, len - 1);

    return current_len + len;
}

func _encode_sequence{range_check_ptr}(dst: felt*, raw_sequence: SequenceExtended) -> felt {
    alloc_locals;
    let (tmp_dst) = alloc();
    let len = _get_joined_encodings(tmp_dst, raw_sequence.value.value, raw_sequence.value.len);
    let cond = is_le(len, 0x38 - 1);
    if (cond != 0) {
        assert [dst] = 0xC0 + len;
        memcpy(dst + 1, tmp_dst, len);
        return len + 1;
    }

    let (len_joined_encodings_as_le: felt*) = alloc();
    let len_joined_encodings_as_le_len = felt_to_bytes(len_joined_encodings_as_le, len);

    assert [dst] = 0xF7 + len_joined_encodings_as_le_len;
    memcpy(dst + 1, len_joined_encodings_as_le, len_joined_encodings_as_le_len);
    memcpy(dst + 1 + len_joined_encodings_as_le_len, tmp_dst, len);

    return 1 + len_joined_encodings_as_le_len + len;
}

func _encode_address{range_check_ptr}(dst: felt*, address: Address) -> felt {
    assert [dst] = 0x80 + 20;
    felt_to_bytes20_little(dst + 1, address.value);
    return 21;
}

func _encode_to{range_check_ptr}(dst: felt*, to: To) -> felt {
    if (cast(to.value.address, felt) != 0) {
        return _encode_address(dst, [to.value.address]);
    }

    assert [dst] = 0x80;
    return 1;
}

func _encode_bytes32{range_check_ptr}(dst: felt*, raw_bytes32: Bytes32) -> felt {
    assert [dst] = 0x80 + 32;
    uint256_to_bytes32_little(dst + 1, [raw_bytes32.value]);
    return 33;
}

func _encode_tuple_bytes32{range_check_ptr}(dst: felt*, raw_tuple_bytes32: TupleBytes32) -> felt {
    alloc_locals;

    if (raw_tuple_bytes32.value.len == 0) {
        assert [dst] = 0xc0;
        return 1;
    }

    if (raw_tuple_bytes32.value.len == 1) {
        assert [dst] = 0xc0 + 33;
        assert [dst + 1] = 0x80 + 32;
        uint256_to_bytes32_little(dst + 2, [raw_tuple_bytes32.value.value[0].value]);
        return 34;
    }

    let joined_encodings_len = raw_tuple_bytes32.value.len * 33;
    let (len_joined_encodings_as_le: felt*) = alloc();
    let len_joined_encodings_as_le_len = felt_to_bytes(
        len_joined_encodings_as_le, joined_encodings_len
    );
    assert [dst] = 0xF7 + len_joined_encodings_as_le_len;
    memcpy(dst + 1, len_joined_encodings_as_le, len_joined_encodings_as_le_len);
    let dst = dst + 1 + len_joined_encodings_as_le_len;

    _encode_tuple_bytes32_inner(dst, raw_tuple_bytes32.value.len, raw_tuple_bytes32.value.value);

    return 1 + len_joined_encodings_as_le_len + joined_encodings_len;
}

func _encode_tuple_bytes32_inner{range_check_ptr}(
    dst: felt*, len: felt, raw_tuple_bytes32: Bytes32*
) {
    if (len == 0) {
        return ();
    }

    _encode_bytes32(dst, [raw_tuple_bytes32]);
    _encode_tuple_bytes32_inner(dst + 33, len - 1, raw_tuple_bytes32 + 1);

    return ();
}

//
// RLP Decode Helper Functions
//

func _decode_joined_encodings{range_check_ptr}(dst: Simple*, joined_encodings: Bytes) -> felt {
    alloc_locals;

    if (joined_encodings.value.len == 0) {
        return 0;
    }

    let encoded_item_length = decode_item_length(joined_encodings);
    assert [range_check_ptr] = joined_encodings.value.len - encoded_item_length;
    let range_check_ptr = range_check_ptr + 1;

    tempvar encoded_item = Bytes(new BytesStruct(joined_encodings.value.data, encoded_item_length));
    let decoded_item = decode(encoded_item);
    assert [dst] = decoded_item;

    tempvar joined_encodings = Bytes(
        new BytesStruct(
            joined_encodings.value.data + encoded_item_length,
            joined_encodings.value.len - encoded_item_length,
        ),
    );

    let len = _decode_joined_encodings(dst + 1, joined_encodings);
    return 1 + len;
}
