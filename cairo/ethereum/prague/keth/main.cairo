%builtins output pedersen range_check ecdsa bitwise ec_op keccak poseidon range_check96 add_mod mul_mod
// In proof mode running with RustVM requires declaring all builtins of the layout and taking them as entrypoint
// see: <https://github.com/lambdaclass/cairo-vm/issues/2004>

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
from ethereum.prague.fork import Block, BlockChain, state_transition
from ethereum.utils.bytes import Bytes32_to_Bytes
from cairo_core.bytes import Bytes, BytesStruct
from mpt.trie_diff import OptionalUnionInternalNodeExtendedImpl
from mpt.types import StorageDiffEntry, AddressAccountDiffEntry

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

func main{
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
    local node_store: NodeStore;
    local address_preimages: MappingBytes32Address;
    local storage_key_preimages: MappingBytes32Bytes32;
    local post_state_root: OptionalUnionInternalNodeExtended;
    %{ main_inputs %}

    // # Execute STF on the initial state, to produce state diffs.
    let parent_header = chain.value.blocks.value.data[
        chain.value.blocks.value.len - 1
    ].value.header;

    // STWO does not prove the keccak builtin, so we need to use a non-builtin keccak
    // implementation.
    let builtin_keccak_ptr = keccak_ptr;
    let (keccak_ptr) = alloc();
    let keccak_ptr_start = keccak_ptr;
    state_transition{chain=chain}(block);
    // # Compute the diff between the pre and post STF MPTs to produce trie diffs.
    let pre_state_root = parent_header.value.state_root;
    let pre_state_root_bytes = Bytes32_to_Bytes(pre_state_root);
    let pre_state_root_node = OptionalUnionInternalNodeExtendedImpl.from_bytes(
        pre_state_root_bytes
    );
    let (buffer) = alloc();
    tempvar path = Bytes(new BytesStruct(buffer, 0));

    let (main_trie_end: AddressAccountDiffEntry*) = alloc();
    local main_trie_start: AddressAccountDiffEntry* = main_trie_end;
    let (storage_tries_end: StorageDiffEntry*) = alloc();
    let storage_tries_start = storage_tries_end;

    let (account_diff, storage_diff) = compute_diff_entrypoint(
        node_store=node_store,
        address_preimages=address_preimages,
        storage_key_preimages=storage_key_preimages,
        left=pre_state_root_node,
        right=post_state_root,
        start_path=path,
        main_trie_start=main_trie_start,
        main_trie_end=main_trie_end,
        storage_tries_start=storage_tries_start,
        storage_tries_end=storage_tries_end,
    );

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

    assert [output_ptr] = pre_state_root.value.low;
    assert [output_ptr + 1] = pre_state_root.value.high;
    assert [output_ptr + 2] = state_account_diff_commitment;
    assert [output_ptr + 3] = state_storage_diff_commitment;
    assert [output_ptr + 4] = trie_account_diff_commitment;
    assert [output_ptr + 5] = trie_storage_diff_commitment;

    finalize_keccak(keccak_ptr_start, keccak_ptr);
    let keccak_ptr = builtin_keccak_ptr;
    let output_ptr = output_ptr + 6;
    return ();
}
