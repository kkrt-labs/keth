from cairo_core.maths import scalar_to_epns, sign, assert_uint256_le
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.alloc import alloc

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

func test__assert_uint256_le{range_check_ptr}() {
    alloc_locals;
    let (a_ptr) = alloc();
    let (b_ptr) = alloc();
    %{
        segments.write_arg(ids.a_ptr, program_input["a"])
        segments.write_arg(ids.b_ptr, program_input["b"])
    %}
    assert_uint256_le([cast(a_ptr, Uint256*)], [cast(b_ptr, Uint256*)]);

    return ();
}
