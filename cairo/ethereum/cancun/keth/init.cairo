from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
    HashBuiltin,
)
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_keccak.keccak import finalize_keccak
from ethereum.cancun.fork import (
    BlockChain,
    Block,
    validate_header,
    get_last_256_block_hashes,
    process_system_tx,
)
from ethereum_types.numeric import Uint
from ethereum.cancun.trie import init_tries

from ethereum.cancun.state import finalize_state

from ethereum.cancun.blocks import Header__hash__, TupleLog, TupleLogStruct, Log
from ethereum.cancun.vm.gas import calculate_excess_blob_gas

from ethereum.cancun.keth.commitments import body_commitments, teardown_commitments

func init{
    output_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}() {
    alloc_locals;

    // Fill-in the program inputs through the hints.
    local chain: BlockChain;
    local block: Block;
    %{ init_inputs %}

    // STWO does not prove the keccak builtin, so we need to use a non-builtin keccak
    // implementation.
    let (keccak_ptr) = alloc();
    let keccak_ptr_start = keccak_ptr;
    with keccak_ptr {
        let parent_header = chain.value.blocks.value.data[
            chain.value.blocks.value.len - 1
        ].value.header;

        let excess_blob_gas = calculate_excess_blob_gas(parent_header);
        with_attr error_message("InvalidBlock") {
            assert block.value.header.value.excess_blob_gas = excess_blob_gas;
        }

        validate_header(block.value.header, parent_header);

        with_attr error_message("InvalidBlock") {
            assert block.value.ommers.value.len = 0;
        }

        let state = chain.value.state;
        let block_hashes = get_last_256_block_hashes(chain);

        let fp_and_pc = get_fp_and_pc();
        local __fp__: felt* = fp_and_pc.fp_val;

        tempvar blob_gas_used = Uint(0);
        let gas_available = block.value.header.value.gas_limit;

        let (transactions_trie, receipts_trie, withdrawals_trie) = init_tries();

        let (logs: Log*) = alloc();
        tempvar block_logs = TupleLog(new TupleLogStruct(data=logs, len=0));

        process_system_tx{state=state}(
            block, chain.value.chain_id, excess_blob_gas, block_hashes
        );

        // Finalize the state, getting unique keys for main and storage tries
        finalize_state{state=state}();

        // Commit to the header
        let header_commitment = Header__hash__(block.value.header);

        // Commit to the following body.cairo program
        let body_commitment = body_commitments(
            header_commitment,
            block.value.transactions,
            state,
            transactions_trie,
            receipts_trie,
            block_logs,
            block_hashes,
            gas_available,
            chain.value.chain_id,
            excess_blob_gas,
        );

        // Commit to the teardown program
        let teardown_commitment = teardown_commitments(
            header_commitment, withdrawals_trie, block.value.withdrawals
        );

        assert [output_ptr] = body_commitment.value.low;
        assert [output_ptr + 1] = body_commitment.value.high;

        assert [output_ptr + 2] = teardown_commitment.value.low;
        assert [output_ptr + 3] = teardown_commitment.value.high;
    }

    finalize_keccak(keccak_ptr_start, keccak_ptr);
    let output_ptr = output_ptr + 4;
    return ();
}
