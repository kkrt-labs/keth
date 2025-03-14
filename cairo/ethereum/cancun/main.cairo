%builtins output pedersen range_check ecdsa bitwise ec_op keccak poseidon range_check96 add_mod mul_mod
// In proof mode running with RustVM requires declaring all builtins of the layout and taking them as entrypoint
// see: <https://github.com/lambdaclass/cairo-vm/issues/2004>

from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    KeccakBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
    HashBuiltin,
    SignatureBuiltin,
    EcOpBuiltin,
)
from ethereum.cancun.fork import state_transition, BlockChain, Block, keccak256_header
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
    %{
        from ethereum.cancun.fork import BlockChain, Block
        from ethereum_types.bytes import Bytes32

        ids.chain = gen_arg(BlockChain, program_inputs["blockchain"])
        ids.block = gen_arg(Block, program_inputs["block"])
    %}

    let parent_header = chain.value.blocks.value.data[
        chain.value.blocks.value.len - 1
    ].value.header;
    let pre_state_root = parent_header.value.state_root;
    let post_state_root = block.value.header.value.state_root;

    state_transition{chain=chain}(block);

    let block_hash = keccak256_header(block.value.header);

    assert [output_ptr] = pre_state_root.value.low;
    assert [output_ptr + 1] = pre_state_root.value.high;
    assert [output_ptr + 2] = post_state_root.value.low;
    assert [output_ptr + 3] = post_state_root.value.high;
    assert [output_ptr + 4] = block_hash.value.low;
    assert [output_ptr + 5] = block_hash.value.high;

    let output_ptr = output_ptr + 6;
    return ();
}
