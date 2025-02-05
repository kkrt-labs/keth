from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    KeccakBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
)
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.default_dict import default_dict_new
from starkware.cairo.common.math import assert_not_zero, split_felt, assert_le_felt
from starkware.cairo.common.math_cmp import is_le, is_le_felt
from starkware.cairo.common.registers import get_fp_and_pc

from ethereum_rlp.rlp import Extended, ExtendedImpl, encode_receipt_to_buffer, encode_header
from ethereum_types.bytes import Bytes, Bytes0, BytesStruct, TupleBytes32
from ethereum_types.numeric import Uint, bool, U256, U256Struct, U64
from ethereum.cancun.blocks import (
    Header,
    Receipt,
    ReceiptStruct,
    TupleLog,
    Log,
    TupleLogStruct,
    Block,
    ListBlock,
    TupleHeader,
)
from ethereum.cancun.bloom import logs_bloom
from ethereum.cancun.fork_types import (
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
    TupleAddressUintTupleVersionedHash,
    TupleAddressUintTupleVersionedHashStruct,
    TupleVersionedHash,
    TupleVersionedHashStruct,
    VersionedHash,
)
from ethereum.cancun.state import (
    account_exists_and_is_empty,
    destroy_account,
    destroy_touched_empty_accounts,
    get_account,
    increment_nonce,
    set_account_balance,
    State,
)
from ethereum.cancun.transactions_types import (
    TX_ACCESS_LIST_ADDRESS_COST,
    TX_ACCESS_LIST_STORAGE_KEY_COST,
    TX_BASE_COST,
    TX_CREATE_COST,
    TX_DATA_COST_PER_NON_ZERO,
    TX_DATA_COST_PER_ZERO,
    Transaction,
    TransactionImpl,
    TransactionType,
    TupleAccessList,
    TupleAccessListStruct,
    To,
    ToStruct,
)
from ethereum.cancun.transactions import calculate_intrinsic_cost, validate_transaction
from ethereum.cancun.utils.message import prepare_message
from ethereum.cancun.vm import Environment, EnvImpl
from ethereum.cancun.vm.exceptions import EthereumException, InvalidBlock
from ethereum.cancun.vm.gas import (
    calculate_data_fee,
    init_code_cost,
    calculate_total_blob_gas,
    calculate_blob_gas_price,
)
from ethereum.cancun.vm.interpreter import process_message_call, MessageCallOutput
from ethereum.crypto.hash import keccak256, Hash32
from ethereum.exceptions import OptionalEthereumException
from ethereum.utils.numeric import (
    divmod,
    min,
    U256_add,
    U256_sub,
    U256__eq__,
    U256_from_felt,
    U256_le,
    U256_to_Uint,
    U256_add_with_carry,
)
from ethereum.cancun.transactions import recover_sender
from cairo_core.comparison import is_zero

from src.utils.array import count_not_zero
from src.utils.dict import hashdict_write

const ELASTICITY_MULTIPLIER = 2;
const BASE_FEE_MAX_CHANGE_DENOMINATOR = 8;
const GAS_LIMIT_ADJUSTMENT_FACTOR = 1024;
const GAS_LIMIT_MINIMUM = 5000;
const EMPTY_OMMER_HASH_LOW = 0xd312451b948a7413f0a142fd40d49347;
const EMPTY_OMMER_HASH_HIGH = 0x1dcc4de8dec75d7aab85b567b6ccd41a;
const VERSIONED_HASH_VERSION_KZG = 0x01;

struct BlockChainStruct {
    blocks: ListBlock,
    state: State,
    chain_id: U64,
}

struct BlockChain {
    value: BlockChainStruct*,
}

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

func validate_header{range_check_ptr}(header: Header, parent_header: Header) {
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
        assert [range_check_ptr] = header.value.timestamp.value -
            parent_header.value.timestamp.value - 1;
        assert [range_check_ptr + 1] = header.value.number.value -
            parent_header.value.number.value - 1;
        assert [range_check_ptr + 2] = 32 - header.value.extra_data.value.len;
        let range_check_ptr = range_check_ptr + 3;
        assert header.value.difficulty.value = 0;
        assert header.value.nonce.value = 0;
        assert header.value.ommers_hash.value.low = EMPTY_OMMER_HASH_LOW;
        assert header.value.ommers_hash.value.high = EMPTY_OMMER_HASH_HIGH;
    }

    // TODO: Implement block header hash check
    // let block_parent_hash = keccak256(rlp.encode(parent_header));
    // assert header.value.parent_hash = block_parent_hash;
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

struct UnionBytesReceiptEnum {
    bytes: Bytes,
    receipt: Receipt,
}

struct UnionBytesReceipt {
    value: UnionBytesReceiptEnum*,
}

func make_receipt{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}(
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

    tempvar res = UnionBytesReceipt(
        new UnionBytesReceiptEnum(bytes=Bytes(cast(0, BytesStruct*)), receipt=receipt)
    );
    return res;
}

func process_transaction{
    range_check_ptr,
    poseidon_ptr: PoseidonBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    env: Environment,
}(tx: Transaction) -> (Uint, TupleLog, OptionalEthereumException) {
    alloc_locals;

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    // Validate transaction
    let is_valid = validate_transaction(tx);
    with_attr error_message("InvalidBlock") {
        assert is_valid.value = TRUE;
    }

    // Get sender account
    let state = env.value.state;
    let sender = env.value.origin;
    let sender_account = get_account{state=state}(sender);

    // Get relevant transaction data
    local tx_gas: Uint;
    local tx_data: Bytes;
    local tx_to: To;
    local tx_value: U256;
    local blob_gas_fee: Uint;
    local access_lists: TupleAccessList;
    if (tx.value.blob_transaction.value != 0) {
        assert tx_gas = tx.value.blob_transaction.value.gas;
        assert tx_data = tx.value.blob_transaction.value.data;
        assert tx_to = To(
            new ToStruct(bytes0=cast(0, Bytes0*), address=&tx.value.blob_transaction.value.to)
        );
        assert tx_value = tx.value.blob_transaction.value.value;
        let blob_gas_fee_res = calculate_data_fee(env.value.excess_blob_gas, tx);
        assert blob_gas_fee = blob_gas_fee_res;
        assert access_lists = TupleAccessList(cast(0, TupleAccessListStruct*));
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
        assert access_lists = TupleAccessList(cast(0, TupleAccessListStruct*));
    }

    if (tx.value.access_list_transaction.value != 0) {
        assert tx_gas = tx.value.access_list_transaction.value.gas;
        assert tx_data = tx.value.access_list_transaction.value.data;
        assert tx_to = tx.value.access_list_transaction.value.to;
        assert tx_value = tx.value.access_list_transaction.value.value;
        assert blob_gas_fee = Uint(0);
        assert access_lists = tx.value.access_list_transaction.value.access_list;
    }

    let effective_gas_fee = tx_gas.value * env.value.gas_price.value;

    // Calculate available gas, does not overflow as it was checked in validate_transaction before.
    let intrinsic_cost = calculate_intrinsic_cost(tx);
    let gas = tx_gas.value - intrinsic_cost.value;

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
    EnvImpl.set_state{env=env}(state);

    // Create preaccessed addresses and write coinbase
    let (preaccessed_addresses_ptr) = default_dict_new(0);
    tempvar preaccessed_addresses_ptr_start = preaccessed_addresses_ptr;
    let address = env.value.coinbase;
    hashdict_write{dict_ptr=preaccessed_addresses_ptr}(1, &address.value, 1);
    tempvar preaccessed_addresses = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=cast(preaccessed_addresses_ptr_start, SetAddressDictAccess*),
            dict_ptr=cast(preaccessed_addresses_ptr, SetAddressDictAccess*),
        ),
    );
    // Create preaccessed storage keys
    let (preaccessed_storage_keys_ptr) = default_dict_new(0);
    tempvar preaccessed_storage_keys = SetTupleAddressBytes32(
        new SetTupleAddressBytes32Struct(
            dict_ptr_start=cast(preaccessed_storage_keys_ptr, SetTupleAddressBytes32DictAccess*),
            dict_ptr=cast(preaccessed_storage_keys_ptr, SetTupleAddressBytes32DictAccess*),
        ),
    );

    if (tx.value.legacy_transaction.value == 0) {
        process_access_list{
            preaccessed_addresses=preaccessed_addresses,
            preaccessed_storage_keys=preaccessed_storage_keys,
        }(access_lists, access_lists.value.len, 0);
        tempvar keccak_ptr = keccak_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar preaccessed_addresses = preaccessed_addresses;
        tempvar preaccessed_storage_keys = preaccessed_storage_keys;
    } else {
        tempvar keccak_ptr = keccak_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar preaccessed_addresses = preaccessed_addresses;
        tempvar preaccessed_storage_keys = preaccessed_storage_keys;
    }

    let keccak_ptr = cast([ap - 5], KeccakBuiltin*);
    let bitwise_ptr = cast([ap - 4], BitwiseBuiltin*);
    let poseidon_ptr = cast([ap - 3], PoseidonBuiltin*);
    let preaccessed_addresses = SetAddress(cast([ap - 2], SetAddressStruct*));
    let preaccessed_storage_keys = SetTupleAddressBytes32(
        cast([ap - 1], SetTupleAddressBytes32Struct*)
    );

    tempvar code_address = OptionalAddress(cast(0, Address*));
    let message = prepare_message{env=env}(
        sender,
        tx_to,
        tx_value,
        tx_data,
        Uint(gas),
        code_address,
        bool(1),
        bool(0),
        preaccessed_addresses,
        preaccessed_storage_keys,
    );
    let output = process_message_call{env=env}(message);
    // Rebind env's state modified in `process_message_call`
    let state = env.value.state;

    // Calculate gas refund
    with_attr error_message("OverflowError") {
        assert output.value.refund_counter.value.high = 0;
        assert_le_felt(env.value.base_fee_per_gas.value, env.value.gas_price.value);
    }
    let gas_used = tx_gas.value - output.value.gas_left.value;
    let (gas_refund_div_5, _) = divmod(gas_used, 5);
    let gas_refund = min(gas_refund_div_5, output.value.refund_counter.value.low);
    let gas_refund_amount = (output.value.gas_left.value + gas_refund) * env.value.gas_price.value;

    // Calculate priority fee
    let priority_fee_per_gas = env.value.gas_price.value - env.value.base_fee_per_gas.value;
    let transaction_fee = (tx_gas.value - output.value.gas_left.value - gas_refund) *
        priority_fee_per_gas;

    // Calculate total gas used
    let total_gas_used = gas_used - gas_refund;

    // Refund gas to sender
    let sender_account = get_account{state=state}(sender);
    let (high, low) = split_felt(gas_refund_amount);
    tempvar gas_refund_amount_u256 = U256(new U256Struct(low, high));
    let sender_balance_after_refund = U256_add(
        sender_account.value.balance, gas_refund_amount_u256
    );
    set_account_balance{state=state}(sender, sender_balance_after_refund);

    // Transfer mining fees
    let coinbase_account = get_account{state=state}(env.value.coinbase);
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
        set_account_balance{state=state}(env.value.coinbase, coinbase_balance_after_mining_fee);
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar state = state;
    } else {
        let is_empty = account_exists_and_is_empty{state=state}(env.value.coinbase);
        if (is_empty.value != FALSE) {
            destroy_account{state=state}(env.value.coinbase);
            tempvar poseidon_ptr = poseidon_ptr;
            tempvar state = state;
        } else {
            tempvar poseidon_ptr = poseidon_ptr;
            tempvar state = state;
        }
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar state = state;
    }

    process_account_deletions{state=state}(output.value.accounts_to_delete);
    destroy_touched_empty_accounts{state=state}(output.value.touched_accounts);
    EnvImpl.set_state{env=env}(state);

    tempvar optional_err = OptionalEthereumException(output.value.error);
    return (Uint(total_gas_used), output.value.logs, optional_err);
}

func process_account_deletions{poseidon_ptr: PoseidonBuiltin*, state: State}(
    accounts_to_delete: SetAddress
) {
    alloc_locals;

    let current = accounts_to_delete.value.dict_ptr_start;
    let end = accounts_to_delete.value.dict_ptr;
    if (current == end) {
        return ();
    }

    // Get current address and destroy account
    let address = [current].key;
    destroy_account(address);

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

// Recursive function to process access list entries
func process_access_list{
    poseidon_ptr: PoseidonBuiltin*,
    preaccessed_addresses: SetAddress,
    preaccessed_storage_keys: SetTupleAddressBytes32,
}(access_list_data: TupleAccessList, len: felt, index: felt) {
    alloc_locals;

    // Base case: end of list
    if (index == len) {
        return ();
    }

    // Get current entry
    let entry = access_list_data.value.data[index];
    let address = entry.value.address;

    // Add address to preaccessed addresses
    let addresses_dict_ptr = cast(preaccessed_addresses.value.dict_ptr, DictAccess*);
    hashdict_write{poseidon_ptr=poseidon_ptr, dict_ptr=addresses_dict_ptr}(1, &address.value, 1);

    // Update preaccessed_addresses with addresses_dict_ptr
    tempvar preaccessed_addresses = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=cast(preaccessed_addresses.value.dict_ptr_start, SetAddressDictAccess*),
            dict_ptr=cast(addresses_dict_ptr, SetAddressDictAccess*),
        ),
    );

    // Process storage keys for this address
    process_storage_keys{
        poseidon_ptr=poseidon_ptr, preaccessed_storage_keys=preaccessed_storage_keys
    }(entry.value.storage_keys, entry.value.storage_keys.value.len, 0, address);

    // Process next entry
    return process_access_list(access_list_data, len, index + 1);
}

// Recursive function to process storage keys
func process_storage_keys{
    poseidon_ptr: PoseidonBuiltin*, preaccessed_storage_keys: SetTupleAddressBytes32
}(storage_keys_data: TupleBytes32, len: felt, index: felt, address: Address) {
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

    hashdict_write{poseidon_ptr=poseidon_ptr, dict_ptr=storage_keys_dict_ptr}(3, keys, 1);

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
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    state: State,
}(
    tx: Transaction,
    gas_available: Uint,
    chain_id: U64,
    base_fee_per_gas: Uint,
    excess_blob_gas: U64,
) -> TupleAddressUintTupleVersionedHash {
    alloc_locals;
    let gas = TransactionImpl.get_gas(tx);
    let tx_gas_within_bounds = is_le(gas.value, gas_available.value);
    with_attr error_message("InvalidBlock") {
        assert tx_gas_within_bounds = 1;
    }
    let sender_address = recover_sender(chain_id, tx);
    let sender_account = get_account{state=state}(sender_address);
    let transaction_type = TransactionImpl.get_transaction_type(tx);
    let is_not_blob_or_fee_transaction = (TransactionType.BLOB - transaction_type) * (
        TransactionType.FEE_MARKET - transaction_type
    );
    // Case where transaction is blob or fee transaction
    if (is_not_blob_or_fee_transaction == FALSE) {
        let max_fee_per_gas = TransactionImpl.get_max_fee_per_gas(tx);
        let max_priority_fee_per_gas = TransactionImpl.get_max_priority_fee_per_gas(tx);
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
        tempvar effective_gas_price = Uint(base_fee_per_gas.value + priority_fee_per_gas);
        tempvar max_gas_fee = Uint(gas.value * max_fee_per_gas.value);
    } else {
        let gas_price = TransactionImpl.get_gas_price(tx);
        let gas_price_valid = is_le(base_fee_per_gas.value, gas_price.value);
        with_attr error_message("InvalidBlock") {
            assert gas_price_valid = 1;
        }
        tempvar effective_gas_price = gas_price;
        tempvar max_gas_fee = Uint(gas.value * gas_price.value);
    }
    let effective_gas_price = effective_gas_price;
    let max_gas_fee = max_gas_fee;
    if (transaction_type == TransactionType.BLOB) {
        let len = tx.value.blob_transaction.value.blob_versioned_hashes.value.len;
        with_attr error_message("InvalidBlock") {
            assert_not_zero(len);
        }

        _check_versioned_hashes_version{range_check_ptr=range_check_ptr}(
            tx.value.blob_transaction.value.blob_versioned_hashes.value.data, len
        );

        // Check blob gas price is valid
        let blob_gas_price = calculate_blob_gas_price(excess_blob_gas);
        let max_fee_per_blob_gas_u256 = tx.value.blob_transaction.value.max_fee_per_blob_gas;
        let max_fee_per_blob_gas_uint = U256_to_Uint(max_fee_per_blob_gas_u256);
        let blob_gas_price_valid = is_le(max_fee_per_blob_gas_uint.value, blob_gas_price.value - 1);
        with_attr error_message("InvalidBlock") {
            assert blob_gas_price_valid = 1;
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

    // Nonce check
    let sender_account_nonce = sender_account.value.nonce;
    let tx_nonce = TransactionImpl.get_nonce(tx);
    let tx_nonce_uint = U256_to_Uint(tx_nonce);
    with_attr error_message("InvalidBlock") {
        assert tx_nonce_uint.value = sender_account_nonce.value;
    }

    // Balance check
    let sender_account_balance = sender_account.value.balance;
    let tx_value = TransactionImpl.get_value(tx);
    let max_gas_fee_u256 = U256_from_felt(max_gas_fee.value);
    let (tx_total_spent, carry) = U256_add_with_carry(tx_value, max_gas_fee_u256);
    with_attr error_message("InvalidBlock") {
        assert carry = 0;
    }
    let is_sender_balance_enough = U256_le(tx_total_spent, sender_account_balance);
    with_attr error_message("InvalidBlock") {
        assert is_sender_balance_enough.value = 1;
    }

    // Empty code check for EOA
    let sender_code = sender_account.value.code;
    with_attr error_message("InvalidBlock") {
        assert sender_code.value.len = 0;
    }

    tempvar res = TupleAddressUintTupleVersionedHash(
        new TupleAddressUintTupleVersionedHashStruct(
            address=sender_address,
            uint=effective_gas_price,
            tuple_versioned_hash=blob_versioned_hashes,
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
    let (first_byte, _) = divmod(versioned_hash.value.low, 2 ** 120);
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

func get_last_256_block_hashes{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*
}(chain: BlockChain) -> ListHash32 {
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
func keccak256_header{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}(
    header: Header
) -> Hash32 {
    // First RLP encode the header
    let encoded_header = encode_header(header);

    // Then compute keccak256 of the encoded bytes
    return keccak256(encoded_header);
}
