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
)
from legacy.utils.dict import default_dict_finalize
from ethereum_types.bytes import Bytes32, Bytes0
from ethereum_types.numeric import Uint, bool, U256, U256Struct
from ethereum.utils.bytes import Bytes32_to_Bytes
from ethereum.cancun.vm.evm_impl import (
    EvmStruct,
    Message,
    MessageStruct,
    Environment,
    EnvironmentStruct,
    OptionalEvm,
)
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

    let (transaction_ptr) = default_dict_new(0);
    tempvar transactions_trie_data = MappingBytesOptionalUnionBytesLegacyTransaction(
        new MappingBytesOptionalUnionBytesLegacyTransactionStruct(
            dict_ptr_start=cast(
                transaction_ptr, BytesOptionalUnionBytesLegacyTransactionDictAccess*
            ),
            dict_ptr=cast(transaction_ptr, BytesOptionalUnionBytesLegacyTransactionDictAccess*),
            parent_dict=cast(0, MappingBytesOptionalUnionBytesLegacyTransactionStruct*),
        ),
    );
    tempvar transactions_trie = TrieBytesOptionalUnionBytesLegacyTransaction(
        new TrieBytesOptionalUnionBytesLegacyTransactionStruct(
            secured=bool(0),
            default=OptionalUnionBytesLegacyTransaction(cast(0, UnionBytesLegacyTransactionEnum*)),
            _data=transactions_trie_data,
        ),
    );

    let (receipt_ptr) = default_dict_new(0);
    tempvar receipts_trie_data = MappingBytesOptionalUnionBytesReceipt(
        new MappingBytesOptionalUnionBytesReceiptStruct(
            dict_ptr_start=cast(receipt_ptr, BytesOptionalUnionBytesReceiptDictAccess*),
            dict_ptr=cast(receipt_ptr, BytesOptionalUnionBytesReceiptDictAccess*),
            parent_dict=cast(0, MappingBytesOptionalUnionBytesReceiptStruct*),
        ),
    );
    tempvar receipts_trie = TrieBytesOptionalUnionBytesReceipt(
        new TrieBytesOptionalUnionBytesReceiptStruct(
            secured=bool(0),
            default=OptionalUnionBytesReceipt(cast(0, UnionBytesReceiptEnum*)),
            _data=receipts_trie_data,
        ),
    );

    let (withdrawals_ptr) = default_dict_new(0);
    tempvar withdrawals_trie_data = MappingBytesOptionalUnionBytesWithdrawal(
        new MappingBytesOptionalUnionBytesWithdrawalStruct(
            dict_ptr_start=cast(withdrawals_ptr, BytesOptionalUnionBytesWithdrawalDictAccess*),
            dict_ptr=cast(withdrawals_ptr, BytesOptionalUnionBytesWithdrawalDictAccess*),
            parent_dict=cast(0, MappingBytesOptionalUnionBytesWithdrawalStruct*),
        ),
    );
    tempvar withdrawals_trie = TrieBytesOptionalUnionBytesWithdrawal(
        new TrieBytesOptionalUnionBytesWithdrawalStruct(
            secured=bool(0),
            default=OptionalUnionBytesWithdrawal(cast(0, UnionBytesWithdrawalEnum*)),
            _data=withdrawals_trie_data,
        ),
    );

    let (logs: Log*) = alloc();
    tempvar block_logs = TupleLog(new TupleLogStruct(data=logs, len=0));

    tempvar beacon_roots_address = Address(BEACON_ROOTS_ADDRESS);
    let beacon_roots_account = get_account{state=state}(beacon_roots_address);
    let beacon_block_roots_contract_code = get_account_code{state=state}(
        beacon_roots_address, beacon_roots_account
    );

    let data = Bytes32_to_Bytes(block.value.header.value.parent_beacon_block_root);
    let code_address = OptionalAddress(&beacon_roots_address);

    let (empty_data_ptr) = default_dict_new(0);
    tempvar accessed_addresses = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=cast(empty_data_ptr, SetAddressDictAccess*),
            dict_ptr=cast(empty_data_ptr, SetAddressDictAccess*),
        ),
    );

    let (empty_data_ptr) = default_dict_new(0);
    tempvar accessed_storage_keys = SetTupleAddressBytes32(
        new SetTupleAddressBytes32Struct(
            dict_ptr_start=cast(empty_data_ptr, SetTupleAddressBytes32DictAccess*),
            dict_ptr=cast(empty_data_ptr, SetTupleAddressBytes32DictAccess*),
        ),
    );
    tempvar system_tx_message = Message(
        new MessageStruct(
            caller=Address(SYSTEM_ADDRESS),
            target=To(new ToStruct(bytes0=cast(0, Bytes0*), address=&beacon_roots_address)),
            current_target=beacon_roots_address,
            gas=Uint(SYSTEM_TRANSACTION_GAS),
            value=U256(new U256Struct(0, 0)),
            data=data,
            code_address=code_address,
            code=beacon_block_roots_contract_code,
            depth=Uint(0),
            should_transfer_value=bool(0),
            is_static=bool(0),
            accessed_addresses=accessed_addresses,
            accessed_storage_keys=accessed_storage_keys,
            parent_evm=OptionalEvm(cast(0, EvmStruct*)),
        ),
    );

    let transient_storage = empty_transient_storage();
    let (empty_blob_versioned_hashes: VersionedHash*) = alloc();
    tempvar blob_versioned_hashes_ptr = TupleVersionedHash(
        new TupleVersionedHashStruct(data=cast(empty_blob_versioned_hashes, VersionedHash*), len=0)
    );
    tempvar system_tx_env = Environment(
        new EnvironmentStruct(
            caller=Address(SYSTEM_ADDRESS),
            block_hashes=block_hashes,
            origin=Address(SYSTEM_ADDRESS),
            coinbase=block.value.header.value.coinbase,
            number=block.value.header.value.number,
            base_fee_per_gas=block.value.header.value.base_fee_per_gas,
            gas_limit=block.value.header.value.gas_limit,
            gas_price=block.value.header.value.base_fee_per_gas,
            time=block.value.header.value.timestamp,
            prev_randao=block.value.header.value.prev_randao,
            state=state,
            chain_id=chain.value.chain_id,
            excess_blob_gas=excess_blob_gas,
            blob_versioned_hashes=blob_versioned_hashes_ptr,
            transient_storage=transient_storage,
        ),
    );

    let system_tx_output = process_message_call{env=system_tx_env}(system_tx_message);

    let state = system_tx_env.value.state;
    destroy_touched_empty_accounts{state=state}(system_tx_output.value.touched_accounts);

    // Commit to _apply_body_inner arguments instead of calling it
    //
    // func _apply_body_inner{
    //     state: State,
    //     transactions_trie: TrieBytesOptionalUnionBytesLegacyTransaction,
    //     receipts_trie: TrieBytesOptionalUnionBytesReceipt,
    // }(
    //     index: felt, <- we don't commit to index
    //     len: felt, <- we don't commit to len
    //     transactions: TupleUnionBytesLegacyTransaction,
    //     gas_available: Uint,
    //     chain_id: U64,
    //     base_fee_per_gas: Uint,
    //     excess_blob_gas: U64,
    //     block_logs: TupleLog,
    //     block_hashes: ListHash32,
    //     coinbase: Address,
    //     block_number: Uint,
    //     block_gas_limit: Uint,
    //     block_time: U256,
    //     prev_randao: Bytes32,
    //     blob_gas_used: Uint,
    // )

    // Finalize the state, getting unique keys for main and storage tries
    finalize_state{state=state}();
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
    blake2s_add_felt{data=init_commitment_buffer}(chain.value.chain_id.value, bigend=0);
    blake2s_add_felt{data=init_commitment_buffer}(
        block.value.header.value.base_fee_per_gas.value, bigend=0
    );
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

    assert [output_ptr] = res.low;
    assert [output_ptr + 1] = res.high;

    // TODO: Teardown commitments
    // https://github.com/kkrt-labs/keth/issues/1367
    let output_ptr = output_ptr + 2;
    let keccak_ptr = builtin_keccak_ptr;
    return ();
}
