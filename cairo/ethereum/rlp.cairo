from ethereum.base_types import Bytes, BytesStruct, TupleBytes, TupleBytesStruct
from ethereum.crypto.hash import keccak256, Hash32
from ethereum.utils.numeric import is_zero
from src.utils.array import reverse
from src.utils.bytes import felt_to_bytes, felt_to_bytes_little, bytes_to_felt
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.math_cmp import is_le, is_not_zero
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.memcpy import memcpy

struct SequenceEnumSimple {
    value: SequenceEnumSimpleStruct*,
}

struct SequenceEnumSimpleStruct {
    value: EnumSimple*,
    len: felt,
}

struct EnumSimple {
    value: EnumSimpleStruct*,
}

struct EnumSimpleStruct {
    sequence: SequenceEnumSimple,
    bytes: Bytes,
}

//
// RLP Encode
//

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

func encode_bytes{range_check_ptr}(raw_bytes: Bytes) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode_bytes(dst, raw_bytes);
    tempvar value = new BytesStruct(dst, len);
    let encoded_bytes = Bytes(value);
    return encoded_bytes;
}

func _get_joined_encodings{range_check_ptr}(dst: felt*, raw_bytes: Bytes*, len: felt) -> felt {
    alloc_locals;

    if (len == 0) {
        return 0;
    }

    let current_len = _encode_bytes(dst, [raw_bytes]);
    let len = _get_joined_encodings(dst + current_len, raw_bytes + 1, len - 1);

    return current_len + len;
}

func get_joined_encodings{range_check_ptr}(raw_sequence: TupleBytes) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _get_joined_encodings(dst, raw_sequence.value.value, raw_sequence.value.len);
    tempvar value = new BytesStruct(dst, len);
    let encoded_bytes = Bytes(value);
    return encoded_bytes;
}

// @notice: Encodes a sequence of RLP encodable objects (`raw_sequence`) using RLP.
// @dev: The standard implementation assumes that the length fits in at most 9 bytes
//       since the leading byte is Bytes([0xF7 + len(len_joined_encodings_as_be)]).
//       In total, it means that the sequence starts at most at dst + 10.
//       To avoid a memcpy, we start using the allocated memory at dst + 10.
func encode_sequence{range_check_ptr}(raw_sequence: TupleBytes) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _get_joined_encodings(dst + 10, raw_sequence.value.value, raw_sequence.value.len);
    let cond = is_le(len, 0x38 - 1);
    if (cond != 0) {
        assert [dst + 9] = 0xC0 + len;
        tempvar value = new BytesStruct(dst + 9, len + 1);
        let encoded_bytes = Bytes(value);
        return encoded_bytes;
    }

    let (len_joined_encodings_as_le: felt*) = alloc();
    let len_joined_encodings_as_le_len = felt_to_bytes_little(len_joined_encodings_as_le, len);
    let dst = dst + 10 - len_joined_encodings_as_le_len - 1;
    reverse(dst + 1, len_joined_encodings_as_le_len, len_joined_encodings_as_le);
    assert [dst] = 0xF7 + len_joined_encodings_as_le_len;

    tempvar value = new BytesStruct(dst, len + 1 + len_joined_encodings_as_le_len);
    let encoded_bytes = Bytes(value);
    return encoded_bytes;
}

func rlp_hash{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}(
    raw_bytes: Bytes
) -> Hash32 {
    let encoded_bytes = encode_bytes(raw_bytes);
    return keccak256(encoded_bytes);
}

//
// RLP Decode
//

func decode{range_check_ptr}(encoded_data: Bytes) -> EnumSimple {
    alloc_locals;
    assert [range_check_ptr] = encoded_data.value.len;
    let range_check_ptr = range_check_ptr + 1;
    assert_not_zero(encoded_data.value.len);

    let cond = is_le(encoded_data.value.data[0], 0xbf);
    if (cond != 0) {
        let decoded_data = decode_to_bytes(encoded_data);
        tempvar value = EnumSimple(
            new EnumSimpleStruct(
                sequence=SequenceEnumSimple(cast(0, SequenceEnumSimpleStruct*)), bytes=decoded_data
            ),
        );
        return value;
    }

    let decoded_sequence = decode_to_sequence(encoded_data);
    tempvar value = EnumSimple(
        new EnumSimpleStruct(sequence=decoded_sequence, Bytes(cast(0, BytesStruct*)))
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

    let raw_data = encoded_bytes.value.data + decoded_data_start_idx;
    tempvar value = new BytesStruct(raw_data, decoded_data_end_idx - decoded_data_start_idx);
    let decoded_bytes = Bytes(value);

    return decoded_bytes;
}

func decode_to_sequence{range_check_ptr}(encoded_sequence: Bytes) -> SequenceEnumSimple {
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

func decode_joined_encodings{range_check_ptr}(joined_encodings: Bytes) -> SequenceEnumSimple {
    alloc_locals;

    let (dst: EnumSimple*) = alloc();
    let len = _decode_joined_encodings(dst, joined_encodings);
    tempvar decoded_sequence = SequenceEnumSimple(new SequenceEnumSimpleStruct(dst, len));
    return decoded_sequence;
}

func _decode_joined_encodings{range_check_ptr}(dst: EnumSimple*, joined_encodings: Bytes) -> felt {
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
