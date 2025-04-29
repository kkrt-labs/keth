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

from ethereum.cancun.keth.commitments import body_commitments

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
}(start_index: felt, len: felt) {
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
    %{ body_inputs %}

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
    with state, transactions_trie, receipts_trie {
        let (blob_gas_used, gas_available, block_logs) = _apply_body_inner(
            index=start_index,
            len=len,
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
    }
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

    let output_ptr = output_ptr + 6;
    return ();
}
