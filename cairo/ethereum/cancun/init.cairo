%builtins output pedersen range_check ecdsa bitwise ec_op keccak poseidon range_check96 add_mod mul_mod
// In proof mode running with RustVM requires declaring all builtins of the layout and taking them as entrypoint
// see: <https://github.com/lambdaclass/cairo-vm/issues/2004>

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
    state_transition,
    BlockChain,
    Block,
    keccak256_header,
    validate_header,
    get_last_256_block_hashes,
    BEACON_ROOTS_ADDRESS,
    SYSTEM_ADDRESS,
    SYSTEM_TRANSACTION_GAS,
    process_system_tx,
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
    init_tries,
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

    // STWO does not prove the keccak builtin, so we need to use a non-builtin keccak
    // implementation.
    let builtin_keccak_ptr = keccak_ptr;
    let (keccak_ptr) = alloc();
    let keccak_ptr_start = keccak_ptr;

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

    process_system_tx{range_check_ptr=range_check_ptr, poseidon_ptr=poseidon_ptr, state=state}(
        block, chain.value.chain_id, excess_blob_gas, block_hashes
    );


    // Finalize the state, getting unique keys for main and storage tries
    finalize_state{state=state}();
    let init_commitment = init_commitments{
        range_check_ptr=range_check_ptr,
        bitwise_ptr=bitwise_ptr,
        keccak_ptr=keccak_ptr,
        poseidon_ptr=poseidon_ptr,
    }(
        block,
        state,
        transactions_trie,
        receipts_trie,
        withdrawals_trie,
        block_logs,
        block_hashes,
        gas_available,
        chain.value.chain_id,
        block.value.header.value.base_fee_per_gas,
        excess_blob_gas,
    );

    assert [output_ptr] = init_commitment.value.low;
    assert [output_ptr + 1] = init_commitment.value.high;

    // TODO: Teardown commitments
    // https://github.com/kkrt-labs/keth/issues/1367
    let output_ptr = output_ptr + 2;
    let keccak_ptr = builtin_keccak_ptr;
    return ();
}

func init_commitments{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: felt*, poseidon_ptr: PoseidonBuiltin*
}(
    block: Block,
    state: State,
    transactions_trie: TrieBytesOptionalUnionBytesLegacyTransaction,
    receipts_trie: TrieBytesOptionalUnionBytesReceipt,
    withdrawals_trie: TrieBytesOptionalUnionBytesWithdrawal,
    block_logs: TupleLog,
    block_hashes: ListHash32,
    gas_available: Uint,
    chain_id: U64,
    base_fee_per_gas: Uint,
    excess_blob_gas: U64,
) -> Hash32 {
    alloc_locals;
    // Commit to the state
    let state_commitment = state_root(state, 'blake2s');

    // Commit to the transaction, withdrawal and receipt tries
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
    let tx_trie_commitment = root(tx_trie_typed, null_account_roots, 'blake2s');

    let receipt_trie_typed = EthereumTriesImpl.from_receipt_trie(receipts_trie);
    let receipt_trie_commitment = root(receipt_trie_typed, null_account_roots, 'blake2s');

    let withdrawal_trie_typed = EthereumTriesImpl.from_withdrawal_trie(withdrawals_trie);
    let withdrawal_trie_commitment = root(withdrawal_trie_typed, null_account_roots, 'blake2s');

    // Commit to transactions
    let transactions_commitment = TupleUnionBytesLegacyTransaction__hash__(
        block.value.transactions
    );

    // Commit to logs
    let logs_commitment = TupleLog__hash__(block_logs);

    // Commit to block hashes
    let block_hashes_commitment = ListHash32__hash__(block_hashes);

    // Commit to block time and prev_randao
    let block_time_commitment = U256__hash__(block.value.header.value.timestamp);
    let prev_randao_commitment = Bytes32__hash__(block.value.header.value.prev_randao);

    // Commit in the order they appear in the function signature
    // Fields that are a single felt are not hashed,
    // simply included in the ultimate_hash in the order they appear in the function signature
    let (init_commitment_buffer) = alloc();
    let start = init_commitment_buffer;
    blake2s_add_uint256{data=init_commitment_buffer}([state_commitment.value]);
    blake2s_add_uint256{data=init_commitment_buffer}([tx_trie_commitment.value]);
    blake2s_add_uint256{data=init_commitment_buffer}([receipt_trie_commitment.value]);
    blake2s_add_uint256{data=init_commitment_buffer}([withdrawal_trie_commitment.value]);
    blake2s_add_uint256{data=init_commitment_buffer}([transactions_commitment.value]);
    blake2s_add_felt{data=init_commitment_buffer}(gas_available.value, bigend=0);
    blake2s_add_felt{data=init_commitment_buffer}(chain_id.value, bigend=0);
    blake2s_add_felt{data=init_commitment_buffer}(base_fee_per_gas.value, bigend=0);
    blake2s_add_felt{data=init_commitment_buffer}(excess_blob_gas.value, bigend=0);
    blake2s_add_uint256{data=init_commitment_buffer}([logs_commitment.value]);
    blake2s_add_uint256{data=init_commitment_buffer}([block_hashes_commitment.value]);
    blake2s_add_felt{data=init_commitment_buffer}(
        block.value.header.value.coinbase.value, bigend=0
    );
    blake2s_add_felt{data=init_commitment_buffer}(block.value.header.value.number.value, bigend=0);
    blake2s_add_felt{data=init_commitment_buffer}(
        block.value.header.value.gas_limit.value, bigend=0
    );
    blake2s_add_uint256{data=init_commitment_buffer}([block_time_commitment.value]);
    blake2s_add_uint256{data=init_commitment_buffer}([prev_randao_commitment.value]);
    blake2s_add_felt{data=init_commitment_buffer}(
        block.value.header.value.gas_used.value, bigend=0
    );

    let (res) = blake2s(data=start, n_bytes=17 * 32);
    tempvar res_hash = Hash32(value=new res);
    return res_hash;
}
