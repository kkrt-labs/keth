from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, PoseidonBuiltin, ModBuiltin
from starkware.cairo.common.default_dict import default_dict_new
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.math import (
    assert_not_zero,
    split_felt,
    assert_le_felt,
    assert_not_equal,
)
from starkware.cairo.common.math_cmp import is_le, is_le_felt
from starkware.cairo.common.registers import get_fp_and_pc
from cairo_core.control_flow import raise

from ethereum_rlp.rlp import (
    encode_receipt_to_buffer,
    encode_header,
    encode_uint,
    encode_withdrawal,
    encode_transaction,
)
from ethereum_types.bytes import (
    Bytes,
    Bytes0,
    Bytes20,
    BytesStruct,
    TupleBytes32,
    TupleBytes,
    TupleBytesStruct,
    OptionalHash32,
    Bytes32Struct,
    ListBytes,
    ListBytesStruct,
)
from ethereum_types.numeric import Uint, bool, U256, U256Struct, U64, OptionalUint
from ethereum.prague.blocks import (
    UnionBytesReceipt,
    OptionalUnionBytesReceipt,
    OptionalUnionBytesLegacyTransaction,
    OptionalUnionBytesWithdrawal,
    UnionBytesReceiptEnum,
    Header,
    Receipt,
    ReceiptStruct,
    TupleLog,
    Block,
    ListBlock,
    ListBlockStruct,
    UnionBytesLegacyTransaction,
    TupleUnionBytesLegacyTransaction,
    TupleWithdrawal,
    Withdrawal,
    WithdrawalStruct,
)
from ethereum.prague.bloom import logs_bloom
from ethereum.prague.trie import (
    get_tuple_address_bytes32_preimage_for_key,
    trie_set_TrieBytesOptionalUnionBytesLegacyTransaction,
    TrieAddressOptionalAccountStruct,
    root,
    EthereumTries,
    EthereumTriesEnum,
    TrieAddressOptionalAccount,
    TrieBytes32U256,
    trie_set_TrieBytesOptionalUnionBytesReceipt,
    TrieBytesOptionalUnionBytesLegacyTransaction,
    TrieBytesOptionalUnionBytesLegacyTransactionStruct,
    TrieBytesOptionalUnionBytesReceipt,
    TrieBytesOptionalUnionBytesReceiptStruct,
    TrieBytesOptionalUnionBytesWithdrawal,
    TrieBytesOptionalUnionBytesWithdrawalStruct,
    UnionBytesWithdrawalEnum,
    trie_set_TrieBytesOptionalUnionBytesWithdrawal,
    TrieBytes32U256Struct,
)
from ethereum.prague.fork_types import (
    OptionalAccount,
    AccountStruct,
    Address,
    ListHash32,
    ListHash32Struct,
    OptionalAddress,
    SetAddress,
    SetAddressStruct,
    SetAddressDictAccess,
    SetTupleAddressBytes32,
    SetTupleAddressBytes32Struct,
    SetTupleAddressBytes32DictAccess,
    TupleAddressUintTupleVersionedHashU64,
    TupleAddressUintTupleVersionedHashU64Struct,
    TupleVersionedHash,
    TupleVersionedHashStruct,
    VersionedHash,
    OptionalMappingAddressBytes32,
    MappingAddressBytes32Struct,
    Authorization,
    TupleAuthorization,
    TupleAuthorizationStruct,
)
from ethereum.prague.requests import (
    compute_requests_hash,
    parse_deposit_requests,
    DEPOSIT_REQUEST_TYPE,
    WITHDRAWAL_REQUEST_TYPE,
    CONSOLIDATION_REQUEST_TYPE,
)

from ethereum.prague.state import (
    set_storage,
    account_exists_and_is_empty,
    destroy_account,
    get_account,
    get_account_code,
    increment_nonce,
    set_account,
    set_account_balance,
    State,
    StateStruct,
    empty_transient_storage,
    process_withdrawal,
    finalize_state,
)
from ethereum.prague.transactions_types import (
    Transaction,
    get_transaction_type,
    get_gas,
    get_max_fee_per_gas,
    get_max_priority_fee_per_gas,
    get_gas_price,
    get_nonce,
    get_value,
    TransactionType,
    TupleAccess,
    TupleAccessStruct,
    To,
    ToStruct,
    get_to,
    get_authorizations_unchecked,
)
from ethereum.prague.transactions import (
    calculate_intrinsic_cost,
    validate_transaction,
    get_transaction_hash,
    decode_transaction,
)
from ethereum.prague.utils.message import prepare_message
from ethereum.prague.vm import empty_block_output, BlockOutput, BlockOutputStruct
from ethereum.prague.vm.evm_impl import Message, MessageStruct, Evm, EvmStruct
from ethereum.prague.vm.env_impl import (
    BlockEnvironment,
    BlockEnvironmentStruct,
    BlockEnvImpl,
    TransactionEnvironment,
    TransactionEnvironmentStruct,
)
from ethereum.prague.vm.exceptions import InvalidBlock
from ethereum.prague.vm.gas import (
    calculate_data_fee,
    calculate_total_blob_gas,
    calculate_blob_gas_price,
    calculate_excess_blob_gas,
)
from ethereum.prague.vm.interpreter import process_message_call, MessageCallOutput
from ethereum.prague.vm.eoa_delegation import is_valid_delegation
from ethereum.crypto.hash import keccak256, Hash32
from ethereum.exceptions import OptionalEthereumException
from ethereum.utils.numeric import (
    divmod,
    min,
    max,
    U256_add,
    U256_sub,
    U256__eq__,
    U256_from_Uint,
    U256_le,
    U256_to_Uint,
    U256_add_with_carry,
)
from ethereum.prague.transactions import recover_sender
from ethereum.prague.vm.instructions.block import _append_logs
from ethereum.utils.hash_dicts import set_address_contains
from ethereum.utils.bytes import Bytes256__eq__, Bytes32__eq__, Bytes32_to_Bytes, Bytes__extend__
from cairo_core.comparison import is_zero

from legacy.utils.dict import hashdict_write, default_dict_finalize

const ELASTICITY_MULTIPLIER = 2;
const BASE_FEE_MAX_CHANGE_DENOMINATOR = 8;
const GAS_LIMIT_ADJUSTMENT_FACTOR = 1024;
const GAS_LIMIT_MINIMUM = 5000;
const EMPTY_OMMER_HASH_LOW = 0x1ad4ccb667b585ab7a5dc7dee84dcc1d;
const EMPTY_OMMER_HASH_HIGH = 0x4793d440fd42a1f013748a941b4512d3;
const VERSIONED_HASH_VERSION_KZG = 0x01;
// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-4788.md
const SYSTEM_ADDRESS = 0xFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
const BEACON_ROOTS_ADDRESS = 0x2ACBED02285BBB8B79F31F17E8032D7F63D0F00;
const SYSTEM_TRANSACTION_GAS = 30000000;

struct BlockChainStruct {
    blocks: ListBlock,
    state: State,
    chain_id: U64,
}

struct BlockChain {
    value: BlockChainStruct*,
}

using Root = Hash32;

const MAX_BLOB_GAS_PER_BLOCK = 1179648;

const WITHDRAWAL_REQUEST_PREDEPLOY_ADDRESS = 0x270004ca67935d89ad1805eb50e48ef61090000;
const CONSOLIDATION_REQUEST_PREDEPLOY_ADDRESS = 0x51720090a5f3008b9f57fb428648cec7ddbb0000;
const HISTORY_STORAGE_ADDRESS = 0x3529002053175b33027acb103ac5f12708f90000;
const HISTORY_SERVE_WINDOW = 8192;

func calculate_base_fee_per_gas{range_check_ptr}(
    block_gas_limit: Uint,
    parent_gas_limit: Uint,
    parent_gas_used: Uint,
    parent_base_fee_per_gas: Uint,
) -> Uint {
    alloc_locals;
    let (parent_gas_target, _) = divmod(parent_gas_limit.value, ELASTICITY_MULTIPLIER);

    let cond_ = check_gas_limit(block_gas_limit, parent_gas_limit);
    with_attr error_message("InvalidBlock") {
        assert_not_zero(cond_.value);
    }

    if (parent_gas_used.value == parent_gas_target) {
        return parent_base_fee_per_gas;
    }

    let cond = is_le(parent_gas_target + 1, parent_gas_used.value);
    if (cond == TRUE) {
        let gas_used_delta = parent_gas_used.value - parent_gas_target;
        let parent_fee_gas_delta = parent_base_fee_per_gas.value * gas_used_delta;
        let (target_fee_gas_delta, _) = divmod(parent_fee_gas_delta, parent_gas_target);
        let (base_fee_per_gas_delta, _) = divmod(
            target_fee_gas_delta, BASE_FEE_MAX_CHANGE_DENOMINATOR
        );
        if (base_fee_per_gas_delta == 0) {
            let base_fee_per_gas = Uint(parent_base_fee_per_gas.value + 1);
            return base_fee_per_gas;
        }
        let base_fee_per_gas = Uint(parent_base_fee_per_gas.value + base_fee_per_gas_delta);
        return base_fee_per_gas;
    }

    let gas_used_delta = parent_gas_target - parent_gas_used.value;
    let parent_fee_gas_delta = parent_base_fee_per_gas.value * gas_used_delta;
    let (target_fee_gas_delta, _) = divmod(parent_fee_gas_delta, parent_gas_target);
    let (base_fee_per_gas_delta, _) = divmod(target_fee_gas_delta, BASE_FEE_MAX_CHANGE_DENOMINATOR);

    let base_fee_per_gas = Uint(parent_base_fee_per_gas.value - base_fee_per_gas_delta);
    return base_fee_per_gas;
}

// @notice Verifies a block header.
// @param chain History and current state.
// @param header Header to check for correctness.
func validate_header{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: felt*}(
    chain: BlockChain, header: Header
) {
    alloc_locals;

    with_attr error_message("InvalidBlock") {
        assert_not_equal(header.value.number.value, 0);
    }

    let parent_header = chain.value.blocks.value.data[
        chain.value.blocks.value.len - 1
    ].value.header;

    let excess_blob_gas = calculate_excess_blob_gas(parent_header);
    with_attr error_message("InvalidBlock") {
        assert header.value.excess_blob_gas = excess_blob_gas;
    }

    with_attr error_message("InvalidBlock") {
        assert [range_check_ptr] = header.value.gas_limit.value - header.value.gas_used.value;
        let range_check_ptr = range_check_ptr + 1;

        let expected_base_fee_per_gas = calculate_base_fee_per_gas(
            header.value.gas_limit,
            parent_header.value.gas_limit,
            parent_header.value.gas_used,
            parent_header.value.base_fee_per_gas,
        );

        assert expected_base_fee_per_gas = header.value.base_fee_per_gas;

        let timestamp_invalid = U256_le(header.value.timestamp, parent_header.value.timestamp);
        assert timestamp_invalid.value = 0;

        let number_is_valid = is_zero(
            header.value.number.value - parent_header.value.number.value - 1
        );
        assert number_is_valid = 1;

        let extra_data_is_valid = is_le(header.value.extra_data.value.len, 32);
        assert extra_data_is_valid = 1;

        assert header.value.difficulty.value = 0;

        assert header.value.nonce.value = 0;

        assert header.value.ommers_hash.value.low = EMPTY_OMMER_HASH_LOW;
        assert header.value.ommers_hash.value.high = EMPTY_OMMER_HASH_HIGH;

        let parent_block_hash = keccak256_header(parent_header);
        let are_equal = Bytes32__eq__(header.value.parent_hash, parent_block_hash);
        assert are_equal.value = 1;
    }
    return ();
}

func check_gas_limit{range_check_ptr}(gas_limit: Uint, parent_gas_limit: Uint) -> bool {
    alloc_locals;
    let (max_adjustment_delta, _) = divmod(parent_gas_limit.value, GAS_LIMIT_ADJUSTMENT_FACTOR);
    let cond = is_le(parent_gas_limit.value + max_adjustment_delta, gas_limit.value);
    if (cond == TRUE) {
        tempvar value = bool(FALSE);
        return value;
    }
    let cond = is_le(gas_limit.value, parent_gas_limit.value - max_adjustment_delta);
    if (cond == TRUE) {
        tempvar value = bool(FALSE);
        return value;
    }
    let cond = is_le(gas_limit.value, GAS_LIMIT_MINIMUM);
    if (cond == TRUE) {
        tempvar value = bool(FALSE);
        return value;
    }

    tempvar value = bool(TRUE);
    return value;
}

func make_receipt{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: felt*}(
    tx: Transaction, error: OptionalEthereumException, cumulative_gas_used: Uint, logs: TupleLog
) -> UnionBytesReceipt {
    alloc_locals;
    if (cast(error.value, felt) != 0) {
        [ap] = 0, ap++;
    } else {
        [ap] = 1, ap++;
    }
    let succeeded = bool([ap - 1]);

    let bloom = logs_bloom(logs);
    tempvar receipt = Receipt(
        new ReceiptStruct(
            succeeded=succeeded, cumulative_gas_used=cumulative_gas_used, bloom=bloom, logs=logs
        ),
    );

    let encoded_receipt = encode_receipt(tx, receipt);
    return encoded_receipt;
}

func process_system_transaction{
    range_check_ptr,
    poseidon_ptr: PoseidonBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    block_env: BlockEnvironment,
}(target_address: Address, system_contract_code: Bytes, data: Bytes) -> MessageCallOutput {
    alloc_locals;

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

    let transient_storage = empty_transient_storage();

    tempvar blob_versioned_hashes = TupleVersionedHash(
        new TupleVersionedHashStruct(data=cast(0, VersionedHash*), len=0)
    );
    tempvar authorizations = TupleAuthorization(
        new TupleAuthorizationStruct(data=cast(0, Authorization*), len=0)
    );

    tempvar index_in_block = OptionalUint(new 0);
    tempvar tx_hash = OptionalHash32(cast(0, Bytes32Struct*));

    tempvar tx_env = TransactionEnvironment(
        new TransactionEnvironmentStruct(
            origin=Address(SYSTEM_ADDRESS),
            gas_price=block_env.value.base_fee_per_gas,
            gas=Uint(SYSTEM_TRANSACTION_GAS),
            access_list_addresses=accessed_addresses,
            access_list_storage_keys=accessed_storage_keys,
            transient_storage=transient_storage,
            blob_versioned_hashes=blob_versioned_hashes,
            authorizations=authorizations,
            index_in_block=index_in_block,
            tx_hash=tx_hash,
        ),
    );

    tempvar u256_zero = U256(new U256Struct(0, 0));

    tempvar target_to = To(new ToStruct(bytes0=cast(0, Bytes0*), address=new target_address));
    tempvar optional_code_address = OptionalAddress(new target_address.value);

    tempvar system_tx_message = Message(
        new MessageStruct(
            block_env=block_env,
            tx_env=tx_env,
            caller=Address(SYSTEM_ADDRESS),
            target=target_to,
            current_target=target_address,
            gas=Uint(SYSTEM_TRANSACTION_GAS),
            value=u256_zero,
            data=data,
            code_address=optional_code_address,
            code=Bytes(system_contract_code.value),
            depth=Uint(0),
            should_transfer_value=bool(0),
            is_static=bool(0),
            accessed_addresses=accessed_addresses,
            accessed_storage_keys=accessed_storage_keys,
            disable_precompiles=bool(0),
            parent_evm=Evm(cast(0, EvmStruct*)),
        ),
    );

    let (system_tx_output, block_env) = process_message_call(system_tx_message);
    return system_tx_output;
}

// @notice Process a system transaction and raise an error if the contract does not
// contain code or if the transaction fails.
// @param block_env The block scoped environment.
// @param target_address The address of the contract to call.
// @param data The data to pass to the contract.
// @return system_tx_output The output of processing the system transaction.
func process_checked_system_transaction{
    range_check_ptr,
    poseidon_ptr: PoseidonBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    block_env: BlockEnvironment,
}(target_address: Address, data: Bytes) -> MessageCallOutput {
    alloc_locals;
    let state = block_env.value.state;
    let system_contract_account = get_account{state=state}(target_address);
    let system_contract_code = get_account_code{state=state}(
        target_address, system_contract_account
    );
    if (system_contract_code.value.len == 0) {
        raise('InvalidBlock');
    }

    BlockEnvImpl.set_state{block_env=block_env}(state);
    let system_tx_output = process_system_transaction{block_env=block_env}(
        target_address, system_contract_code, data
    );
    if (cast(system_tx_output.value.error, felt) != 0) {
        raise('InvalidBlock');
    }
    return system_tx_output;
}

// @notice Process a system transaction without checking if the contract contains code
// or if the transaction fails.
// @param block_env The block scoped environment.
// @param target_address The address of the contract to call.
// @param data The data to pass to the contract.
// @return system_tx_output The output of processing the system transaction.
func process_unchecked_system_transaction{
    range_check_ptr,
    poseidon_ptr: PoseidonBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    block_env: BlockEnvironment,
}(target_address: Address, data: Bytes) -> MessageCallOutput {
    alloc_locals;
    let state = block_env.value.state;
    let system_contract_account = get_account{state=state}(target_address);
    let system_contract_code = get_account_code{state=state}(
        target_address, system_contract_account
    );
    BlockEnvImpl.set_state{block_env=block_env}(state);
    let system_tx_output = process_system_transaction{block_env=block_env}(
        target_address, system_contract_code, data
    );
    return system_tx_output;
}

func process_transaction{
    range_check_ptr,
    poseidon_ptr: PoseidonBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    block_env: BlockEnvironment,
    block_output: BlockOutput,
}(encoded_tx: UnionBytesLegacyTransaction, index: Uint) {
    alloc_locals;

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let encoded_index = encode_uint(index);
    let tx = decode_transaction(encoded_tx);
    let tx_value = get_value(tx);

    let transactions_trie = block_output.value.transactions_trie;
    trie_set_TrieBytesOptionalUnionBytesLegacyTransaction{trie=transactions_trie}(
        encoded_index, OptionalUnionBytesLegacyTransaction(encoded_tx.value)
    );

    // Validate transaction
    let (intrinsic_gas, calldata_floor_gas_cost) = validate_transaction(tx);

    let tuple_address_uint_tuple_versioned_hash_u64 = check_transaction{block_env=block_env}(
        block_output, tx
    );
    let sender = tuple_address_uint_tuple_versioned_hash_u64.value.address;
    let effective_gas_price = tuple_address_uint_tuple_versioned_hash_u64.value.uint;
    let blob_versioned_hashes = tuple_address_uint_tuple_versioned_hash_u64.value.tuple_versioned_hash;
    let tx_blob_gas_used = tuple_address_uint_tuple_versioned_hash_u64.value.u64;

    // Get sender account
    let state = block_env.value.state;
    let sender_account = get_account{state=state}(sender);

    // Get relevant transaction data
    local tx_gas: Uint;
    local tx_data: Bytes;
    local tx_to: To;
    local tx_value: U256;
    local blob_gas_fee: Uint;
    local access_lists: TupleAccess;
    if (tx.value.blob_transaction.value != 0) {
        assert tx_gas = tx.value.blob_transaction.value.gas;
        assert tx_data = tx.value.blob_transaction.value.data;
        assert tx_to = To(
            new ToStruct(bytes0=cast(0, Bytes0*), address=&tx.value.blob_transaction.value.to)
        );
        assert tx_value = tx.value.blob_transaction.value.value;
        let blob_gas_fee_res = calculate_data_fee(block_env.value.excess_blob_gas, tx);
        assert blob_gas_fee = blob_gas_fee_res;
        assert access_lists = tx.value.blob_transaction.value.access_list;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar range_check_ptr = range_check_ptr;
    }

    let range_check_ptr = [ap - 1];

    if (tx.value.fee_market_transaction.value != 0) {
        assert tx_gas = tx.value.fee_market_transaction.value.gas;
        assert tx_data = tx.value.fee_market_transaction.value.data;
        assert tx_to = tx.value.fee_market_transaction.value.to;
        assert tx_value = tx.value.fee_market_transaction.value.value;
        assert blob_gas_fee = Uint(0);
        assert access_lists = tx.value.fee_market_transaction.value.access_list;
    }

    if (tx.value.legacy_transaction.value != 0) {
        assert tx_gas = tx.value.legacy_transaction.value.gas;
        assert tx_data = tx.value.legacy_transaction.value.data;
        assert tx_to = tx.value.legacy_transaction.value.to;
        assert tx_value = tx.value.legacy_transaction.value.value;
        assert blob_gas_fee = Uint(0);
        assert access_lists = TupleAccess(cast(0, TupleAccessStruct*));
    }

    if (tx.value.access_list_transaction.value != 0) {
        assert tx_gas = tx.value.access_list_transaction.value.gas;
        assert tx_data = tx.value.access_list_transaction.value.data;
        assert tx_to = tx.value.access_list_transaction.value.to;
        assert tx_value = tx.value.access_list_transaction.value.value;
        assert blob_gas_fee = Uint(0);
        assert access_lists = tx.value.access_list_transaction.value.access_list;
    }

    let effective_gas_fee = tx_gas.value * effective_gas_price.value;

    // Calculate available gas, does not overflow as it was checked in validate_transaction before.
    let intrinsic_cost = calculate_intrinsic_cost(tx);
    let gas = tx_gas.value - intrinsic_gas.value;

    // Increment nonce
    increment_nonce{state=state}(sender);

    // Deduct gas fee from sender
    tempvar effective_gas_fee_u256 = U256(new U256Struct(effective_gas_fee, 0));
    tempvar blob_gas_fee_u256 = U256(new U256Struct(blob_gas_fee.value, 0));
    let sender_balance_after_gas_fee = U256_sub(
        sender_account.value.balance, effective_gas_fee_u256
    );
    let sender_balance_after_gas_fee_u256 = U256_sub(
        sender_balance_after_gas_fee, blob_gas_fee_u256
    );
    set_account_balance{state=state}(sender, sender_balance_after_gas_fee_u256);
    BlockEnvImpl.set_state{block_env=block_env}(state);

    // Create preaccessed addresses and write coinbase
    let (access_list_addresses_ptr) = default_dict_new(0);
    tempvar access_list_addresses_start = access_list_addresses_ptr;
    let address = block_env.value.coinbase;
    hashdict_write{dict_ptr=access_list_addresses_ptr}(1, &address.value, 1);
    tempvar access_list_addresses = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=cast(access_list_addresses_start, SetAddressDictAccess*),
            dict_ptr=cast(access_list_addresses_ptr, SetAddressDictAccess*),
        ),
    );
    // Create preaccessed storage keys
    let (access_list_storage_keys_ptr) = default_dict_new(0);
    tempvar access_list_storage_keys = SetTupleAddressBytes32(
        new SetTupleAddressBytes32Struct(
            dict_ptr_start=cast(access_list_storage_keys_ptr, SetTupleAddressBytes32DictAccess*),
            dict_ptr=cast(access_list_storage_keys_ptr, SetTupleAddressBytes32DictAccess*),
        ),
    );

    if (tx.value.legacy_transaction.value == 0) {
        process_access_list{
            preaccessed_addresses=access_list_addresses,
            preaccessed_storage_keys=access_list_storage_keys,
        }(access_lists, access_lists.value.len, 0);
        tempvar keccak_ptr = keccak_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar range_check_ptr = range_check_ptr;
        tempvar access_list_addresses = access_list_addresses;
        tempvar access_list_storage_keys = access_list_storage_keys;
    } else {
        tempvar keccak_ptr = keccak_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar range_check_ptr = range_check_ptr;
        tempvar access_list_addresses = access_list_addresses;
        tempvar access_list_storage_keys = access_list_storage_keys;
    }

    let keccak_ptr = cast([ap - 5], felt*);
    let bitwise_ptr = cast([ap - 4], BitwiseBuiltin*);
    let range_check_ptr = [ap - 3];
    let access_list_addresses = SetAddress(cast([ap - 2], SetAddressStruct*));
    let access_list_storage_keys = SetTupleAddressBytes32(
        cast([ap - 1], SetTupleAddressBytes32Struct*)
    );

    tempvar access_list_addresses = access_list_addresses;
    tempvar access_list_storage_keys = access_list_storage_keys;

    // Squash the access_list_addresses and access_list_storage_keys here -
    // they're copied needed.
    default_dict_finalize(
        cast(access_list_addresses.value.dict_ptr_start, DictAccess*),
        cast(access_list_addresses.value.dict_ptr, DictAccess*),
        0,
    );

    default_dict_finalize(
        cast(access_list_storage_keys.value.dict_ptr_start, DictAccess*),
        cast(access_list_storage_keys.value.dict_ptr, DictAccess*),
        0,
    );

    tempvar code_address = OptionalAddress(cast(0, Address*));

    let transient_storage = empty_transient_storage();
    let encoded_tx = encode_transaction(tx);

    tempvar index_in_block = OptionalUint(new index);
    let transaction_hash = get_transaction_hash(encoded_tx);
    tempvar tx_hash = OptionalHash32(cast(transaction_hash.value, Bytes32Struct*));
    let authorizations = get_authorizations_unchecked(tx);
    tempvar tx_env = TransactionEnvironment(
        new TransactionEnvironmentStruct(
            origin=sender,
            gas_price=effective_gas_price,
            gas=Uint(gas),
            access_list_addresses=access_list_addresses,
            access_list_storage_keys=access_list_storage_keys,
            transient_storage=transient_storage,
            blob_versioned_hashes=blob_versioned_hashes,
            authorizations=authorizations,
            index_in_block=index_in_block,
            tx_hash=tx_hash,
        ),
    );
    let message = prepare_message{block_env=block_env, tx_env=tx_env}(tx);

    let (tx_output, block_env) = process_message_call(message);
    // Rebind block_env's state modified in `process_message_call`
    let state = block_env.value.state;

    // Calculate gas refund
    with_attr error_message("OverflowError") {
        assert tx_output.value.refund_counter.value.high = 0;
        assert_le_felt(block_env.value.base_fee_per_gas.value, effective_gas_price.value);
    }
    let tx_gas_used_before_refund = tx_gas.value - tx_output.value.gas_left.value;
    let (gas_refund_div_5, _) = divmod(tx_gas_used_before_refund, 5);
    let tx_gas_refund = min(gas_refund_div_5, tx_output.value.refund_counter.value.low);
    let tx_gas_used_after_refund = tx_gas_used_before_refund - tx_gas_refund;
    let tx_gas_used_after_refund = max(tx_gas_used_after_refund, calldata_floor_gas_cost.value);
    let tx_gas_left = tx_gas.value - tx_gas_used_after_refund;

    // INVARIANT: tx_gas_left does not wrap around the prime field
    assert [range_check_ptr] = tx_gas_left;
    let range_check_ptr = range_check_ptr + 1;

    let gas_refund_amount = tx_gas_left * effective_gas_price.value;
    assert [range_check_ptr] = gas_refund_amount;
    let range_check_ptr = range_check_ptr + 1;

    // Calculate priority fee
    let priority_fee_per_gas = effective_gas_price.value - block_env.value.base_fee_per_gas.value;
    assert [range_check_ptr] = priority_fee_per_gas;
    let range_check_ptr = range_check_ptr + 1;

    let transaction_fee = tx_gas_used_after_refund * priority_fee_per_gas;
    assert [range_check_ptr] = transaction_fee;
    let range_check_ptr = range_check_ptr + 1;

    let sender_account = get_account{state=state}(sender);
    let (high, low) = split_felt(gas_refund_amount);
    tempvar gas_refund_amount_u256 = U256(new U256Struct(low, high));
    let sender_balance_after_refund = U256_add(
        sender_account.value.balance, gas_refund_amount_u256
    );
    set_account_balance{state=state}(sender, sender_balance_after_refund);

    // Transfer mining fees
    let coinbase_account = get_account{state=state}(block_env.value.coinbase);
    let (high, low) = split_felt(transaction_fee);
    tempvar transaction_fee_u256 = U256(new U256Struct(low, high));
    let coinbase_balance_after_mining_fee = U256_add(
        coinbase_account.value.balance, transaction_fee_u256
    );
    tempvar zero_u256 = U256(new U256Struct(0, 0));
    let coinbase_balance_after_mining_fee_is_zero = U256__eq__(
        coinbase_balance_after_mining_fee, zero_u256
    );
    if (coinbase_balance_after_mining_fee_is_zero.value == FALSE) {
        set_account_balance{state=state}(
            block_env.value.coinbase, coinbase_balance_after_mining_fee
        );
        tempvar range_check_ptr = range_check_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar state = state;
    } else {
        let is_empty = account_exists_and_is_empty{state=state}(block_env.value.coinbase);
        if (is_empty.value != FALSE) {
            destroy_account{state=state}(block_env.value.coinbase);
            tempvar range_check_ptr = range_check_ptr;
            tempvar poseidon_ptr = poseidon_ptr;
            tempvar state = state;
        } else {
            tempvar range_check_ptr = range_check_ptr;
            tempvar poseidon_ptr = poseidon_ptr;
            tempvar state = state;
        }
        tempvar range_check_ptr = range_check_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar state = state;
    }

    // The objects passed here are already squashed for efficiency - see `finalize_evm`.
    // We separate the deletion of storage from the deletion of accounts for efficiency.
    process_storage_deletions{state=state}(
        tx_output.value.accessed_storage_keys, tx_output.value.accounts_to_delete
    );
    process_account_deletions{state=state}(tx_output.value.accounts_to_delete);

    BlockEnvImpl.set_state{block_env=block_env}(state);

    let new_block_gas_used = block_output.value.block_gas_used.value + tx_gas_used_after_refund;
    let new_blob_gas_used = block_output.value.blob_gas_used.value + tx_blob_gas_used.value;

    tempvar tx_opt_error = OptionalEthereumException(cast(tx_output.value.error, felt*));
    let receipt = make_receipt(tx, tx_opt_error, Uint(new_block_gas_used), tx_output.value.logs);
    let receipt_key = encode_uint(index);
    // Append the new receipt key to the receipt keys
    let receipt_keys = block_output.value.receipt_keys;
    assert receipt_keys.value.data[receipt_keys.value.len] = receipt_key;

    tempvar new_receipt_keys = TupleBytes(
        new TupleBytesStruct(data=receipt_keys.value.data, len=receipt_keys.value.len + 1)
    );

    let receipts_trie = block_output.value.receipts_trie;
    trie_set_TrieBytesOptionalUnionBytesReceipt{trie=receipts_trie}(
        receipt_key, OptionalUnionBytesReceipt(receipt.value)
    );

    let block_logs = block_output.value.block_logs;
    _append_logs{logs=block_logs}(tx_output.value.logs);

    tempvar block_output = BlockOutput(
        new BlockOutputStruct(
            block_gas_used=Uint(new_block_gas_used),
            transactions_trie=transactions_trie,
            receipts_trie=receipts_trie,
            receipt_keys=new_receipt_keys,
            block_logs=block_logs,
            withdrawals_trie=block_output.value.withdrawals_trie,
            blob_gas_used=U64(new_blob_gas_used),
            requests=block_output.value.requests,
        ),
    );

    return ();
}

// @notice Deletes an account from the state.
// @dev This function does not delete the associated storage.
// @param accounts_to_delete - The set of accounts to delete. For performance reasons, this should be squashed before calling this function.
func process_account_deletions{range_check_ptr, state: State}(accounts_to_delete: SetAddress) {
    alloc_locals;

    let current = accounts_to_delete.value.dict_ptr_start;
    let end = accounts_to_delete.value.dict_ptr;
    if (current == end) {
        return ();
    }

    // Get current address and destroy account
    let address = [current].key;
    let none_account = OptionalAccount(cast(0, AccountStruct*));
    set_account(address, none_account);

    // Recursively process remaining accounts
    return process_account_deletions(
        SetAddress(
            new SetAddressStruct(
                dict_ptr_start=cast(current + DictAccess.SIZE, SetAddressDictAccess*),
                dict_ptr=cast(end, SetAddressDictAccess*),
            ),
        ),
    );
}
// @notice Sets to 0 the storage keys present in `accessed_storage_keys` for the accounts present in `accounts_to_delete`.
// @dev Accounts are only deleted in the case of a SELFDESTRUCT execution.
//      1. Because the account was created in the same transaction, we can assume that all storage keys to delete are present in `accessed_storage_keys`.
//      2. Iterate over these keys, identify whether it belongs to an account to delete, if so, set it to 0.
// @param accessed_storage_keys - The set of unique storage keys accessed in the transaction. For performance reasons, this should be squashed before calling this function.
// @param accounts_to_delete - The set of accounts to delete. For performance reasons, this should be squashed before calling this function.
func process_storage_deletions{range_check_ptr, poseidon_ptr: PoseidonBuiltin*, state: State}(
    accessed_storage_keys: SetTupleAddressBytes32, accounts_to_delete: SetAddress
) {
    alloc_locals;

    let current = accessed_storage_keys.value.dict_ptr_start;
    let dict_ptr_stop = accessed_storage_keys.value.dict_ptr;
    if (current == dict_ptr_stop) {
        // Squash the `accounts_to_delete` dict that was read
        let (
            squashed_accounts_to_delete_start, squashed_accounts_to_delete_end
        ) = default_dict_finalize(
            cast(accounts_to_delete.value.dict_ptr_start, DictAccess*),
            cast(accounts_to_delete.value.dict_ptr, DictAccess*),
            0,
        );
        return ();
    }

    let storage_key_hash = [current].key;
    let tuple_address_bytes32 = get_tuple_address_bytes32_preimage_for_key(
        storage_key_hash.value, cast(dict_ptr_stop, DictAccess*)
    );
    let is_account_to_delete = set_address_contains{set=accounts_to_delete}(
        tuple_address_bytes32.value.address
    );
    if (is_account_to_delete != 0) {
        let new_storage_value = state.value._storage_tries.value.default;
        set_storage(
            tuple_address_bytes32.value.address,
            tuple_address_bytes32.value.bytes32,
            new_storage_value,
        );
        tempvar state = state;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar state = state;
        tempvar range_check_ptr = range_check_ptr;
    }
    let state = State(cast([ap - 2], StateStruct*));
    let range_check_ptr = [ap - 1];

    tempvar next_iter = SetTupleAddressBytes32(
        new SetTupleAddressBytes32Struct(
            dict_ptr_start=cast(
                current + SetTupleAddressBytes32DictAccess.SIZE, SetTupleAddressBytes32DictAccess*
            ),
            dict_ptr=cast(dict_ptr_stop, SetTupleAddressBytes32DictAccess*),
        ),
    );

    return process_storage_deletions(next_iter, accounts_to_delete);
}

// Recursive function to process access list entries
func process_access_list{
    range_check_ptr,
    preaccessed_addresses: SetAddress,
    preaccessed_storage_keys: SetTupleAddressBytes32,
}(access_list_data: TupleAccess, len: felt, index: felt) {
    alloc_locals;

    // Base case: end of list
    if (index == len) {
        return ();
    }

    // Get current entry
    let entry = access_list_data.value.data[index];
    let address = entry.value.account;

    // Add address to preaccessed addresses
    let addresses_dict_ptr = cast(preaccessed_addresses.value.dict_ptr, DictAccess*);
    hashdict_write{dict_ptr=addresses_dict_ptr}(1, &address.value, 1);

    // Update preaccessed_addresses with addresses_dict_ptr
    tempvar preaccessed_addresses = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=cast(preaccessed_addresses.value.dict_ptr_start, SetAddressDictAccess*),
            dict_ptr=cast(addresses_dict_ptr, SetAddressDictAccess*),
        ),
    );

    // Process storage keys for this address
    process_storage_keys{preaccessed_storage_keys=preaccessed_storage_keys}(
        entry.value.slots, entry.value.slots.value.len, 0, address
    );

    // Process next entry
    return process_access_list(access_list_data, len, index + 1);
}

// Recursive function to process storage keys
func process_storage_keys{range_check_ptr, preaccessed_storage_keys: SetTupleAddressBytes32}(
    storage_keys_data: TupleBytes32, len: felt, index: felt, address: Address
) {
    alloc_locals;

    // Base case: end of list
    if (index == len) {
        return ();
    }

    // Get current key and add (address, key) to preaccessed storage keys
    let key = storage_keys_data.value.data[index];
    let storage_keys_dict_ptr = cast(preaccessed_storage_keys.value.dict_ptr, DictAccess*);

    // Create composite key from address and storage key
    let (keys: felt*) = alloc();
    assert keys[0] = address.value;
    assert keys[1] = key.value.low;
    assert keys[2] = key.value.high;

    hashdict_write{dict_ptr=storage_keys_dict_ptr}(3, keys, 1);

    // Update preaccessed_process_storage_keys with new dict_ptr
    tempvar preaccessed_storage_keys = SetTupleAddressBytes32(
        new SetTupleAddressBytes32Struct(
            dict_ptr_start=preaccessed_storage_keys.value.dict_ptr_start,
            dict_ptr=cast(storage_keys_dict_ptr, SetTupleAddressBytes32DictAccess*),
        ),
    );

    // Process next key
    return process_storage_keys(storage_keys_data, len, index + 1, address);
}

func check_transaction{
    range_check_ptr,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    block_env: BlockEnvironment,
}(block_output: BlockOutput, tx: Transaction) -> TupleAddressUintTupleVersionedHashU64 {
    alloc_locals;

    with_attr error_message("InvalidBlock") {
        let gas_available = block_env.value.block_gas_limit.value -
            block_output.value.block_gas_used.value;
        // Ensure no overflow
        assert [range_check_ptr] = gas_available;
        let range_check_ptr = range_check_ptr + 1;
        let gas = get_gas(tx);
        let tx_gas_within_bounds = is_le_felt(gas.value, gas_available);
        assert tx_gas_within_bounds = 1;
    }

    with_attr error_message("InvalidBlock") {
        let blob_gas_available = MAX_BLOB_GAS_PER_BLOCK - block_output.value.blob_gas_used.value;
        // Ensure no overflow
        assert [range_check_ptr] = blob_gas_available;
        let range_check_ptr = range_check_ptr + 1;

        let tx_blob_gas_used = calculate_total_blob_gas(tx);
        let tx_blob_gas_within_bounds = is_le_felt(tx_blob_gas_used.value, blob_gas_available);
        assert tx_blob_gas_within_bounds = 1;
    }

    let state = block_env.value.state;
    let sender_address = recover_sender(block_env.value.chain_id, tx);
    let sender_account = get_account{state=state}(sender_address);
    let transaction_type = get_transaction_type(tx);
    let is_not_blob_or_fee_or_set_code_transaction = (TransactionType.BLOB - transaction_type) * (
        TransactionType.FEE_MARKET - transaction_type
    ) * (TransactionType.SET_CODE - transaction_type);

    let base_fee_per_gas = block_env.value.base_fee_per_gas;
    // Case where transaction is blob or fee transaction
    if (is_not_blob_or_fee_or_set_code_transaction == FALSE) {
        let max_fee_per_gas = get_max_fee_per_gas(tx);
        let max_priority_fee_per_gas = get_max_priority_fee_per_gas(tx);
        let max_fee_per_gas_valid = is_le(base_fee_per_gas.value, max_fee_per_gas.value);
        let max_priority_fee_per_gas_valid = is_le(
            max_priority_fee_per_gas.value, max_fee_per_gas.value
        );
        let is_coherent_fee = max_fee_per_gas_valid * max_priority_fee_per_gas_valid;
        with_attr error_message("InvalidBlock") {
            assert is_coherent_fee = 1;
        }
        let priority_fee_per_gas = min(
            max_priority_fee_per_gas.value, max_fee_per_gas.value - base_fee_per_gas.value
        );
        let effective_gas_price_ = base_fee_per_gas.value + priority_fee_per_gas;
        assert [range_check_ptr] = effective_gas_price_;
        let range_check_ptr = range_check_ptr + 1;

        let max_gas_fee_ = gas.value * max_fee_per_gas.value;
        assert [range_check_ptr] = max_gas_fee_;
        let range_check_ptr = range_check_ptr + 1;

        tempvar effective_gas_price = Uint(effective_gas_price_);
        tempvar max_gas_fee = Uint(max_gas_fee_);
        tempvar range_check_ptr = range_check_ptr;
    } else {
        let gas_price = get_gas_price(tx);
        let gas_price_valid = is_le(base_fee_per_gas.value, gas_price.value);
        with_attr error_message("InvalidBlock") {
            assert gas_price_valid = 1;
        }

        let max_gas_fee_ = gas.value * gas_price.value;
        assert [range_check_ptr] = max_gas_fee_;
        let range_check_ptr = range_check_ptr + 1;

        tempvar effective_gas_price = gas_price;
        tempvar max_gas_fee = Uint(max_gas_fee_);
        tempvar range_check_ptr = range_check_ptr;
    }
    let range_check_ptr = [ap - 1];
    let effective_gas_price = effective_gas_price;
    let max_gas_fee = max_gas_fee;
    if (transaction_type == TransactionType.BLOB) {
        let len = tx.value.blob_transaction.value.blob_versioned_hashes.value.len;
        with_attr error_message("InvalidBlock") {
            assert_not_zero(len);
        }

        _check_versioned_hashes_version(
            tx.value.blob_transaction.value.blob_versioned_hashes.value.data, len
        );

        // Check blob gas price is valid
        let excess_blob_gas = block_env.value.excess_blob_gas;
        let blob_gas_price = calculate_blob_gas_price(excess_blob_gas);
        let max_fee_per_blob_gas_u256 = tx.value.blob_transaction.value.max_fee_per_blob_gas;
        let max_fee_per_blob_gas_uint = U256_to_Uint(max_fee_per_blob_gas_u256);
        let blob_gas_price_invalid = is_le(
            max_fee_per_blob_gas_uint.value, blob_gas_price.value - 1
        );
        with_attr error_message("InvalidBlock") {
            assert blob_gas_price_invalid = 0;
        }

        // Compute total blob gas
        let total_blob_gas = calculate_total_blob_gas(tx);

        // Increment max gas fee by the blob gas fee
        tempvar max_gas_fee = Uint(
            max_gas_fee.value + total_blob_gas.value * max_fee_per_blob_gas_uint.value
        );

        // Rebind values
        let blob_versioned_hashes = tx.value.blob_transaction.value.blob_versioned_hashes;
        tempvar blob_versioned_hashes_ptr = blob_versioned_hashes.value;
        tempvar range_check_ptr = range_check_ptr;
        tempvar max_gas_fee_value = max_gas_fee.value;
    } else {
        let (empty_data: felt*) = alloc();
        tempvar blob_versioned_hashes_ptr = new TupleVersionedHashStruct(
            data=cast(empty_data, VersionedHash*), len=0
        );
        tempvar range_check_ptr = range_check_ptr;
        tempvar max_gas_fee_value = max_gas_fee.value;
    }
    let blob_versioned_hashes = TupleVersionedHash(cast([ap - 3], TupleVersionedHashStruct*));
    let range_check_ptr = [ap - 2];
    let max_gas_fee = Uint([ap - 1]);

    let is_not_blob_or_set_code_transaction = (TransactionType.BLOB - transaction_type) * (
        TransactionType.SET_CODE - transaction_type
    );
    let to = get_to(tx);
    if (is_not_blob_or_set_code_transaction == FALSE and cast(to.value, felt) == 0) {
        raise('InvalidBlock');
    }

    let is_not_set_code_transaction = TransactionType.SET_CODE - transaction_type;
    let authorizations = get_authorizations_unchecked(tx);
    if (is_not_set_code_transaction == FALSE and authorizations.value.len == 0) {
        raise('InvalidBlock');
    }

    // Nonce check
    let sender_account_nonce = sender_account.value.nonce;
    let tx_nonce = get_nonce(tx);
    let tx_nonce_uint = U256_to_Uint(tx_nonce);
    with_attr error_message("InvalidBlock") {
        assert tx_nonce_uint.value = sender_account_nonce.value;
    }

    // Balance check
    let sender_account_balance = sender_account.value.balance;
    let tx_value = get_value(tx);
    let max_gas_fee_u256 = U256_from_Uint(max_gas_fee);
    let (tx_total_spent, carry) = U256_add_with_carry(tx_value, max_gas_fee_u256);
    with_attr error_message("InvalidBlock") {
        assert carry = 0;
    }
    let is_sender_balance_enough = U256_le(tx_total_spent, sender_account_balance);
    with_attr error_message("InvalidBlock") {
        assert is_sender_balance_enough.value = 1;
    }

    // Empty code check for EOA
    let sender_code = get_account_code{state=state}(sender_address, sender_account);
    let valid_delegation = is_valid_delegation(sender_code);
    let invalid_sender = sender_code.value.len * (1 - valid_delegation.value);
    with_attr error_message("InvalidSenderError") {
        assert invalid_sender = 0;
    }

    BlockEnvImpl.set_state{block_env=block_env}(state);

    tempvar res = TupleAddressUintTupleVersionedHashU64(
        new TupleAddressUintTupleVersionedHashU64Struct(
            address=sender_address,
            uint=effective_gas_price,
            tuple_versioned_hash=blob_versioned_hashes,
            u64=U64(tx_blob_gas_used.value),
        ),
    );
    return res;
}

func _check_versioned_hashes_version{range_check_ptr}(
    versioned_hashes: VersionedHash*, index: felt
) {
    // Check that each versioned hash has the correct version, i.e. that blob_versioned_hash[0:1] == VERSIONED_HASH_VERSION_KZG
    // for each versioned_hash in blob_versioned_hashes
    tempvar index = index;
    tempvar range_check_ptr = range_check_ptr;

    loop:
    let index = [ap - 2];
    let range_check_ptr = [ap - 1];
    let versioned_hash = versioned_hashes[index - 1];
    // Since versioned_hash are hash32 which are little endian, we need to check that the least significant byte is 0x01
    let (_, first_byte) = divmod(versioned_hash.value.low, 256);
    with_attr error_message("InvalidBlock") {
        assert first_byte = VERSIONED_HASH_VERSION_KZG;
    }
    tempvar index = index - 1;
    tempvar range_check_ptr = range_check_ptr;

    static_assert index == [ap - 2];
    static_assert range_check_ptr == [ap - 1];

    jmp loop if index != 0;

    static_assert index == [ap - 2];
    static_assert range_check_ptr == [ap - 1];

    return ();
}

func get_last_256_block_hashes{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: felt*}(
    chain: BlockChain
) -> ListHash32 {
    alloc_locals;

    // If no blocks, return empty array
    if (chain.value.blocks.value.len == 0) {
        let (empty_hashes_alloc: Hash32*) = alloc();
        tempvar empty_hashes = ListHash32(new ListHash32Struct(data=empty_hashes_alloc, len=0));
        return empty_hashes;
    }

    // Get last 255 blocks or all blocks if less than 255
    let is_le_255 = is_le(chain.value.blocks.value.len, 255);
    if (is_le_255 != FALSE) {
        tempvar start_idx = 0;
    } else {
        tempvar start_idx = chain.value.blocks.value.len - 255;
    }
    tempvar recent_blocks_len = chain.value.blocks.value.len - start_idx;

    // Allocate list for hashes
    let (hashes: Hash32*) = alloc();

    // Get parent hashes from recent blocks
    _get_parent_hashes{hashes=hashes}(
        chain.value.blocks.value.data + start_idx, recent_blocks_len, 0
    );

    // Add hash of most recent block
    let most_recent_block: Block* = chain.value.blocks.value.data + chain.value.blocks.value.len -
        1;
    let most_recent_hash = keccak256_header(most_recent_block.value.header);
    assert hashes[recent_blocks_len] = most_recent_hash;
    tempvar list_hash_32 = ListHash32(new ListHash32Struct(data=hashes, len=recent_blocks_len + 1));
    return list_hash_32;
}

// Helper function to get parent hashes using a loop
func _get_parent_hashes{hashes: Hash32*}(blocks: Block*, len: felt, idx: felt) {
    tempvar idx = idx;

    loop:
    let idx = [ap - 1];

    let end_loop = is_zero(idx - len);
    jmp end if end_loop != 0;

    // Get block at current index and store parent hash
    let block: Block* = blocks + idx;
    assert hashes[idx] = block.value.header.value.parent_hash;

    tempvar idx = idx + 1;

    jmp loop;

    end:
    return ();
}

// Helper to compute header hash
func keccak256_header{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: felt*}(
    header: Header
) -> Hash32 {
    // First RLP encode the header
    let encoded_header = encode_header(header);

    // Then compute keccak256 of the encoded bytes
    return keccak256(encoded_header);
}

func apply_body{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    block_env: BlockEnvironment,
}(transactions: TupleUnionBytesLegacyTransaction, withdrawals: TupleWithdrawal) -> BlockOutput {
    alloc_locals;

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let block_output = empty_block_output();

    let data_bytes = Bytes32_to_Bytes(block_env.value.parent_beacon_block_root);
    process_unchecked_system_transaction{block_env=block_env}(
        target_address=Address(BEACON_ROOTS_ADDRESS), data=data_bytes
    );

    let last_block_hash = block_env.value.block_hashes.value.data[
        block_env.value.block_hashes.value.len - 1
    ];
    let last_block_hash_bytes = Bytes32_to_Bytes(last_block_hash);
    process_unchecked_system_transaction{block_env=block_env}(
        target_address=Address(HISTORY_STORAGE_ADDRESS), data=last_block_hash_bytes
    );

    _apply_body_inner{block_env=block_env, block_output=block_output}(
        0, transactions.value.len, transactions
    );

    _process_withdrawals_inner{block_env=block_env, block_output=block_output}(0, withdrawals);

    process_general_purpose_requests{block_env=block_env, block_output=block_output}();

    // Finalize the state, getting unique keys for main and storage tries
    let state = block_env.value.state;
    finalize_state{state=state}();

    BlockEnvImpl.set_state{block_env=block_env}(state);

    return block_output;
}

func _apply_body_inner{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    block_env: BlockEnvironment,
    block_output: BlockOutput,
}(index: felt, len: felt, transactions: TupleUnionBytesLegacyTransaction) {
    alloc_locals;
    if (index == len) {
        return ();
    }

    let encoded_tx = transactions.value.data[index];
    process_transaction{block_env=block_env, block_output=block_output}(encoded_tx, Uint(index));

    return _apply_body_inner{block_env=block_env, block_output=block_output}(
        index + 1, len, transactions
    );
}

// @notice Process all the requests in the block.
// @param block_env The block scoped environment.
// @param block_output The block output for the current block.
func process_general_purpose_requests{
    range_check_ptr,
    poseidon_ptr: PoseidonBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    block_env: BlockEnvironment,
    block_output: BlockOutput,
}() {
    alloc_locals;

    tempvar DEPOSIT_REQUEST_TYPE_BYTES = Bytes(new BytesStruct(new DEPOSIT_REQUEST_TYPE, 1));

    let deposit_requests = parse_deposit_requests{block_output=block_output}();
    tempvar requests_from_execution = block_output.value.requests;
    if (deposit_requests.value.len != 0) {
        let (data_to_add) = alloc();
        assert [data_to_add] = DEPOSIT_REQUEST_TYPE;
        tempvar prefix = Bytes(new BytesStruct(data_to_add, 1));
        Bytes__extend__{self=prefix}(deposit_requests);
        assert requests_from_execution.value.data[requests_from_execution.value.len] = prefix;
        tempvar requests_from_execution = ListBytes(
            new ListBytesStruct(
                data=requests_from_execution.value.data, len=requests_from_execution.value.len + 1
            ),
        );
    } else {
        tempvar requests_from_execution = requests_from_execution;
    }
    let requests_from_execution = requests_from_execution;

    let (empty_bytes_data: Bytes*) = alloc();
    tempvar empty_bytes = Bytes(new BytesStruct(empty_bytes_data, 0));
    let system_withdrawal_tx_output = process_checked_system_transaction{block_env=block_env}(
        target_address=Bytes20(WITHDRAWAL_REQUEST_PREDEPLOY_ADDRESS), data=empty_bytes
    );
    if (system_withdrawal_tx_output.value.return_data.value.len != 0) {
        let (data_to_add) = alloc();
        assert [data_to_add] = WITHDRAWAL_REQUEST_TYPE;
        tempvar prefix = Bytes(new BytesStruct(data_to_add, 1));
        Bytes__extend__{self=prefix}(system_withdrawal_tx_output.value.return_data);
        assert requests_from_execution.value.data[requests_from_execution.value.len] = prefix;
        tempvar requests_from_execution = ListBytes(
            new ListBytesStruct(
                data=requests_from_execution.value.data, len=requests_from_execution.value.len + 1
            ),
        );
    } else {
        tempvar requests_from_execution = requests_from_execution;
    }
    let requests_from_execution = requests_from_execution;

    let system_consolidation_tx_output = process_checked_system_transaction{block_env=block_env}(
        target_address=Bytes20(CONSOLIDATION_REQUEST_PREDEPLOY_ADDRESS), data=empty_bytes
    );

    if (system_consolidation_tx_output.value.return_data.value.len != 0) {
        let (data_to_add) = alloc();
        assert [data_to_add] = CONSOLIDATION_REQUEST_TYPE;
        tempvar prefix = Bytes(new BytesStruct(data_to_add, 1));
        Bytes__extend__{self=prefix}(system_consolidation_tx_output.value.return_data);
        assert requests_from_execution.value.data[requests_from_execution.value.len] = prefix;
        tempvar requests_from_execution = ListBytes(
            new ListBytesStruct(
                data=requests_from_execution.value.data, len=requests_from_execution.value.len + 1
            ),
        );
    } else {
        tempvar requests_from_execution = requests_from_execution;
    }
    let requests_from_execution = requests_from_execution;

    tempvar block_output = BlockOutput(
        new BlockOutputStruct(
            block_gas_used=block_output.value.block_gas_used,
            transactions_trie=block_output.value.transactions_trie,
            receipts_trie=block_output.value.receipts_trie,
            receipt_keys=block_output.value.receipt_keys,
            block_logs=block_output.value.block_logs,
            withdrawals_trie=block_output.value.withdrawals_trie,
            blob_gas_used=block_output.value.blob_gas_used,
            requests=requests_from_execution,
        ),
    );

    return ();
}

func _process_withdrawals_inner{
    range_check_ptr,
    poseidon_ptr: PoseidonBuiltin*,
    block_env: BlockEnvironment,
    block_output: BlockOutput,
}(index: felt, withdrawals: TupleWithdrawal) {
    alloc_locals;
    if (index == withdrawals.value.len) {
        return ();
    }

    let withdrawal_trie = block_output.value.withdrawals_trie;

    let withdrawal = withdrawals.value.data[index];
    let index_bytes = encode_uint(Uint(index));
    let withdrawal_bytes = encode_withdrawal(withdrawal);
    tempvar value = OptionalUnionBytesWithdrawal(
        new UnionBytesWithdrawalEnum(
            bytes=withdrawal_bytes, withdrawal=Withdrawal(cast(0, WithdrawalStruct*))
        ),
    );
    trie_set_TrieBytesOptionalUnionBytesWithdrawal{trie=withdrawal_trie}(index_bytes, value);

    let state = block_env.value.state;
    process_withdrawal{state=state}(withdrawal);

    let cond = account_exists_and_is_empty{state=state}(withdrawal.value.address);
    if (cond.value != 0) {
        destroy_account{state=state}(withdrawal.value.address);
        tempvar range_check_ptr = range_check_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar state = state;
    } else {
        tempvar range_check_ptr = range_check_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar state = state;
    }
    BlockEnvImpl.set_state{block_env=block_env}(state);
    tempvar block_output = BlockOutput(
        new BlockOutputStruct(
            block_gas_used=block_output.value.block_gas_used,
            transactions_trie=block_output.value.transactions_trie,
            receipts_trie=block_output.value.receipts_trie,
            receipt_keys=block_output.value.receipt_keys,
            block_logs=block_output.value.block_logs,
            withdrawals_trie=withdrawal_trie,
            blob_gas_used=block_output.value.blob_gas_used,
            requests=block_output.value.requests,
        ),
    );

    return _process_withdrawals_inner{block_env=block_env, block_output=block_output}(
        index + 1, withdrawals
    );
}

func state_transition{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    chain: BlockChain,
    keccak_ptr: felt*,
}(block: Block) {
    alloc_locals;

    validate_header{keccak_ptr=keccak_ptr}(chain, block.value.header);

    with_attr error_message("InvalidBlock") {
        assert block.value.ommers.value.len = 0;
    }

    let state = chain.value.state;
    let block_hashes = get_last_256_block_hashes(chain);
    tempvar block_env = BlockEnvironment(
        new BlockEnvironmentStruct(
            chain_id=chain.value.chain_id,
            state=chain.value.state,
            block_gas_limit=block.value.header.value.gas_limit,
            block_hashes=block_hashes,
            coinbase=block.value.header.value.coinbase,
            number=block.value.header.value.number,
            base_fee_per_gas=block.value.header.value.base_fee_per_gas,
            time=block.value.header.value.timestamp,
            prev_randao=block.value.header.value.prev_randao,
            excess_blob_gas=block.value.header.value.excess_blob_gas,
            parent_beacon_block_root=block.value.header.value.parent_beacon_block_root,
        ),
    );

    let block_output = apply_body{block_env=block_env}(
        transactions=block.value.transactions, withdrawals=block.value.withdrawals
    );

    let withdrawals_trie = block_output.value.withdrawals_trie;
    let receipts_trie = block_output.value.receipts_trie;
    let transactions_trie = block_output.value.transactions_trie;

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

    let none_storage_roots = OptionalMappingAddressBytes32(cast(0, MappingAddressBytes32Struct*));

    // Compute all roots
    tempvar transaction_eth_trie = EthereumTries(
        new EthereumTriesEnum(
            account=TrieAddressOptionalAccount(cast(0, TrieAddressOptionalAccountStruct*)),
            storage=TrieBytes32U256(cast(0, TrieBytes32U256Struct*)),
            transaction=transactions_trie,
            receipt=TrieBytesOptionalUnionBytesReceipt(
                cast(0, TrieBytesOptionalUnionBytesReceiptStruct*)
            ),
            withdrawal=TrieBytesOptionalUnionBytesWithdrawal(
                cast(0, TrieBytesOptionalUnionBytesWithdrawalStruct*)
            ),
        ),
    );
    let none_storage_roots = OptionalMappingAddressBytes32(cast(0, MappingAddressBytes32Struct*));
    let transactions_root = root(transaction_eth_trie, none_storage_roots, 'keccak256');

    tempvar receipt_eth_trie = EthereumTries(
        new EthereumTriesEnum(
            account=TrieAddressOptionalAccount(cast(0, TrieAddressOptionalAccountStruct*)),
            storage=TrieBytes32U256(cast(0, TrieBytes32U256Struct*)),
            transaction=TrieBytesOptionalUnionBytesLegacyTransaction(
                cast(0, TrieBytesOptionalUnionBytesLegacyTransactionStruct*)
            ),
            receipt=receipts_trie,
            withdrawal=TrieBytesOptionalUnionBytesWithdrawal(
                cast(0, TrieBytesOptionalUnionBytesWithdrawalStruct*)
            ),
        ),
    );
    let receipts_root = root(receipt_eth_trie, none_storage_roots, 'keccak256');

    tempvar withdrawals_eth_trie = EthereumTries(
        new EthereumTriesEnum(
            account=TrieAddressOptionalAccount(cast(0, TrieAddressOptionalAccountStruct*)),
            storage=TrieBytes32U256(cast(0, TrieBytes32U256Struct*)),
            transaction=TrieBytesOptionalUnionBytesLegacyTransaction(
                cast(0, TrieBytesOptionalUnionBytesLegacyTransactionStruct*)
            ),
            receipt=TrieBytesOptionalUnionBytesReceipt(
                cast(0, TrieBytesOptionalUnionBytesReceiptStruct*)
            ),
            withdrawal=withdrawals_trie,
        ),
    );

    let withdrawals_root = root(withdrawals_eth_trie, none_storage_roots, 'keccak256');
    // Diff with EELS: we don't compute the full state root here - because we have a diff-based approach with the hinted sparse MPT
    let transactions_root = root(transaction_eth_trie, none_storage_roots, 'keccak256');
    let receipts_root = root(receipt_eth_trie, none_storage_roots, 'keccak256');
    let withdrawals_root = root(withdrawals_eth_trie, none_storage_roots, 'keccak256');
    let block_logs_bloom = logs_bloom(block_output.value.block_logs);

    let requests_hash = compute_requests_hash(block_output.value.requests);

    // Rebind state
    let state = block_env.value.state;
    tempvar chain = BlockChain(
        new BlockChainStruct(blocks=chain.value.blocks, state=state, chain_id=chain.value.chain_id)
    );

    with_attr error_message("InvalidBlock") {
        assert block_output.value.block_gas_used = block.value.header.value.gas_used;

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

        assert block_output.value.blob_gas_used.value = block.value.header.value.blob_gas_used.value;

        let req_hash_eq = Bytes32__eq__(
            requests_hash, block.value.header.value.requests_hash
        );
        assert req_hash_eq.value = 1;
    }

    _append_block{chain=chain}(block);

    return ();
}

func _append_block{range_check_ptr, chain: BlockChain}(block: Block) {
    assert chain.value.blocks.value.data[chain.value.blocks.value.len] = block;
    tempvar chain = BlockChain(
        new BlockChainStruct(
            blocks=ListBlock(
                new ListBlockStruct(
                    data=chain.value.blocks.value.data, len=chain.value.blocks.value.len + 1
                ),
            ),
            state=chain.value.state,
            chain_id=chain.value.chain_id,
        ),
    );
    return ();
}

// Moved out of blocks.cairo to avoid circular dependency
func encode_receipt{range_check_ptr}(tx: Transaction, receipt: Receipt) -> UnionBytesReceipt {
    alloc_locals;
    if (cast(tx.value.access_list_transaction.value, felt) != 0) {
        let (buffer: felt*) = alloc();
        assert [buffer] = 1;
        let encoding = encode_receipt_to_buffer(1, buffer + 1, receipt);
        tempvar res = UnionBytesReceipt(
            new UnionBytesReceiptEnum(bytes=encoding, receipt=Receipt(cast(0, ReceiptStruct*)))
        );
        return res;
    }

    if (cast(tx.value.fee_market_transaction.value, felt) != 0) {
        let (buffer: felt*) = alloc();
        assert [buffer] = 2;
        let encoding = encode_receipt_to_buffer(1, buffer + 1, receipt);
        tempvar res = UnionBytesReceipt(
            new UnionBytesReceiptEnum(bytes=encoding, receipt=Receipt(cast(0, ReceiptStruct*)))
        );
        return res;
    }

    if (cast(tx.value.blob_transaction.value, felt) != 0) {
        let (buffer: felt*) = alloc();
        assert [buffer] = 3;
        let encoding = encode_receipt_to_buffer(1, buffer + 1, receipt);
        tempvar res = UnionBytesReceipt(
            new UnionBytesReceiptEnum(bytes=encoding, receipt=Receipt(cast(0, ReceiptStruct*)))
        );
        return res;
    }

    if (cast(tx.value.set_code_transaction.value, felt) != 0) {
        let (buffer: felt*) = alloc();
        assert [buffer] = 4;
        let encoding = encode_receipt_to_buffer(1, buffer + 1, receipt);
        tempvar res = UnionBytesReceipt(
            new UnionBytesReceiptEnum(bytes=encoding, receipt=Receipt(cast(0, ReceiptStruct*)))
        );
        return res;
    }

    tempvar res = UnionBytesReceipt(
        new UnionBytesReceiptEnum(bytes=Bytes(cast(0, BytesStruct*)), receipt=receipt)
    );
    return res;
}
