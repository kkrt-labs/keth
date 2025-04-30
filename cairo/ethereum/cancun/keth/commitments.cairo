from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
    HashBuiltin,
    KeccakBuiltin,
    SignatureBuiltin,
    EcOpBuiltin,
)
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.default_dict import default_dict_new
from starkware.cairo.common.registers import get_fp_and_pc, get_label_location
from starkware.cairo.common.cairo_keccak.keccak import finalize_keccak
from starkware.cairo.common.alloc import alloc

from ethereum.cancun.fork import (
    _apply_body_inner,
    state_transition,
    BlockChain,
    Block,
    keccak256_header,
    validate_header,
    get_last_256_block_hashes,
    BEACON_ROOTS_ADDRESS,
    SYSTEM_ADDRESS,
    SYSTEM_TRANSACTION_GAS,
)
from legacy.utils.dict import default_dict_finalize
from ethereum_types.bytes import Bytes32, Bytes0
from ethereum_types.numeric import Uint, bool, U256, U256Struct, U64
from ethereum.utils.bytes import Bytes32_to_Bytes
from ethereum.cancun.vm.evm_impl import (
    EvmStruct,
    Message,
    MessageStruct,
    Environment,
    EnvironmentStruct,
    OptionalEvm,
)
from ethereum.crypto.hash import Hash32
from ethereum.cancun.vm.interpreter import process_message_call
from ethereum.cancun.trie import (
    EthereumTriesImpl,
    root,
    MappingBytesOptionalUnionBytesLegacyTransaction,
    MappingBytesOptionalUnionBytesLegacyTransactionStruct,
    BytesOptionalUnionBytesLegacyTransactionDictAccess,
    TrieBytesOptionalUnionBytesLegacyTransactionStruct,
    TrieBytesOptionalUnionBytesLegacyTransaction,
    MappingBytesOptionalUnionBytesReceipt,
    MappingBytesOptionalUnionBytesReceiptStruct,
    BytesOptionalUnionBytesReceiptDictAccess,
    TrieBytesOptionalUnionBytesReceiptStruct,
    TrieBytesOptionalUnionBytesReceipt,
    MappingBytesOptionalUnionBytesWithdrawal,
    MappingBytesOptionalUnionBytesWithdrawalStruct,
    BytesOptionalUnionBytesWithdrawalDictAccess,
    TrieBytesOptionalUnionBytesWithdrawalStruct,
    TrieBytesOptionalUnionBytesWithdrawal,
    OptionalUnionBytesWithdrawal,
    UnionBytesWithdrawalEnum,
)

from ethereum.cancun.state import (
    destroy_account,
    destroy_touched_empty_accounts,
    get_account,
    get_account_code,
    State,
    state_root,
    empty_transient_storage,
    finalize_state,
)

from ethereum.cancun.blocks import (
    Header,
    Header__hash__,
    TupleUnionBytesLegacyTransaction__hash__,
    TupleLog__hash__,
    UnionBytesLegacyTransactionEnum,
    OptionalUnionBytesLegacyTransaction,
    TupleUnionBytesLegacyTransaction,
    TupleLog,
    TupleLogStruct,
    OptionalUnionBytesReceipt,
    UnionBytesReceiptEnum,
    Log,
    LogStruct,
)
from ethereum.utils.numeric import U256__hash__
from ethereum.cancun.fork_types import (
    ListHash32__hash__,
    ListHash32,
    Address,
    OptionalAddress,
    SetAddress,
    SetAddressDictAccess,
    SetAddressStruct,
    SetTupleAddressBytes32,
    SetTupleAddressBytes32DictAccess,
    SetTupleAddressBytes32Struct,
    OptionalMappingAddressBytes32,
    MappingAddressBytes32Struct,
    TupleVersionedHash,
    TupleVersionedHashStruct,
    VersionedHash,
)
from ethereum.cancun.vm.gas import calculate_excess_blob_gas
from ethereum.cancun.transactions_types import To, ToStruct

from cairo_core.bytes_impl import Bytes32__hash__
from cairo_core.hash.blake2s import blake2s_add_uint256, blake2s, blake2s_add_felt

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
