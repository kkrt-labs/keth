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

from ethereum_types.bytes import Bytes, BytesStruct, Bytes1DictAccess
from ethereum_types.numeric import U256, Uint
from ethereum.utils.numeric import max
from src.utils.bytes import uint256_to_bytes32

struct MemoryStruct {
    dict_ptr_start: Bytes1DictAccess*,
    dict_ptr: Bytes1DictAccess*,
    len: felt,
}

struct Memory {
    value: MemoryStruct*,
}

// @notice Write bytes to memory at a given position.
// @dev assumption: memory is resized by the calling opcode
// @param memory The pointer to the bytearray.
// @param start_position Starting position to write at.
// @param value Bytes to write.
func memory_write{range_check_ptr, memory: Memory}(start_position: U256, value: Bytes) {
    alloc_locals;
    let bytes_len = value.value.len;
    let start_position_felt = start_position.value.low;

    // Early return if nothing to write
    if (value.value.len == 0) {
        return ();
    }

    with_attr error_message("memory_write: start_position > 2**128") {
        assert start_position.value.high = 0;
    }

    let bytes_data = value.value.data;
    let dict_ptr = cast(memory.value.dict_ptr, DictAccess*);
    with dict_ptr {
        _write_bytes(start_position_felt, bytes_data, bytes_len);
    }
    let new_dict_ptr = cast(dict_ptr, Bytes1DictAccess*);

    // we do not resize the memory here as it is done by the calling opcode
    tempvar memory = Memory(
        new MemoryStruct(memory.value.dict_ptr_start, new_dict_ptr, memory.value.len)
    );
    return ();
}

// @notice Read bytes from memory.
// @param memory The pointer to the bytearray.
// @param start_position Starting position to read from.
// @param size Number of bytes to read.
// @return The bytes read from memory.
func memory_read_bytes{memory: Memory}(start_position: U256, size: U256) -> Bytes {
    alloc_locals;

    with_attr error_message("memory_read_bytes: size > 2**128") {
        assert size.value.high = 0;
    }

    // Early return if nothing to read
    if (size.value.low == 0) {
        tempvar result = Bytes(new BytesStruct(cast(0, felt*), 0));
        return result;
    }

    with_attr error_message("memory_read_bytes: start_position > 2**128") {
        assert start_position.value.high = 0;
    }

    let (local output: felt*) = alloc();
    let dict_ptr = cast(memory.value.dict_ptr, DictAccess*);
    let start_position_felt = start_position.value.low;
    let size_felt = size.value.low;

    with dict_ptr {
        _read_bytes(start_position_felt, size_felt, output);
    }
    let new_dict_ptr = cast(dict_ptr, Bytes1DictAccess*);

    tempvar memory = Memory(
        new MemoryStruct(memory.value.dict_ptr_start, new_dict_ptr, memory.value.len)
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

    with_attr error_message("buffer_read: size > 2**128") {
        assert size.value.high = 0;
    }

    // Early return if nothing to read
    if (size_felt == 0) {
        tempvar result = Bytes(new BytesStruct(cast(0, felt*), 0));
        return result;
    }

    with_attr error_message("buffer_read: start_position > 2**128") {
        assert start_position.value.high = 0;
    }

    _buffer_read(buffer_len, buffer_data, start_position_felt, size_felt, output);
    tempvar result = Bytes(new BytesStruct(output, size_felt));
    return result;
}

// @notice Internal function to expand memory by a given amount.
// @param memory The pointer to the bytearray.
// @param expansion The amount to expand by.
func expand_by{memory: Memory}(expansion: Uint) {
    tempvar memory = Memory(
        new MemoryStruct(
            memory.value.dict_ptr_start, memory.value.dict_ptr, memory.value.len + expansion.value
        ),
    );
    return ();
}

// @notice Internal function to write bytes to memory.
// @param start_position Starting position to write at.
// @param data Pointer to the bytes data.
// @param len Length of bytes to write.
func _write_bytes{dict_ptr: DictAccess*}(start_position: felt, data: felt*, len: felt) {
    if (len == 0) {
        return ();
    }

    tempvar index = len;
    tempvar dict_ptr = dict_ptr;

    body:
    let index = [ap - 2] - 1;
    let dict_ptr = cast([ap - 1], DictAccess*);
    let start_position = [fp - 5];
    let data = cast([fp - 4], felt*);

    dict_write(start_position + index, data[index]);

    tempvar index = index;
    tempvar dict_ptr = dict_ptr;
    jmp body if index != 0;

    end:
    return ();
}

// @notice Internal function to read bytes from memory.
// @param start_position Starting position to read from.
// @param size Number of bytes to read.
// @param output Pointer to write output bytes to.
func _read_bytes{dict_ptr: DictAccess*}(start_position: felt, size: felt, output: felt*) {
    alloc_locals;
    if (size == 0) {
        return ();
    }

    tempvar dict_index = start_position + size;
    tempvar dict_ptr = dict_ptr;

    body:
    let dict_index = [ap - 2] - 1;
    let dict_ptr = cast([ap - 1], DictAccess*);
    let output = cast([fp - 3], felt*);
    let start_position = [fp - 5];
    tempvar output_index = dict_index - start_position;

    let (value) = dict_read(dict_index);
    assert output[output_index] = value;

    tempvar dict_index = dict_index;
    tempvar dict_ptr = dict_ptr;
    jmp body if output_index != 0;

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
