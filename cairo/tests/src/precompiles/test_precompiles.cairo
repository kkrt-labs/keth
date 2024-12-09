from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.alloc import alloc

from src.precompiles.precompiles import Precompiles

func test__is_precompile{range_check_ptr}() -> felt {
    alloc_locals;
    // Given
    local address;
    %{ ids.address = program_input["address"] %}

    // When
    let is_precompile = Precompiles.is_precompile(address);
    return is_precompile;
}

func test__precompiles_run{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}() -> (output: felt*, reverted: felt, gas_used: felt) {
    alloc_locals;
    // Given
    local address;
    local input_len;
    let (local input) = alloc();
    %{
        ids.address = program_input["address"]
        ids.input_len = len(program_input["input"])
        segments.write_arg(ids.input, program_input["input"])
    %}

    // When
    let result = Precompiles.exec_precompile(
        precompile_address=address, input_len=input_len, input=input
    );
    let output_len = result.output_len;
    let (output) = alloc();
    memcpy(dst=output, src=result.output, len=output_len);

    return (output, result.reverted, result.gas_used);
}
