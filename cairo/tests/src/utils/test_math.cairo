%builtins range_check

from src.utils.maths import unsigned_div_rem, ceil32

func test__unsigned_div_rem{range_check_ptr}() -> (felt, felt) {
    alloc_locals;

    tempvar value;
    tempvar div;
    %{
        ids.value = program_input["value"]
        ids.div = program_input["div"]
    %}
    return unsigned_div_rem(value, div);
}

func test__ceil32{range_check_ptr}() -> felt {
    alloc_locals;
    tempvar value;
    %{ ids.value = program_input["value"] %}
    return ceil32(value);
}
