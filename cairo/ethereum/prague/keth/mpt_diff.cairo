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

from cairo_core.bytes_impl import Bytes__hash__, Bytes32__hash__
from ethereum.utils.bytes import Bytes32_to_Bytes, Bytes__eq__

from ethereum.prague.state import state_root
from ethereum.prague.fork import BlockChain
from mpt.types import AccountDiff, StorageDiff
from mpt.utils import sort_account_diff, sort_storage_diff

from mpt.trie_diff import OptionalUnionInternalNodeExtendedImpl, find_branches_to_explore

from mpt.hash_diff import hash_account_diff_segment, hash_storage_diff_segment
from mpt.types import (
    NodeStore,
    OptionalUnionInternalNodeExtended,
    MappingBytes32Bytes32,
    MappingBytes32Address,
)
from mpt.trie_diff import compute_diff_entrypoint

func mpt_diff{
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

    // STWO does not prove the keccak builtin, so we need to use a non-builtin keccak
    // implementation.
    let builtin_keccak_ptr = keccak_ptr;
    let (keccak_ptr) = alloc();
    let keccak_ptr_start = keccak_ptr;

    // MPT diffs inputs
    local node_store: NodeStore;
    local address_preimages: MappingBytes32Address;
    local storage_key_preimages: MappingBytes32Bytes32;
    local post_state_root: OptionalUnionInternalNodeExtended;
    local chain: BlockChain;

    // The diff segment from the previous chunk of mpt_diff
    local input_trie_account_diff: AccountDiff;
    local input_trie_storage_diff: StorageDiff;

    // Index of the sub-MPT branch we want to iterate over;
    local branch_index: felt;

    %{ mpt_diff_inputs %}

    // Hash the inputs to make cryptographic commitments for later stages.
    // Inputs are assumed to be sorted.
    let input_trie_account_diff_commitment = hash_account_diff_segment(input_trie_account_diff);
    let input_trie_storage_diff_commitment = hash_storage_diff_segment(input_trie_storage_diff);

    // # Compute the diff between the pre and post STF MPTs to produce trie diffs.
    let parent_header = chain.value.blocks.value.data[
        chain.value.blocks.value.len - 1
    ].value.header;
    let pre_state_root = parent_header.value.state_root;
    let pre_state_root_bytes = Bytes32_to_Bytes(pre_state_root);
    let pre_state_root_node = OptionalUnionInternalNodeExtendedImpl.from_bytes(
        pre_state_root_bytes
    );

    let (left_node, left_path, right_node, right_path) = find_branches_to_explore{
        node_store=node_store
    }(pre_state_root_node, post_state_root, branch_index);

    // Expected to always be bytes - which is the case with proper inputs.
    let left_mpt_hash = Bytes32__hash__(pre_state_root);
    let right_mpt_hash = Bytes__hash__(post_state_root.value.bytes);

    // The left - right path should always be the same - as we're exploring similar tries.
    with_attr error_message("Left - right path should always be the same") {
        let bytes_eq = Bytes__eq__(left_path, right_path);
        assert bytes_eq.value = 1;
    }

    let main_trie_start = input_trie_account_diff.value.data;
    let main_trie_end = main_trie_start + input_trie_account_diff.value.len;
    let storage_tries_start = input_trie_storage_diff.value.data;
    let storage_tries_end = storage_tries_start + input_trie_storage_diff.value.len;

    let (account_diff, storage_diff) = compute_diff_entrypoint(
        node_store=node_store,
        address_preimages=address_preimages,
        storage_key_preimages=storage_key_preimages,
        left=left_node,
        right=right_node,
        start_path=left_path,
        main_trie_start=main_trie_start,
        main_trie_end=main_trie_end,
        storage_tries_start=storage_tries_start,
        storage_tries_end=storage_tries_end,
    );

    finalize_keccak(keccak_ptr_start, keccak_ptr);

    // # Compute commitments for the state diffs and the trie diffs.
    let account_diff = sort_account_diff(account_diff);
    let storage_diff = sort_storage_diff(storage_diff);
    let trie_account_diff_commitment = hash_account_diff_segment(account_diff);
    let trie_storage_diff_commitment = hash_storage_diff_segment(storage_diff);


    // Output format matching KethMptDiffOutput struct
    assert [output_ptr] = input_trie_account_diff_commitment;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = input_trie_storage_diff_commitment;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = branch_index;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = left_mpt_hash.value.low;
    assert [output_ptr + 1] = left_mpt_hash.value.high;
    let output_ptr = output_ptr + 2;
    assert [output_ptr] = right_mpt_hash.value.low;
    assert [output_ptr + 1] = right_mpt_hash.value.high;
    let output_ptr = output_ptr + 2;
    assert [output_ptr] = trie_account_diff_commitment;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = trie_storage_diff_commitment;
    let output_ptr = output_ptr + 1;

    let keccak_ptr = builtin_keccak_ptr;
    return ();
}
