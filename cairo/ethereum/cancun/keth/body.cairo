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
from ethereum_types.numeric import U64, Uint
from ethereum.cancun.trie import (
    TrieBytesOptionalUnionBytesLegacyTransaction,
    TrieBytesOptionalUnionBytesReceipt,
)
from ethereum.cancun.fork_types import (
    MappingAddressAccount,
    MappingAddressAccountStruct,
    ListHash32,
)
from ethereum.cancun.state import State, StateStruct, finalize_state
from ethereum.cancun.trie import TrieAddressOptionalAccount, TrieAddressOptionalAccountStruct
from ethereum.cancun.blocks import (
    Header,
    Header__hash__,
    TupleUnionBytesLegacyTransaction,
    TupleLog,
)

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
    local block_header: Header;
    local block_transactions: TupleUnionBytesLegacyTransaction;
    local state: State;
    local transactions_trie: TrieBytesOptionalUnionBytesLegacyTransaction;
    local receipts_trie: TrieBytesOptionalUnionBytesReceipt;
    local block_logs: TupleLog;
    local block_hashes: ListHash32;
    local gas_available: Uint;
    local chain_id: U64;
    local blob_gas_used: Uint;
    local excess_blob_gas: U64;
    local start_index: felt;
    local len: felt;
    %{ body_inputs %}

    // // Because in args_gen we want to generate a state with (prev, new) tuples, we pass an initial snapshot of the state.
    // // However we don't need this inside the cairo program, so we just set the parent dict of the state to an empty pointer.
    // // Otherwise, this would trigger an assertion error in state.cairo when computing the state root.
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

    // STWO does not prove the keccak builtin, so we need to use a non-builtin keccak
    // implementation.
    let builtin_keccak_ptr = keccak_ptr;
    let (keccak_ptr) = alloc();
    let keccak_ptr_start = keccak_ptr;

    // Input Commitments
    let header_commitment = Header__hash__(block_header);
    let initial_args_commitment = body_commitments(
        header_commitment,
        block_transactions,
        state,
        transactions_trie,
        receipts_trie,
        block_logs,
        block_hashes,
        gas_available,
        chain_id,
        excess_blob_gas,
    );

    // Execution
    let (blob_gas_used, gas_available, block_logs) = _apply_body_inner{
        state=state, transactions_trie=transactions_trie, receipts_trie=receipts_trie
    }(
        index=start_index,
        len=start_index + len,
        transactions=block_transactions,
        gas_available=gas_available,
        chain_id=chain_id,
        base_fee_per_gas=block_header.value.base_fee_per_gas,
        excess_blob_gas=excess_blob_gas,
        block_logs=block_logs,
        block_hashes=block_hashes,
        coinbase=block_header.value.coinbase,
        block_number=block_header.value.number,
        block_gas_limit=block_header.value.gas_limit,
        block_time=block_header.value.timestamp,
        prev_randao=block_header.value.prev_randao,
        blob_gas_used=blob_gas_used,
    );
    finalize_state{state=state}();

    // Output Commitments
    let post_exec_commitment = body_commitments(
        header_commitment,
        block_transactions,
        state,
        transactions_trie,
        receipts_trie,
        block_logs,
        block_hashes,
        gas_available,
        chain_id,
        excess_blob_gas,
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
