from starkware.cairo.common.math_cmp import is_le_felt, is_not_zero
from starkware.cairo.common.bool import FALSE, TRUE

from ethereum_types.bytes import Bytes, Bytes0
from ethereum_types.numeric import Uint, bool, U256, U256Struct
from ethereum.cancun.fork_types import Address
from ethereum.cancun.vm.gas import init_code_cost
from ethereum.cancun.transactions_types import (
    Transaction,
    To,
    ToStruct,
    TupleAccessListStruct,
    TX_BASE_COST,
    TX_DATA_COST_PER_NON_ZERO,
    TX_DATA_COST_PER_ZERO,
    TX_CREATE_COST,
    TX_ACCESS_LIST_ADDRESS_COST,
    TX_ACCESS_LIST_STORAGE_KEY_COST,
)
from ethereum.cancun.utils.constants import MAX_CODE_SIZE
from ethereum.utils.numeric import U256_le
from src.utils.array import count_not_zero

func calculate_intrinsic_cost{range_check_ptr}(tx: Transaction) -> Uint {
    alloc_locals;

    if (tx.value.legacy_transaction.value != 0) {
        let legacy_tx = tx.value.legacy_transaction;
        let cost_data_and_create = _calculate_data_and_create_cost(
            legacy_tx.value.data, legacy_tx.value.to
        );
        let cost = Uint(TX_BASE_COST + cost_data_and_create);
        return cost;
    }

    if (tx.value.access_list_transaction.value != 0) {
        let access_list_tx = tx.value.access_list_transaction;
        let cost_data_and_create = _calculate_data_and_create_cost(
            access_list_tx.value.data, access_list_tx.value.to
        );
        let cost_access_list = _calculate_access_list_cost(
            [access_list_tx.value.access_list.value]
        );
        let cost = Uint(TX_BASE_COST + cost_data_and_create + cost_access_list);
        return cost;
    }

    if (tx.value.fee_market_transaction.value != 0) {
        let fee_market_tx = tx.value.fee_market_transaction;
        let cost_data_and_create = _calculate_data_and_create_cost(
            fee_market_tx.value.data, fee_market_tx.value.to
        );
        let cost_access_list = _calculate_access_list_cost([fee_market_tx.value.access_list.value]);
        let cost = Uint(TX_BASE_COST + cost_data_and_create + cost_access_list);
        return cost;
    }

    if (tx.value.blob_transaction.value != 0) {
        let blob_tx = tx.value.blob_transaction;
        tempvar to = new ToStruct(bytes0=cast(0, Bytes0*), address=&blob_tx.value.to);
        let cost_data_and_create = _calculate_data_and_create_cost(blob_tx.value.data, To(to));
        let cost_access_list = _calculate_access_list_cost([blob_tx.value.access_list.value]);
        let cost = Uint(TX_BASE_COST + cost_data_and_create + cost_access_list);
        return cost;
    }

    with_attr error_message("InvalidTransaction") {
        assert 0 = 1;
    }

    let cost = Uint(0);
    return cost;
}

func _calculate_data_and_create_cost{range_check_ptr}(data: Bytes, to: To) -> felt {
    alloc_locals;
    let count = count_not_zero(data.value.len, data.value.data);
    let zeroes = data.value.len - count;
    let data_cost = zeroes * TX_DATA_COST_PER_ZERO + count * TX_DATA_COST_PER_NON_ZERO;

    if (cast(to.value.address, felt) != 0) {
        return data_cost;
    }

    let cost = init_code_cost(Uint(data.value.len));
    return data_cost + TX_CREATE_COST + cost.value;
}

func _calculate_access_list_cost{range_check_ptr}(access_list: TupleAccessListStruct) -> felt {
    alloc_locals;
    if (access_list.len == 0) {
        return 0;
    }

    let current_list = access_list.data[access_list.len - 1];
    let current_cost = TX_ACCESS_LIST_ADDRESS_COST + current_list.value.storage_keys.value.len *
        TX_ACCESS_LIST_STORAGE_KEY_COST;
    let access_list = TupleAccessListStruct(data=access_list.data, len=access_list.len - 1);
    let cum_gas_cost = _calculate_access_list_cost(access_list);
    let cost = current_cost + cum_gas_cost;
    return cost;
}

func validate_transaction{range_check_ptr}(tx: Transaction) -> bool {
    alloc_locals;

    local tx_gas: Uint;
    local tx_nonce: U256;
    local tx_data: Bytes;
    local tx_to_ptr: Address*;

    if (tx.value.legacy_transaction.value != 0) {
        assert tx_gas = tx.value.legacy_transaction.value.gas;
        assert tx_nonce = tx.value.legacy_transaction.value.nonce;
        assert tx_data = tx.value.legacy_transaction.value.data;
        assert tx_to_ptr = tx.value.legacy_transaction.value.to.value.address;
    }

    if (tx.value.access_list_transaction.value != 0) {
        assert tx_gas = tx.value.access_list_transaction.value.gas;
        assert tx_nonce = tx.value.access_list_transaction.value.nonce;
        assert tx_data = tx.value.access_list_transaction.value.data;
        assert tx_to_ptr = tx.value.access_list_transaction.value.to.value.address;
    }

    if (tx.value.fee_market_transaction.value != 0) {
        assert tx_gas = tx.value.fee_market_transaction.value.gas;
        assert tx_nonce = tx.value.fee_market_transaction.value.nonce;
        assert tx_data = tx.value.fee_market_transaction.value.data;
        assert tx_to_ptr = tx.value.fee_market_transaction.value.to.value.address;
    }

    if (tx.value.blob_transaction.value != 0) {
        assert tx_gas = tx.value.blob_transaction.value.gas;
        assert tx_nonce = tx.value.blob_transaction.value.nonce;
        assert tx_data = tx.value.blob_transaction.value.data;
        assert tx_to_ptr = &tx.value.blob_transaction.value.to;
    }

    let intrinsic_cost = calculate_intrinsic_cost(tx);
    let is_gas_insufficient = is_le_felt(tx_gas.value, intrinsic_cost.value - 1);
    if (is_gas_insufficient != FALSE) {
        tempvar res = bool(FALSE);
        return res;
    }

    let is_nonce_out_of_range = is_le_felt(2 ** 64 - 1, tx_nonce.value.low);
    if (is_nonce_out_of_range + tx_nonce.value.high != FALSE) {
        tempvar res = bool(FALSE);
        return res;
    }

    let is_data_not_zero = is_not_zero(tx_data.value.len);
    let is_data_too_large = is_le_felt(2 * MAX_CODE_SIZE, tx_data.value.len - 1);
    if (tx_to_ptr == 0 and is_data_not_zero != FALSE and is_data_too_large != FALSE) {
        tempvar res = bool(FALSE);
        return res;
    }

    tempvar res = bool(TRUE);
    return res;
}
