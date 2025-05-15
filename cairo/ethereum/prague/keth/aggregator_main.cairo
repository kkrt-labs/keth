%builtins output pedersen range_check ecdsa bitwise ec_op keccak poseidon range_check96 add_mod mul_mod
// In proof mode running with RustVM requires declaring all builtins of the layout and taking them as entrypoint
// see: <https://github.com/lambdaclass/cairo-vm/issues/2004>

from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
    HashBuiltin,
    SignatureBuiltin,
    EcOpBuiltin,
)
from ethereum.cancun.keth.aggregator import aggregator

//@notice Main entry point for the Keth STF Aggregator.
//@params program_input: dict
//        The program input is a dictionary with the following keys:
//        - "keth_segment_outputs": list of lists of Keth segment outputs ([[init_output], [body1_output], ..., [bodyN_output], [teardown_output]])
//        - "keth_segment_program_hashes": dict of program hashes for each Keth segment ("init": H_init, "body": H_body, "teardown": H_teardown)
//        - "n_body_chunks": int - number of body chunks executed as part of the Keth execution
func main{
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
}() {
    aggregator();
    return ();
}
