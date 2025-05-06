from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
    HashBuiltin,
)

from ethereum.cancun.keth.body import body

func test_body{
    output_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}() -> (output_start: felt*) {
    alloc_locals;
    local output_start: felt* = output_ptr;
    body();
    return (output_start=output_start);
}
