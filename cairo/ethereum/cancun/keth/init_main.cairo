%builtins output pedersen range_check bitwise poseidon range_check96 add_mod mul_mod
// In proof mode running with RustVM requires declaring all builtins of the layout and taking them as entrypoint
// see: <https://github.com/lambdaclass/cairo-vm/issues/2004>

from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    PoseidonBuiltin,
    HashBuiltin,
    ModBuiltin,
)
from ethereum.cancun.keth.init import init

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
    init();
    return ();
}
