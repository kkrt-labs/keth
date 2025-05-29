from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
    HashBuiltin,
    SignatureBuiltin,
    EcOpBuiltin,
)
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_keccak.keccak import finalize_keccak
from ethereum.prague.fork_types import (
    Address,
    OptionalMappingAddressBytes32,
    MappingAddressBytes32Struct,
)
from ethereum.prague.fork import (
    BlockChain,
    Block,
    validate_header,
    get_last_256_block_hashes,
    process_unchecked_system_transaction,
    BEACON_ROOTS_ADDRESS,
)
from ethereum.prague.trie import EthereumTriesImpl, root

from ethereum.prague.state import finalize_state

from ethereum.utils.bytes import Bytes32_to_Bytes
from ethereum.prague.blocks import Header__hash__
from ethereum.prague.vm import BlockOutput__hash__, empty_block_output
from ethereum.prague.vm.env_impl import (
    BlockEnvironment,
    BlockEnvironmentStruct,
    BlockEnvImpl,
    BlockEnv__hash__,
)
from ethereum.prague.keth.commitments import body_commitments, teardown_commitments

func init{
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
    alloc_locals;

    // Fill-in the program inputs through the hints.
    local chain: BlockChain;
    local block: Block;
    %{ init_inputs %}

    // STWO does not prove the keccak builtin, so we need to use a non-builtin keccak
    // implementation.
    let builtin_keccak_ptr = keccak_ptr;
    let (keccak_ptr) = alloc();
    let keccak_ptr_start = keccak_ptr;
    let parent_header = chain.value.blocks.value.data[
        chain.value.blocks.value.len - 1
    ].value.header;

    validate_header{keccak_ptr=keccak_ptr}(chain, block.value.header);

    with_attr error_message("InvalidBlock") {
        assert block.value.ommers.value.len = 0;
    }

    let state = chain.value.state;
    let block_hashes = get_last_256_block_hashes(chain);

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let state = chain.value.state;
    let block_hashes = get_last_256_block_hashes(chain);
    tempvar block_env = BlockEnvironment(
        new BlockEnvironmentStruct(
            chain_id=chain.value.chain_id,
            state=chain.value.state,
            block_gas_limit=block.value.header.value.gas_limit,
            block_hashes=block_hashes,
            coinbase=block.value.header.value.coinbase,
            number=block.value.header.value.number,
            base_fee_per_gas=block.value.header.value.base_fee_per_gas,
            time=block.value.header.value.timestamp,
            prev_randao=block.value.header.value.prev_randao,
            excess_blob_gas=block.value.header.value.excess_blob_gas,
            parent_beacon_block_root=block.value.header.value.parent_beacon_block_root,
        ),
    );

    let data_bytes = Bytes32_to_Bytes(block_env.value.parent_beacon_block_root);
    process_unchecked_system_transaction{block_env=block_env}(
        target_address=Address(BEACON_ROOTS_ADDRESS), data=data_bytes
    );

    let last_block_hash = block_env.value.block_hashes.value.data[
        block_env.value.block_hashes.value.len - 1
    ];
    let last_block_hash_bytes = Bytes32_to_Bytes(last_block_hash);
    process_unchecked_system_transaction{block_env=block_env}(
        target_address=Address(HISTORY_STORAGE_ADDRESS), data=last_block_hash_bytes
    );
    let state = block_env.value.state;

    let block_output = empty_block_output();
    let transactions_trie = block_output.value.transactions_trie;
    let receipts_trie = block_output.value.receipts_trie;
    let withdrawals_trie = block_output.value.withdrawals_trie;
    let block_logs = block_output.value.block_logs;
    let gas_available = block_env.value.block_gas_limit;
    let excess_blob_gas = block_env.value.excess_blob_gas;

    // Finalize the state, getting unique keys for main and storage tries
    finalize_state{state=state}();
    BlockEnvImpl.set_state{block_env=block_env}(state);

    // Commit to the header, block_env, and block_output
    let header_commitment = Header__hash__(block.value.header);
    let block_env_commitment = BlockEnv__hash__(block_env);
    let block_output_commitment = BlockOutput__hash__(block_output);

    // Commit to the following body.cairo program
    let body_commitment = body_commitments(
        header_commitment, block_env_commitment, block_output_commitment, block.value.transactions
    );

    // Commit to the teardown program
    let null_account_roots = OptionalMappingAddressBytes32(cast(0, MappingAddressBytes32Struct*));
    let withdrawal_trie_typed = EthereumTriesImpl.from_withdrawal_trie(withdrawals_trie);
    let withdrawal_trie_commitment = root(withdrawal_trie_typed, null_account_roots, 'blake2s');
    let teardown_commitment = teardown_commitments(
        header_commitment, withdrawal_trie_commitment, block.value.withdrawals
    );

    assert [output_ptr] = body_commitment.value.low;
    assert [output_ptr + 1] = body_commitment.value.high;

    assert [output_ptr + 2] = teardown_commitment.value.low;
    assert [output_ptr + 3] = teardown_commitment.value.high;

    finalize_keccak(keccak_ptr_start, keccak_ptr);
    let keccak_ptr = builtin_keccak_ptr;
    let output_ptr = output_ptr + 4;
    return ();
}
