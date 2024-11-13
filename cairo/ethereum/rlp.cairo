from starkware.cairo.common.math_cmp import is_le, is_not_zero
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memcpy import memcpy
from ethereum.base_types import Bytes, BytesStruct, TupleBytes, TupleBytesStruct
from ethereum.utils.numeric import is_zero
from src.utils.bytes import felt_to_bytes

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
