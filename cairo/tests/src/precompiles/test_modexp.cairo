from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.math import split_felt

from src.utils.utils import Helpers
from src.precompiles.modexp import PrecompileModExpUint256

func test__modexp_impl{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}(output_ptr: felt*) {
    alloc_locals;
    local data_len: felt;
    let (data: felt*) = alloc();
    %{
        ids.data_len = len(program_input["data"]);
        segments.write_arg(ids.data, program_input["data"]);
    %}

    let (output_len, output, gas_used, reverted) = PrecompileModExpUint256.run(
        PrecompileModExpUint256.PRECOMPILE_ADDRESS, data_len, data
    );

    let result = Helpers.bytes_to_felt(output_len, output);
    assert [output_ptr] = result;
    assert [output_ptr + 1] = gas_used;
    return ();
}
