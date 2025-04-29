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
    TupleWithdrawal,
    TupleWithdrawal__hash__,
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

from ethereum.cancun.keth.commitments import body_commitments

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

    // Commit to the header
    let header_commitment = Header__hash__(block.value.header);

    // Commit to the following body.cairo program
    let body_commitment = body_commitments{
        range_check_ptr=range_check_ptr,
        bitwise_ptr=bitwise_ptr,
        keccak_ptr=keccak_ptr,
        poseidon_ptr=poseidon_ptr,
    }(
        header_commitment,
        block.value.transactions,
        state,
        transactions_trie,
        receipts_trie,
        block_logs,
        block_hashes,
        gas_available,
        chain.value.chain_id,
        excess_blob_gas,
    );

    // Commit to the teardown program
    let teardown_commitment = teardown_commitments{
        range_check_ptr=range_check_ptr,
        bitwise_ptr=bitwise_ptr,
        keccak_ptr=keccak_ptr,
        poseidon_ptr=poseidon_ptr,
    }(header_commitment, withdrawals_trie, block.value.withdrawals);

    assert [output_ptr] = body_commitment.value.low;
    assert [output_ptr + 1] = body_commitment.value.high;

    assert [output_ptr + 2] = teardown_commitment.value.low;
    assert [output_ptr + 3] = teardown_commitment.value.high;

    let output_ptr = output_ptr + 4;
    let keccak_ptr = builtin_keccak_ptr;
    return ();
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
