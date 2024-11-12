from ethereum.crypto.hash import keccak256, Hash32
from ethereum.base_types import Bytes
from starkware.cairo.common.cairo_builtins import KeccakBuiltin, BitwiseBuiltin

func test_keccak256{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}(
    ) -> Hash32 {
    tempvar buffer: Bytes;
    %{ memory[ap - 1] = gen_arg(program_input["buffer"]) %}
    let hash = keccak256(buffer);
    return hash;
}
