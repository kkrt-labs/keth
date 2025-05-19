// cairo-lint: disable-file

from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
    HashBuiltin,
    SignatureBuiltin,
    EcOpBuiltin,
)

from ethereum.prague.keth.body import body
from ethereum.prague.keth.init import init
from ethereum.prague.keth.teardown import teardown
from ethereum.prague.keth.aggregator import aggregator
from ethereum.prague.keth.main import main

func test_body{
    output_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    ec_op_ptr: EcOpBuiltin*,
    keccak_ptr: felt*,
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


func test_init{
    output_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    ec_op_ptr: EcOpBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}() -> (output_start: felt*) {
    alloc_locals;
    local output_start: felt* = output_ptr;
    init();
    return (output_start=output_start);
}


func test_teardown{
    output_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    ec_op_ptr: EcOpBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}() -> (output_start: felt*) {
    alloc_locals;
    local output_start: felt* = output_ptr;
    teardown();
    return (output_start=output_start);
}


func test_main{
    output_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    ec_op_ptr: EcOpBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}() -> (output_start: felt*) {
    alloc_locals;
    local output_start: felt* = output_ptr;
    main();
    return (output_start=output_start);
}

func test_aggregator{
    output_ptr: felt*,
    range_check_ptr,
}() -> (output_start: felt*) {
    alloc_locals;
    local output_start: felt* = output_ptr;
    aggregator();
    return (output_start=output_start);
}
