%builtins range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import Uint256, assert_uint256_eq
from starkware.cairo.common.memset import memset
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.dict_access import DictAccess

from src.utils.dict import dict_squash
from src.utils.utils import Helpers
from src.constants import Constants
from tests.utils.dict import dict_keys

func test__bytes_to_uint256{range_check_ptr}() -> Uint256 {
    alloc_locals;

    tempvar word_len;
    let (word) = alloc();
    %{
        ids.word_len = len(program_input["word"])
        segments.write_arg(ids.word, program_input["word"])
    %}

    let res = Helpers.bytes_to_uint256(word_len, word);

    return res;
}

func test__bytes_to_bytes4_array{range_check_ptr}() {
    alloc_locals;
    // Given
    let (data) = alloc();
    let (expected) = alloc();
    %{
        segments.write_arg(ids.data, program_input["data"])
        segments.write_arg(ids.expected, program_input["expected"])
    %}

    // When
    let (tmp: felt*) = alloc();
    let (_, result: felt*) = Helpers.bytes_to_bytes4_array(12, data, 0, tmp);

    // Then
    assert expected[0] = result[0];
    assert expected[1] = result[1];
    assert expected[2] = result[2];

    return ();
}

func test__bytes4_array_to_bytes{range_check_ptr}() {
    alloc_locals;
    // Given
    let (data) = alloc();
    let (expected) = alloc();
    %{
        segments.write_arg(ids.data, program_input["data"])
        segments.write_arg(ids.expected, program_input["expected"])
    %}

    // When
    let (tmp) = alloc();
    let (_, result) = Helpers.bytes4_array_to_bytes(3, data, 0, tmp);

    // Then
    assert result[0] = expected[0];
    assert result[1] = expected[1];
    assert result[2] = expected[2];
    assert result[3] = expected[3];
    assert result[4] = expected[4];
    assert result[5] = expected[5];
    assert result[6] = expected[6];
    assert result[7] = expected[7];
    assert result[8] = expected[8];
    assert result[9] = expected[9];
    assert result[10] = expected[10];
    assert result[11] = expected[11];

    return ();
}

func test__bytes_used_128{range_check_ptr}(output_ptr: felt*) {
    tempvar word;
    %{ ids.word = program_input["word"] %}

    // When
    let bytes_used = Helpers.bytes_used_128(word);

    // Then
    assert [output_ptr] = bytes_used;
    return ();
}

func test__try_parse_destination_from_bytes{range_check_ptr}(output_ptr: felt*) {
    let (bytes) = alloc();
    tempvar bytes_len;
    %{
        segments.write_arg(ids.bytes, program_input["bytes"])
        ids.bytes_len = len(program_input["bytes"])
    %}

    // When
    let maybe_address = Helpers.try_parse_destination_from_bytes(bytes_len, bytes);

    // Then
    assert [output_ptr] = maybe_address.is_some;
    assert [output_ptr + 1] = maybe_address.value;

    return ();
}

func test__initialize_jumpdests{range_check_ptr}(output_ptr: felt*) {
    alloc_locals;

    tempvar bytecode_len;
    let (bytecode) = alloc();

    %{
        ids.bytecode_len = len(program_input["bytecode"])
        segments.write_arg(ids.bytecode, program_input["bytecode"])
    %}

    let (valid_jumpdests_start, valid_jumpdests) = Helpers.initialize_jumpdests(
        bytecode_len, bytecode
    );

    %{ segments.write_arg(ids.output_ptr, __dict_manager.get_dict(ids.valid_jumpdests)) %}

    return ();
}

func test__finalize_jumpdests{range_check_ptr}() {
    alloc_locals;

    local bytecode: felt*;
    local valid_jumpdests_start: DictAccess*;
    local valid_jumpdests: DictAccess*;
    %{
        from starkware.cairo.common.dict import DictTracker
        from tests.utils.helpers import flatten
        from ethereum.cancun.vm.runtime import get_valid_jump_destinations

        memory[fp] = segments.add()
        segments.write_arg(memory[fp], program_input["bytecode"])

        data = {k: 1 for k in get_valid_jump_destinations(program_input["bytecode"])}

        base = segments.add()
        segments.load_data(
            base,
            flatten([[int(k), 1, 1] for k in data.keys()])
        )
        __dict_manager.trackers[base.segment_index] = DictTracker(
            data=data,
            current_ptr=(base + len(data) * 3),
        )
        memory[fp + 1] = base
        memory[fp + 2] = base + len(data) * 3
    %}

    let (sorted_keys_start, sorted_keys_end) = dict_squash(valid_jumpdests_start, valid_jumpdests);

    Helpers.finalize_jumpdests(0, sorted_keys_start, sorted_keys_end, bytecode);

    return ();
}

func test__assert_valid_jumpdest{range_check_ptr}() {
    alloc_locals;
    tempvar bytecode: felt*;
    tempvar valid_jumpdest: DictAccess*;
    %{
        ids.bytecode = segments.add()
        segments.write_arg(ids.bytecode, program_input["bytecode"])
        ids.valid_jumpdest = segments.add()
        segments.write_arg(ids.valid_jumpdest.address_, program_input["valid_jumpdest"])
    %}
    Helpers.assert_valid_jumpdest(0, bytecode, valid_jumpdest);
    return ();
}

func test__split_word{range_check_ptr}() -> felt* {
    alloc_locals;
    local value: felt;
    local len: felt;
    %{
        ids.value = program_input["value"]
        ids.len = program_input["length"]
    %}
    let (dst) = alloc();
    Helpers.split_word(value, len, dst);
    return dst;
}

func test__split_word_little{range_check_ptr}() -> felt* {
    alloc_locals;
    local value: felt;
    local len: felt;
    %{
        ids.value = program_input["value"]
        ids.len = program_input["length"]
    %}
    let (dst) = alloc();
    Helpers.split_word_little(value, len, dst);
    return dst;
}
