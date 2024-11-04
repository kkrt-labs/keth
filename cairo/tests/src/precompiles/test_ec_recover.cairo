from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.math import unsigned_div_rem, assert_not_zero
from starkware.cairo.common.memset import memset
from starkware.cairo.common.memcpy import memcpy

from src.precompiles.ec_recover import PrecompileEcRecover
from src.utils.utils import Helpers

func test__ec_recover{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}() -> (output: felt*) {
    alloc_locals;
    let (local input) = alloc();
    tempvar input_len: felt;
    %{
        ids.input_len = len(program_input["input"]);
        segments.write_arg(ids.input, program_input["input"])
    %}
    let (output_len: felt, output: felt*, gas_used: felt, reverted: felt) = PrecompileEcRecover.run(
        PrecompileEcRecover.PRECOMPILE_ADDRESS, input_len, input
    );
    return (output=output);
}
