%builtins range_check

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import Uint256

from legacy.utils.utils import Helpers

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

func test__bytes_used_128{range_check_ptr}(output_ptr: felt*) {
    tempvar word;
    %{ ids.word = program_input["word"] %}

    // When
    let bytes_used = Helpers.bytes_used_128(word);

    // Then
    assert [output_ptr] = bytes_used;
    return ();
}
