from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
    HashBuiltin,
    SignatureBuiltin,
    EcOpBuiltin,
)
from ethereum.cancun.fork import state_transition, BlockChain, Block, keccak256_header
from ethereum_types.bytes import Bytes32
from ethereum.utils.bytes import Bytes32_to_Bytes
from mpt.trie_diff import OptionalUnionInternalNodeExtendedImpl

from ethereum.cancun.keth.body import main

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
    local start_index;
    local len;
    %{ ids.start_index = program_input["start_index"] %}
    %{ ids.len = program_input["len"] %}
    local output_start: felt* = output_ptr;
    main(start_index=start_index, len=len);
    return (output_start=output_start);
}
