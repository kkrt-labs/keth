from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
    HashBuiltin,
    SignatureBuiltin,
    EcOpBuiltin,
)
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.cairo_keccak.keccak import finalize_keccak
from starkware.cairo.common.alloc import alloc

from ethereum.cancun.bloom import logs_bloom
from ethereum.cancun.fork import BlockChainStruct, _process_withdrawals_inner, BlockChain, Block
from legacy.utils.dict import default_dict_finalize
from ethereum_types.numeric import U64, Uint
from ethereum.utils.bytes import Bytes32_to_Bytes, Bytes32__eq__, Bytes256__eq__
from ethereum.cancun.trie import (
    EthereumTriesImpl,
    root,
    TrieBytesOptionalUnionBytesLegacyTransaction,
    TrieBytesOptionalUnionBytesReceipt,
    TrieBytesOptionalUnionBytesWithdrawal,
    TrieAddressOptionalAccount,
    TrieAddressOptionalAccountStruct,
)

from ethereum.cancun.state import State, StateStruct, state_root, finalize_state
from ethereum.cancun.keth.commitments import teardown_commitments, body_commitments

from ethereum.cancun.blocks import Header__hash__, TupleUnionBytesLegacyTransaction, TupleLog
from ethereum.cancun.fork_types import (
    MappingAddressAccount,
    MappingAddressAccountStruct,
    ListHash32,
    OptionalMappingAddressBytes32,
    MappingAddressBytes32Struct,
)

from mpt.trie_diff import OptionalUnionInternalNodeExtendedImpl

from mpt.hash_diff import (
    hash_state_storage_diff,
    hash_state_account_diff,
    hash_account_diff_segment,
    hash_storage_diff_segment,
)
from mpt.types import (
    NodeStore,
    OptionalUnionInternalNodeExtended,
    MappingBytes32Bytes32,
    MappingBytes32Address,
)
from mpt.trie_diff import compute_diff_entrypoint
from mpt.utils import sort_account_diff, sort_storage_diff

func teardown{
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

    // Program inputs from the init.cairo program.
    local block: Block;
    local chain: BlockChain;
    local withdrawals_trie: TrieBytesOptionalUnionBytesWithdrawal;

    // Program inputs from the body.cairo program.
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

    // MPT diffs inputs
    local node_store: NodeStore;
    local address_preimages: MappingBytes32Address;
    local storage_key_preimages: MappingBytes32Bytes32;
    local post_state_root: OptionalUnionInternalNodeExtended;

    // Fill-in the program inputs through the hints.
    %{ teardown_inputs %}

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

    // Commit to the same inputs as the init.cairo's outputs.
    let header = block.value.header;
    let header_commitment = Header__hash__(header);
    let teardown_commitment = teardown_commitments{
        range_check_ptr=range_check_ptr,
        bitwise_ptr=bitwise_ptr,
        keccak_ptr=keccak_ptr,
        poseidon_ptr=poseidon_ptr,
    }(header_commitment, withdrawals_trie, block.value.withdrawals);

    assert [output_ptr] = teardown_commitment.value.low;
    assert [output_ptr + 1] = teardown_commitment.value.high;
    let output_ptr = output_ptr + 2;

    // Commit to the same inputs as the body.cairo's outputs.
    let body_commitment = body_commitments{
        range_check_ptr=range_check_ptr,
        bitwise_ptr=bitwise_ptr,
        keccak_ptr=keccak_ptr,
        poseidon_ptr=poseidon_ptr,
    }(
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
    assert [output_ptr] = body_commitment.value.low;
    assert [output_ptr + 1] = body_commitment.value.high;
    let output_ptr = output_ptr + 2;

    // Commit to the same inputs as the body.cairo's outputs.

    // Start the teardown process when _apply_body_inner stops.
    tempvar block_gas_used = Uint(block.value.header.value.gas_limit.value - gas_available.value);
    let block_logs_bloom = logs_bloom(block_logs);

    _process_withdrawals_inner{state=state, trie=withdrawals_trie}(0, block.value.withdrawals);

    // Squash the receipts, transactions, and withdrawals dicts once they're no longer being modified.
    default_dict_finalize(
        cast(transactions_trie.value._data.value.dict_ptr_start, DictAccess*),
        cast(transactions_trie.value._data.value.dict_ptr, DictAccess*),
        0,
    );
    default_dict_finalize(
        cast(receipts_trie.value._data.value.dict_ptr_start, DictAccess*),
        cast(receipts_trie.value._data.value.dict_ptr, DictAccess*),
        0,
    );
    default_dict_finalize(
        cast(withdrawals_trie.value._data.value.dict_ptr_start, DictAccess*),
        cast(withdrawals_trie.value._data.value.dict_ptr, DictAccess*),
        0,
    );

    let null_account_roots = OptionalMappingAddressBytes32(cast(0, MappingAddressBytes32Struct*));
    let tx_trie_typed = EthereumTriesImpl.from_transaction_trie(transactions_trie);
    let transactions_root = root(tx_trie_typed, null_account_roots, 'keccak256');

    let receipt_trie_typed = EthereumTriesImpl.from_receipt_trie(receipts_trie);
    let receipts_root = root(receipt_trie_typed, null_account_roots, 'keccak256');

    let withdrawal_trie_typed = EthereumTriesImpl.from_withdrawal_trie(withdrawals_trie);
    let withdrawals_root = root(withdrawal_trie_typed, null_account_roots, 'keccak256');

    finalize_state{state=state}();

    // rebind state
    tempvar chain = BlockChain(
        new BlockChainStruct(blocks=chain.value.blocks, state=state, chain_id=chain.value.chain_id)
    );

    with_attr error_message("InvalidBlock") {
        assert block_gas_used = block.value.header.value.gas_used;

        let transactions_root_equal = Bytes32__eq__(
            transactions_root, block.value.header.value.transactions_root
        );
        assert transactions_root_equal.value = 1;

        // Diff with EELS: Because our approach is based on state-diffs instead of re-computation of the
        // state root, we don't check that the state root is equal to the one in the block.
        // Instead, we assert that the State Transition is correct by ensuring the diffs it produces
        // are the same as the one of the expected post-MPT.

        let receipt_root_equal = Bytes32__eq__(
            receipts_root, block.value.header.value.receipt_root
        );
        assert receipt_root_equal.value = 1;

        let logs_bloom_equal = Bytes256__eq__(block_logs_bloom, block.value.header.value.bloom);
        assert logs_bloom_equal.value = 1;

        let withdrawals_root_equal = Bytes32__eq__(
            withdrawals_root, block.value.header.value.withdrawals_root
        );
        assert withdrawals_root_equal.value = 1;

        assert blob_gas_used.value = block.value.header.value.blob_gas_used.value;
    }

    // # Compute the diff between the pre and post STF MPTs to produce trie diffs.
    let parent_header = chain.value.blocks.value.data[
        chain.value.blocks.value.len - 1
    ].value.header;
    let pre_state_root = parent_header.value.state_root;
    let pre_state_root_bytes = Bytes32_to_Bytes(pre_state_root);
    let pre_state_root_node = OptionalUnionInternalNodeExtendedImpl.from_bytes(
        pre_state_root_bytes
    );
    let (account_diff, storage_diff) = compute_diff_entrypoint{keccak_ptr=keccak_ptr}(
        node_store=node_store,
        address_preimages=address_preimages,
        storage_key_preimages=storage_key_preimages,
        left=pre_state_root_node,
        right=post_state_root,
    );

    finalize_keccak(keccak_ptr_start, keccak_ptr);

    // # Compute commitments for the state diffs and the trie diffs.
    let account_diff = sort_account_diff(account_diff);
    let storage_diff = sort_storage_diff(storage_diff);

    let trie_account_diff_commitment = hash_account_diff_segment(account_diff);
    let trie_storage_diff_commitment = hash_storage_diff_segment(storage_diff);

    let state_account_diff_commitment = hash_state_account_diff(chain.value.state);
    let state_storage_diff_commitment = hash_state_storage_diff(chain.value.state);

    with_attr error_message("STF and Trie diffs are not equal") {
        assert state_account_diff_commitment = trie_account_diff_commitment;
        assert state_storage_diff_commitment = trie_storage_diff_commitment;
    }

    let keccak_ptr = builtin_keccak_ptr;
    return ();
}
