%builtins range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memcpy import memcpy

from src.utils.rlp import RLP

func test__decode_raw{range_check_ptr}() -> RLP.Item* {
    alloc_locals;
    // Given
    tempvar data_len: felt;
    let (data) = alloc();
    %{
        ids.data_len = program_input.get("data_len", len(program_input["data"]))
        segments.write_arg(ids.data, program_input["data"])
    %}

    // When
    let (local items: RLP.Item*) = alloc();
    RLP.decode_raw(items, data_len, data);

    return items;
}

func test__decode{range_check_ptr}() -> RLP.Item* {
    alloc_locals;
    // Given
    tempvar data_len: felt;
    let (data) = alloc();
    %{
        ids.data_len = len(program_input["data"])
        segments.write_arg(ids.data, program_input["data"])
    %}

    // When
    let (local items: RLP.Item*) = alloc();
    RLP.decode(items, data_len, data);

    return items;
}

func test__decode_type{range_check_ptr}() -> (felt, felt, felt) {
    alloc_locals;
    // Given
    let (data) = alloc();
    %{ segments.write_arg(ids.data, program_input["data"]) %}

    // When
    let (type, offset, len) = RLP.decode_type_unsafe(data);

    // Then
    return (type, offset, len);
}
