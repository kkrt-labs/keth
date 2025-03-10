%builtins output range_check bitwise keccak poseidon range_check96 add_mod mul_mod

from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    KeccakBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
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
    local prestate_root: Bytes32;
    local poststate_root: Bytes32;
    local block_hash: Bytes32;
    %{
        from ethereum.cancun.fork import BlockChain, Block
        from ethereum_types.bytes import Bytes32

        memory[fp+2] = gen_arg(Bytes32, public_inputs["prestate_root"])
        memory[fp+3] = gen_arg(Bytes32, public_inputs["poststate_root"])
        memory[fp+4] = gen_arg(Bytes32, public_inputs["block_hash"])

        memory[fp] = gen_arg(BlockChain, private_inputs["blockchain"])
        memory[fp+1] = gen_arg(Block, private_inputs["block"])
    %}

    state_transition{chain=chain}(block);

    assert [output_ptr] = prestate_root.value.low;
    assert [output_ptr + 1] = prestate_root.value.high;
    assert [output_ptr + 2] = poststate_root.value.low;
    assert [output_ptr + 3] = poststate_root.value.high;
    assert [output_ptr + 4] = block_hash.value.low;
    assert [output_ptr + 5] = block_hash.value.high;

    let output_ptr = output_ptr + 3;
    return();
}
