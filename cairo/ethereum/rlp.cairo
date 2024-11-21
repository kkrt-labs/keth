from ethereum.base_types import Bytes, BytesStruct, TupleBytes, TupleBytesStruct, Uint, U256, bool
from ethereum.crypto.hash import keccak256, Hash32
from ethereum.utils.numeric import is_zero
from src.utils.array import reverse
from src.utils.bytes import felt_to_bytes, felt_to_bytes_little, bytes_to_felt
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.math_cmp import is_le, is_not_zero
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.memcpy import memcpy

from src.utils.bytes import uint256_to_bytes_little, uint256_to_bytes

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
    bytesarray: Bytes,
    bytes: Bytes,
    uint: Uint*,
    fixed_uint: Uint*,
    str: Bytes,
    bool: bool*,
    RLP: Bytes,
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

    if (cast(raw_data.value.bytesarray.value, felt) != 0) {
        return _encode_bytes(dst, raw_data.value.bytesarray);
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
        return _encode_bytes(dst, raw_data.value.str);
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
    let len_joined_encodings_as_le_len = felt_to_bytes_little(len_joined_encodings_as_le, len);

    assert [dst] = 0xF7 + len_joined_encodings_as_le_len;
    memcpy(dst + 1, len_joined_encodings_as_le, len_joined_encodings_as_le_len);
    memcpy(dst + 1 + len_joined_encodings_as_le_len, tmp_dst, len);

    return 1 + len_joined_encodings_as_le_len + len;
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
