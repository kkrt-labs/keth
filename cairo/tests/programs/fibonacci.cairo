%builtins output pedersen range_check bitwise poseidon range_check96 add_mod mul_mod

from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
    HashBuiltin,
)

func main{
    output_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}() {
    alloc_locals;

    tempvar a;
    tempvar b;
    tempvar n;
    %{ ids.a, ids.b, ids.n = program_input; %}
    let result: felt = fib(a, b, n);

    // Make sure the 10th Fibonacci number is 144.
    assert [output_ptr] = result;
    let output_ptr = output_ptr + 1;
    return ();
}

func fib(a, b, n) -> (res: felt) {
    jmp fib_body if n != 0;
    tempvar result = b;
    return (b,);

    fib_body:
    tempvar y = a + b;
    return fib(b, y, n - 1);
}
