%builtins output pedersen range_check ecdsa bitwise ec_op keccak poseidon range_check96 add_mod mul_mod
// In proof mode running with RustVM requires declaring all builtins and taking them as entrypoint
// This is probably a mis-handling from the RustVM side.

from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    KeccakBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
    HashBuiltin,
    SignatureBuiltin,
    EcOpBuiltin,
)
from ethereum.cancun.fork import state_transition, BlockChain, Block
from ethereum_types.bytes import Bytes32

func main{
    output_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    ec_op_ptr: EcOpBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}() {
    alloc_locals;

    local chain: BlockChain;
    local block: Block;
    local pre_state_root: Bytes32;
    local post_state_root: Bytes32;
    local block_hash: Bytes32;
    %{
        from ethereum.cancun.fork import BlockChain, Block
        from ethereum_types.bytes import Bytes32

        # Note: for efficiency purposes, we don't use the `ids` object to
        # avoid loading program identifiers into the context.
        memory[fp+2] = gen_arg(Bytes32, public_inputs["pre_state_root"])
        memory[fp+3] = gen_arg(Bytes32, public_inputs["post_state_root"])
        memory[fp+4] = gen_arg(Bytes32, public_inputs["block_hash"])

        memory[fp] = gen_arg(BlockChain, private_inputs["blockchain"])
        memory[fp+1] = gen_arg(Block, private_inputs["block"])
    %}

    state_transition{chain=chain}(block);

    assert [output_ptr] = pre_state_root.value.low;
    assert [output_ptr + 1] = pre_state_root.value.high;
    assert [output_ptr + 2] = post_state_root.value.low;
    assert [output_ptr + 3] = post_state_root.value.high;
    assert [output_ptr + 4] = block_hash.value.low;
    assert [output_ptr + 5] = block_hash.value.high;

    let output_ptr = output_ptr + 6;
    return ();
}
