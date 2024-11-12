from starkware.cairo.common.math_cmp import is_le, is_not_zero
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memcpy import memcpy
from ethereum.base_types import Bytes, BytesStruct
from ethereum.utils.numeric import is_zero
from src.utils.bytes import felt_to_bytes

func encode_bytes{range_check_ptr}(raw_bytes: Bytes) -> Bytes {
    alloc_locals;

    let len_raw_data = raw_bytes.value.len;

    if (len_raw_data == 0) {
        let (data) = alloc();
        assert [data] = 0x80;
        tempvar value = new BytesStruct(data, 1);
        let encoded_bytes = Bytes(value);
        return encoded_bytes;
    }

    let cond_1 = is_le(raw_bytes.value.data[0], 0x80 - 1);
    let cond_2 = is_zero(len_raw_data - 1);
    if (cond_1 * cond_2 != 0) {
        return raw_bytes;
    }

    let cond = is_le(len_raw_data, 0x38 - 1);
    if (cond != 0) {
        let (data) = alloc();
        assert [data] = 0x80 + len_raw_data;
        memcpy(data + 1, raw_bytes.value.data, len_raw_data);
        tempvar value = new BytesStruct(data, len_raw_data + 1);
        let encoded_bytes = Bytes(value);

        return encoded_bytes;
    }

    // len_raw_data > 0x38
    let (data) = alloc();

    let len_raw_data_as_be = felt_to_bytes(data + 1, len_raw_data);
    assert [data] = 0xB7 + len_raw_data_as_be;

    memcpy(data + 1 + len_raw_data_as_be, raw_bytes.value.data, raw_bytes.value.len);
    tempvar value = new BytesStruct(data, 1 + len_raw_data_as_be + raw_bytes.value.len);
    let encoded_bytes = Bytes(value);

    return encoded_bytes;
}
