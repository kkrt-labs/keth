from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, PoseidonBuiltin
from starkware.cairo.common.alloc import alloc

from ethereum.crypto.hash import Hash32

from ethereum.cancun.blocks import (
    TupleWithdrawal,
    TupleWithdrawal__hash__,
    TupleUnionBytesLegacyTransaction__hash__,
    TupleUnionBytesLegacyTransaction,
)

from cairo_core.hash.blake2s import blake2s, blake2s_add_uint256

func body_commitments{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: felt*, poseidon_ptr: PoseidonBuiltin*
}(
    header_commitment: Hash32,
    block_env_commitment: Hash32,
    block_output_commitment: Hash32,
    transactions: TupleUnionBytesLegacyTransaction,
) -> Hash32 {
    alloc_locals;

    // Commit to transactions
    let transactions_commitment = TupleUnionBytesLegacyTransaction__hash__(transactions);

    // Commit in the order they appear in the function signature
    // Fields that are a single felt are not hashed,
    // simply included in the ultimate_hash in the order they appear in the function signature
    let (init_commitment_buffer) = alloc();
    let start = init_commitment_buffer;
    blake2s_add_uint256{data=init_commitment_buffer}([header_commitment.value]);
    blake2s_add_uint256{data=init_commitment_buffer}([block_env_commitment.value]);
    blake2s_add_uint256{data=init_commitment_buffer}([block_output_commitment.value]);
    blake2s_add_uint256{data=init_commitment_buffer}([transactions_commitment.value]);
    let (res) = blake2s(data=start, n_bytes=4 * 32);
    tempvar res_hash = Hash32(value=new res);
    return res_hash;
}

func teardown_commitments{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: felt*, poseidon_ptr: PoseidonBuiltin*
}(
    header_commitment: Hash32, withdrawal_trie_commitment: Hash32, withdrawals: TupleWithdrawal
) -> Hash32 {
    alloc_locals;

    let (init_commitment_buffer) = alloc();
    let start = init_commitment_buffer;
    blake2s_add_uint256{data=init_commitment_buffer}([header_commitment.value]);
    blake2s_add_uint256{data=init_commitment_buffer}([withdrawal_trie_commitment.value]);

    // Commit to the withdrawals
    let withdrawals_commitment = TupleWithdrawal__hash__(withdrawals);
    blake2s_add_uint256{data=init_commitment_buffer}([withdrawals_commitment.value]);

    let (res) = blake2s(data=start, n_bytes=3 * 32);
    tempvar res_hash = Hash32(value=new res);
    return res_hash;
}
