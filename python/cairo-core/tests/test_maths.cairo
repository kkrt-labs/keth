from cairo_core.maths import scalar_to_epns, sign

func test__sign{range_check_ptr}() -> felt {
    tempvar value;
    %{ ids.value = program_input["value"] %}
    return sign(value);
}

func test__scalar_to_epns{range_check_ptr}() -> (
    sum_p: felt, sum_n: felt, p_sign: felt, n_sign: felt
) {
    tempvar scalar;
    %{ ids.scalar = program_input["scalar"] %}
    return scalar_to_epns(scalar);
}
