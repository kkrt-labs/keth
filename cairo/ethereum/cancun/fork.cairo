from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.math import assert_not_zero
from ethereum_types.numeric import Uint, bool
from ethereum_types.bytes import Bytes, Bytes0
from ethereum.utils.numeric import divmod
from ethereum.cancun.blocks import Header
from ethereum.cancun.transactions import (
    TX_ACCESS_LIST_ADDRESS_COST,
    TX_ACCESS_LIST_STORAGE_KEY_COST,
    TX_BASE_COST,
    TX_CREATE_COST,
    TX_DATA_COST_PER_NON_ZERO,
    TX_DATA_COST_PER_ZERO,
    Transaction,
    TupleAccessListStruct,
    To,
    ToStruct,
)
from ethereum.cancun.fork_types import Address
from ethereum.crypto.hash import keccak256
from ethereum.cancun.vm.gas import init_code_cost

from src.utils.array import count_not_zero

const ELASTICITY_MULTIPLIER = 2;
const BASE_FEE_MAX_CHANGE_DENOMINATOR = 8;
const GAS_LIMIT_ADJUSTMENT_FACTOR = 1024;
const GAS_LIMIT_MINIMUM = 5000;
const EMPTY_OMMER_HASH_LOW = 0xd312451b948a7413f0a142fd40d49347;
const EMPTY_OMMER_HASH_HIGH = 0x1dcc4de8dec75d7aab85b567b6ccd41a;

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
