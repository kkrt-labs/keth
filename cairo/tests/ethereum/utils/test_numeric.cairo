from ethereum.utils.numeric import min, divmod

func test_min{range_check_ptr}() -> felt {
    tempvar a;
    tempvar b;
    %{
        ids.a = program_input["a"]
        ids.b = program_input["b"]
    %}

    return min(a, b);
}

func test_divmod{range_check_ptr}() -> (q: felt, r: felt) {
    tempvar value;
    tempvar div;
    %{
        ids.value = program_input["value"]
        ids.div = program_input["div"]
    %}
    return divmod(value, div);
}
