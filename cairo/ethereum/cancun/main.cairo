%builtins output range_check bitwise keccak poseidon range_check96 add_mod mul_mod
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
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}() {
    alloc_locals;

    local chain: BlockChain;
    local block: Block;
    local block_hash: Bytes32;
    %{
        from ethereum.cancun.fork import BlockChain, Block
        from ethereum_types.bytes import Bytes32

        # Note: for efficiency purposes, we don't use the `ids` object to
        # avoid loading program identifiers into the context.
        # see: README of cairo-addons crate
        memory[fp] = gen_arg(BlockChain, public_inputs["blockchain"])
        memory[fp+1] = gen_arg(Block, public_inputs["block"])
        memory[fp+2] = gen_arg(Bytes32, public_inputs["block_hash"])
    %}

    let parent_header = chain.value.blocks.value.data[
        chain.value.blocks.value.len - 1
    ].value.header;
    let pre_state_root = parent_header.value.state_root;
    let post_state_root = block.value.header.value.state_root;

    state_transition{chain=chain}(block);

    // TODO: we must ensure that hash of last block = block_hash

    assert [output_ptr] = pre_state_root.value.low;
    assert [output_ptr + 1] = pre_state_root.value.high;
    assert [output_ptr + 2] = post_state_root.value.low;
    assert [output_ptr + 3] = post_state_root.value.high;
    assert [output_ptr + 4] = block_hash.value.low;
    assert [output_ptr + 5] = block_hash.value.high;

    let output_ptr = output_ptr + 6;
    return ();
}
