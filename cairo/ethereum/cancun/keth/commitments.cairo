from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, PoseidonBuiltin
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.alloc import alloc

from legacy.utils.dict import default_dict_finalize
from ethereum_types.numeric import U64, Uint
from ethereum.crypto.hash import Hash32
from ethereum.cancun.trie import (
    EthereumTriesImpl,
    root,
    TrieBytesOptionalUnionBytesLegacyTransaction,
    TrieBytesOptionalUnionBytesReceipt,
    TrieBytesOptionalUnionBytesWithdrawal,
)

from ethereum.cancun.state import State, state_root

from ethereum.cancun.blocks import (
    TupleWithdrawal,
    TupleWithdrawal__hash__,
    TupleUnionBytesLegacyTransaction__hash__,
    TupleLog__hash__,
    TupleUnionBytesLegacyTransaction,
    TupleLog,
)
from ethereum.cancun.fork_types import (
    ListHash32__hash__,
    ListHash32,
    OptionalMappingAddressBytes32,
    MappingAddressBytes32Struct,
)

from cairo_core.hash.blake2s import blake2s_add_uint256, blake2s, blake2s_add_felt

func body_commitments{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: felt*, poseidon_ptr: PoseidonBuiltin*
}(
    header_commitment: Hash32,
    transactions: TupleUnionBytesLegacyTransaction,
    state: State,
    transactions_trie: TrieBytesOptionalUnionBytesLegacyTransaction,
    receipts_trie: TrieBytesOptionalUnionBytesReceipt,
    block_logs: TupleLog,
    block_hashes: ListHash32,
    gas_available: Uint,
    chain_id: U64,
    excess_blob_gas: U64,
) -> Hash32 {
    alloc_locals;
    // Commit to the state
    let state_commitment = state_root(state, 'blake2s');

    // Commit to the transaction and receipt tries
    // Squash the receipts and transactions dicts once they're no longer being modified.
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

    let null_account_roots = OptionalMappingAddressBytes32(cast(0, MappingAddressBytes32Struct*));
    let tx_trie_typed = EthereumTriesImpl.from_transaction_trie(transactions_trie);
    let tx_trie_commitment = root(tx_trie_typed, null_account_roots, 'blake2s');

    let receipt_trie_typed = EthereumTriesImpl.from_receipt_trie(receipts_trie);
    let receipt_trie_commitment = root(receipt_trie_typed, null_account_roots, 'blake2s');

    // Commit to transactions
    let transactions_commitment = TupleUnionBytesLegacyTransaction__hash__(transactions);

    // Commit to logs
    let logs_commitment = TupleLog__hash__(block_logs);

    // Commit to block hashes
    let block_hashes_commitment = ListHash32__hash__(block_hashes);

    // Commit in the order they appear in the function signature
    // Fields that are a single felt are not hashed,
    // simply included in the ultimate_hash in the order they appear in the function signature
    let (init_commitment_buffer) = alloc();
    let start = init_commitment_buffer;
    blake2s_add_uint256{data=init_commitment_buffer}([state_commitment.value]);
    blake2s_add_uint256{data=init_commitment_buffer}([tx_trie_commitment.value]);
    blake2s_add_uint256{data=init_commitment_buffer}([receipt_trie_commitment.value]);
    blake2s_add_uint256{data=init_commitment_buffer}([transactions_commitment.value]);
    blake2s_add_felt{data=init_commitment_buffer}(gas_available.value, bigend=0);
    blake2s_add_felt{data=init_commitment_buffer}(chain_id.value, bigend=0);
    blake2s_add_felt{data=init_commitment_buffer}(excess_blob_gas.value, bigend=0);
    blake2s_add_uint256{data=init_commitment_buffer}([logs_commitment.value]);
    blake2s_add_uint256{data=init_commitment_buffer}([block_hashes_commitment.value]);
    blake2s_add_uint256{data=init_commitment_buffer}([header_commitment.value]);
    let (res) = blake2s(data=start, n_bytes=10 * 32);
    tempvar res_hash = Hash32(value=new res);
    return res_hash;
}

func teardown_commitments{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: felt*, poseidon_ptr: PoseidonBuiltin*
}(
    header_commitment: Hash32,
    withdrawals_trie: TrieBytesOptionalUnionBytesWithdrawal,
    withdrawals: TupleWithdrawal,
) -> Hash32 {
    alloc_locals;

    let (init_commitment_buffer) = alloc();
    let start = init_commitment_buffer;
    blake2s_add_uint256{data=init_commitment_buffer}([header_commitment.value]);

    // Commit to the withdrawals trie
    default_dict_finalize(
        cast(withdrawals_trie.value._data.value.dict_ptr_start, DictAccess*),
        cast(withdrawals_trie.value._data.value.dict_ptr, DictAccess*),
        0,
    );
    let null_account_roots = OptionalMappingAddressBytes32(cast(0, MappingAddressBytes32Struct*));
    let withdrawal_trie_typed = EthereumTriesImpl.from_withdrawal_trie(withdrawals_trie);
    let withdrawal_trie_commitment = root(withdrawal_trie_typed, null_account_roots, 'blake2s');
    blake2s_add_uint256{data=init_commitment_buffer}([withdrawal_trie_commitment.value]);

    // Commit to the withdrawals
    let withdrawals_commitment = TupleWithdrawal__hash__(withdrawals);
    blake2s_add_uint256{data=init_commitment_buffer}([withdrawals_commitment.value]);

    let (res) = blake2s(data=start, n_bytes=3 * 32);
    tempvar res_hash = Hash32(value=new res);
    return res_hash;
}
