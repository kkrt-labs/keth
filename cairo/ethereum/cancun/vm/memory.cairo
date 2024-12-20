// SPDX-License-Identifier: MIT

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE, TRUE
from starkware.cairo.common.default_dict import default_dict_new, default_dict_finalize
from starkware.cairo.common.dict import DictAccess, dict_read, dict_write
from starkware.cairo.common.memset import memset
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.math import assert_le, assert_lt
from starkware.cairo.common.math_cmp import is_le, is_not_zero

from ethereum_types.bytes import Bytes, BytesStruct, Bytes1
from ethereum_types.numeric import U256

// @title Memory related functions.
// @notice Implements EVM memory operations using a mutable bytearray.
struct BytearrayStruct {
    dict_ptr_start: Bytes1DictAccess*,
    dict_ptr: Bytes1DictAccess*,
    len: felt,
}

struct Bytearray {
    value: BytearrayStruct*,
}

struct Bytes1DictAccess {
    key: felt,
    prev_value: Bytes1,
    new_value: Bytes1,
}

// @notice Write bytes to memory at a given position.
// @dev assumption: start_position < 2**128
// @dev assumption: value.len < 2**128
// @param memory The pointer to the bytearray.
// @param start_position Starting position to write at.
// @param value Bytes to write.
func memory_write{range_check_ptr, memory: Bytearray}(start_position: U256, value: Bytes) {
    alloc_locals;
    let bytes_len = value.value.len;
    let bytes_data = value.value.data;
    let start_position_felt = start_position.value.low;
    let new_len = start_position_felt + bytes_len;

    let dict_ptr = cast(memory.value.dict_ptr, DictAccess*);
    with dict_ptr {
        Internals._write_bytes(start_position_felt, bytes_data, bytes_len);
    }
    let new_dict_ptr = cast(dict_ptr, Bytes1DictAccess*);

    // Update length if we wrote beyond current length
    tempvar current_len = memory.value.len;
    let is_new_le_current = is_le(new_len, current_len);
    if (is_new_le_current != TRUE) {
        tempvar final_len = new_len;
    } else {
        tempvar final_len = current_len;
    }

    tempvar memory = Bytearray(
        new BytearrayStruct(memory.value.dict_ptr_start, new_dict_ptr, final_len)
    );
    return ();
}

// @notice Read bytes from memory.
// @dev assumption: start_position < 2**128
// @dev assumption: size < 2**128
// @param memory The pointer to the bytearray.
// @param start_position Starting position to read from.
// @param size Number of bytes to read.
// @return The bytes read from memory.
func memory_read_bytes{memory: Bytearray}(start_position: U256, size: U256) -> Bytes {
    alloc_locals;
    let (local output: felt*) = alloc();

    let start_position_felt = start_position.value.low;
    let size_felt = size.value.low;
    let dict_ptr = cast(memory.value.dict_ptr, DictAccess*);
    with dict_ptr {
        Internals._read_bytes(start_position_felt, size_felt, output);
    }
    let new_dict_ptr = cast(dict_ptr, Bytes1DictAccess*);

    tempvar memory = Bytearray(
        new BytearrayStruct(memory.value.dict_ptr_start, new_dict_ptr, memory.value.len)
    );
    tempvar result = Bytes(new BytesStruct(output, size_felt));
    return result;
}

// @notice Read bytes from a buffer with zero padding.
// @dev assumption: start_position < 2**128
// @dev assumption: size < 2**128
// @param buffer Source bytes to read from.
// @param start_position Starting position to read from.
// @param size Number of bytes to read.
// @return The bytes read from the buffer.
func buffer_read{range_check_ptr}(buffer: Bytes, start_position: U256, size: U256) -> Bytes {
    alloc_locals;
    let (local output: felt*) = alloc();
    let buffer_len = buffer.value.len;
    let buffer_data = buffer.value.data;
    let start_position_felt = start_position.value.low;
    let size_felt = size.value.low;

    Internals._buffer_read(buffer_len, buffer_data, start_position_felt, size_felt, output);
    tempvar result = Bytes(new BytesStruct(output, size_felt));
    return result;
}

namespace Internals {
    // @notice Internal function to write bytes to memory.
    // @param start_position Starting position to write at.
    // @param data Pointer to the bytes data.
    // @param len Length of bytes to write.
    func _write_bytes{dict_ptr: DictAccess*}(start_position: felt, data: felt*, len: felt) {
        if (len == 0) {
            return ();
        }

        tempvar start_position = start_position;
        tempvar data = data;
        tempvar len = len;
        tempvar dict_ptr = dict_ptr;

        body:
        let start_position = [ap - 4];
        let data = cast([ap - 3], felt*);
        let len = [ap - 2];
        let dict_ptr = cast([ap - 1], DictAccess*);
        dict_write(start_position, [data]);

        tempvar start_position = start_position + 1;
        tempvar data = data + 1;
        tempvar len = len - 1;
        tempvar dict_ptr = dict_ptr;
        jmp body if len != 0;
        return ();
    }

    // @notice Internal function to read bytes from memory.
    // @param start_position Starting position to read from.
    // @param size Number of bytes to read.
    // @param output Pointer to write output bytes to.
    func _read_bytes{dict_ptr: DictAccess*}(start_position: felt, size: felt, output: felt*) {
        if (size == 0) {
            return ();
        }

        tempvar start_position = start_position;
        tempvar size = size;
        tempvar output = output;
        tempvar dict_ptr = dict_ptr;

        body:
        let start_position = [ap - 4];
        let size = [ap - 3];
        let output = cast([ap - 2], felt*);
        let dict_ptr = cast([ap - 1], DictAccess*);

        let (value) = dict_read(start_position);
        assert [output] = value;

        tempvar start_position = start_position + 1;
        tempvar size = size - 1;
        tempvar output = output + 1;
        tempvar dict_ptr = dict_ptr;
        jmp body if size != 0;
        return ();
    }

    // @notice Internal function to read bytes from a buffer with zero padding.
    // @param data_len Length of the buffer.
    // @param data Pointer to the buffer data.
    // @param start_position Starting position to read from.
    // @param size Number of bytes to read.
    // @param output Pointer to write output bytes to.
    func _buffer_read{range_check_ptr}(
        data_len: felt, data: felt*, start_position: felt, size: felt, output: felt*
    ) {
        alloc_locals;
        if (size == 0) {
            return ();
        }

        // Check if start position is beyond buffer length
        let start_oob = is_le(data_len, start_position);
        if (start_oob == TRUE) {
            memset(output, 0, size);
            return ();
        }

        // Check if read extends past end of buffer
        let end_oob = is_le(data_len, start_position + size);
        if (end_oob == TRUE) {
            let available_size = data_len - start_position;
            memcpy(output, data + start_position, available_size);

            let remaining_size = size - available_size;
            memset(output + available_size, 0, remaining_size);
        } else {
            memcpy(output, data + start_position, size);
        }
        return ();
    }
}
