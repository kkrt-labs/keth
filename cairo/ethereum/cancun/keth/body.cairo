from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
    HashBuiltin,
    SignatureBuiltin,
    EcOpBuiltin,
)
from starkware.cairo.common.cairo_keccak.keccak import finalize_keccak
from starkware.cairo.common.alloc import alloc

from ethereum.cancun.fork import _apply_body_inner
from ethereum.cancun.vm import BlockOutput, BlockOutput__hash__
from ethereum.cancun.fork_types import MappingAddressAccount, MappingAddressAccountStruct
from ethereum.cancun.state import State, StateStruct, finalize_state
from ethereum.cancun.trie import TrieAddressOptionalAccount, TrieAddressOptionalAccountStruct
from ethereum.cancun.vm.env_impl import (
    BlockEnvironment,
    BlockEnvironmentStruct,
    BlockEnv__hash__,
    BlockEnvImpl,
)
from ethereum.cancun.blocks import Header, Header__hash__, TupleUnionBytesLegacyTransaction

from ethereum.cancun.keth.commitments import body_commitments

func body{
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

    // Program inputs
    // TODO update the hints
    local block_header: Header;
    local block_transactions: TupleUnionBytesLegacyTransaction;
    local block_env: BlockEnvironment;
    local block_output: BlockOutput;
    local start_index: felt;
    local len: felt;
    %{ body_inputs %}

    // // Because in args_gen we want to generate a state with (prev, new) tuples, we pass an initial snapshot of the state.
    // // However we don't need this inside the cairo program, so we just set the parent dict of the state to an empty pointer.
    // // Otherwise, this would trigger an assertion error in state.cairo when computing the state root.
    let state = block_env.value.state;
    tempvar main_trie_data = MappingAddressAccount(
        new MappingAddressAccountStruct(
            dict_ptr_start=state.value._main_trie.value._data.value.dict_ptr_start,
            dict_ptr=state.value._main_trie.value._data.value.dict_ptr,
            parent_dict=cast(0, MappingAddressAccountStruct*),
        ),
    );
    tempvar main_trie = TrieAddressOptionalAccount(
        new TrieAddressOptionalAccountStruct(
            secured=state.value._main_trie.value.secured,
            default=state.value._main_trie.value.default,
            _data=main_trie_data,
        ),
    );
    tempvar state = State(
        new StateStruct(
            _main_trie=main_trie,
            _storage_tries=state.value._storage_tries,
            created_accounts=state.value.created_accounts,
            original_storage_tries=state.value.original_storage_tries,
        ),
    );

    // TODO add block_gas_limit to input hint
    tempvar block_env = BlockEnvironment(
        new BlockEnvironmentStruct(
            chain_id=block_env.value.chain_id,
            state=state,
            block_gas_limit=block_env.value.block_gas_limit,
            block_hashes=block_env.value.block_hashes,
            coinbase=block_env.value.coinbase,
            number=block_env.value.number,
            base_fee_per_gas=block_env.value.base_fee_per_gas,
            time=block_env.value.time,
            prev_randao=block_env.value.prev_randao,
            excess_blob_gas=block_env.value.excess_blob_gas,
            parent_beacon_block_root=block_env.value.parent_beacon_block_root,
        ),
    );

    // STWO does not prove the keccak builtin, so we need to use a non-builtin keccak
    // implementation.
    let builtin_keccak_ptr = keccak_ptr;
    let (keccak_ptr) = alloc();
    let keccak_ptr_start = keccak_ptr;

    // Input Commitments
    let header_commitment = Header__hash__(block_header);
    let block_env_commitment = BlockEnv__hash__(block_env);
    let block_output_commitment = BlockOutput__hash__(block_output);
    let initial_args_commitment = body_commitments(
        header_commitment, block_env_commitment, block_output_commitment, block_transactions
    );

    // Execution
    _apply_body_inner{block_env=block_env, block_output=block_output}(
        index=start_index, len=start_index + len, transactions=block_transactions
    );
    let state = block_env.value.state;
    finalize_state{state=state}();
    BlockEnvImpl.set_state{block_env=block_env}(state);

    // Output Commitments
    let post_exec_commitment = body_commitments(
        header_commitment, block_env_commitment, block_output_commitment, block_transactions
    );

    assert [output_ptr] = initial_args_commitment.value.low;
    assert [output_ptr + 1] = initial_args_commitment.value.high;
    assert [output_ptr + 2] = post_exec_commitment.value.low;
    assert [output_ptr + 3] = post_exec_commitment.value.high;
    assert [output_ptr + 4] = start_index;
    assert [output_ptr + 5] = len;

    finalize_keccak(keccak_ptr_start, keccak_ptr);
    let keccak_ptr = builtin_keccak_ptr;
    let output_ptr = output_ptr + 6;
    return ();
}
