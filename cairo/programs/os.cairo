%builtins output

from starkware.cairo.common.memcpy import memcpy

from src.model import model

func main{output_ptr: felt*}() {
    tempvar block_info: model.BlockInfo*;
    %{
        ids.block_info = segments.add()
        block_hashes = segments.add()
        segments.write_arg(block_hashes, list(range(32 * 2)))
        segments.write_arg(ids.block_info.address_, list(range(8)) + [block_hashes])
    %}

    assert [output_ptr] = block_info.coinbase;
    assert [output_ptr + 1] = block_info.timestamp;
    assert [output_ptr + 2] = block_info.number;
    assert [output_ptr + 3] = block_info.prev_randao.low;
    assert [output_ptr + 4] = block_info.prev_randao.high;
    assert [output_ptr + 5] = block_info.gas_limit;
    assert [output_ptr + 6] = block_info.chain_id;
    assert [output_ptr + 7] = block_info.base_fee;

    memcpy(output_ptr + 8, cast(block_info.block_hashes, felt*), 32 * 2);

    let output_ptr = output_ptr + 8 + 32 * 2;

    return ();
}
