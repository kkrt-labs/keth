from ethereum.base_types import U256, Uint, U64
from ethereum.utils.numeric import is_zero, divmod, taylor_exponential, min, ceil32
from ethereum.cancun.blocks import Header
from ethereum.cancun.transactions import Transaction
from starkware.cairo.common.math_cmp import is_le, is_not_zero

const TARGET_BLOB_GAS_PER_BLOCK = 393216;
const GAS_INIT_CODE_WORD_COST = 2;
const GAS_MEMORY = 3;
const GAS_PER_BLOB = 2 ** 17;
const MIN_BLOB_GASPRICE = 1;
const BLOB_GASPRICE_UPDATE_FRACTION = 3338477;

struct MessageCallGasStruct {
    cost: Uint,
    stipend: Uint,
}

struct MessageCallGas {
    value: MessageCallGasStruct*,
}

func calculate_memory_gas_cost{range_check_ptr}(size_in_bytes: Uint) -> Uint {
    let size = ceil32(size_in_bytes);
    let (size_in_words, _) = divmod(size.value, 32);
    let linear_cost = size_in_words * GAS_MEMORY;
    let quadratic_cost = size_in_words * size_in_words;
    let (quadratic_cost, _) = divmod(quadratic_cost, 512);
    let total_gas_cost = Uint(linear_cost + quadratic_cost);
    return total_gas_cost;
}

func calculate_message_call_gas{range_check_ptr}(
    value: U256, gas: Uint, gas_left: Uint, memory_cost: Uint, extra_gas: Uint, call_stipend: Uint
) -> MessageCallGas {
    alloc_locals;
    let cond_low = is_zero(value.value.low);
    let cond_high = is_zero(value.value.high);
    let cond = cond_low * cond_high;
    let stipend = (1 - cond) * call_stipend.value;

    let cond = is_le(gas_left.value, extra_gas.value + memory_cost.value - 1);
    if (cond != 0) {
        tempvar message_call_gas = MessageCallGas(
            new MessageCallGasStruct(Uint(gas.value + extra_gas.value), Uint(gas.value + stipend))
        );
        return message_call_gas;
    }

    let max_allowed_gas = max_message_call_gas(
        Uint(gas_left.value - memory_cost.value - extra_gas.value)
    );
    let actual_gas = min(gas.value, max_allowed_gas.value);

    tempvar message_call_gas = MessageCallGas(
        new MessageCallGasStruct(Uint(actual_gas + extra_gas.value), Uint(actual_gas + stipend))
    );
    return message_call_gas;
}

func max_message_call_gas{range_check_ptr}(gas: Uint) -> Uint {
    let (quotient, _) = divmod(gas.value, 64);
    let max_allowed_gas = gas.value - quotient;
    let max_allowed = Uint(max_allowed_gas);
    return max_allowed;
}

func init_code_cost{range_check_ptr}(init_code_length: Uint) -> Uint {
    let length = ceil32(init_code_length);
    let (words, _) = divmod(length.value, 32);
    let cost = Uint(GAS_INIT_CODE_WORD_COST * words);
    return cost;
}

func calculate_excess_blob_gas{range_check_ptr}(parent_header: Header) -> U64 {
    let parent_blob_gas = parent_header.value.excess_blob_gas.value +
        parent_header.value.blob_gas_used.value;
    let cond = is_le(parent_blob_gas, TARGET_BLOB_GAS_PER_BLOCK - 1);
    if (cond == 1) {
        let excess_blob_gas = U64(0);
        return excess_blob_gas;
    }
    let excess_blob_gas = U64(parent_blob_gas - TARGET_BLOB_GAS_PER_BLOCK);
    return excess_blob_gas;
}

func calculate_total_blob_gas{range_check_ptr}(tx: Transaction) -> Uint {
    if (tx.value.blob_transaction.value != 0) {
        let total_blob_gas = Uint(
            GAS_PER_BLOB * tx.value.blob_transaction.value.blob_versioned_hashes.value.len
        );
        return total_blob_gas;
    }
    let total_blob_gas = Uint(0);
    return total_blob_gas;
}

func calculate_blob_gas_price{range_check_ptr}(excess_blob_gas: U64) -> Uint {
    let blob_gas_price = taylor_exponential(
        Uint(MIN_BLOB_GASPRICE), Uint(excess_blob_gas.value), Uint(BLOB_GASPRICE_UPDATE_FRACTION)
    );
    return blob_gas_price;
}

func calculate_data_fee{range_check_ptr}(excess_blob_gas: U64, tx: Transaction) -> Uint {
    alloc_locals;
    let total_blob_gas = calculate_total_blob_gas(tx);
    let blob_gas_price = calculate_blob_gas_price(excess_blob_gas);
    let data_fee = Uint(total_blob_gas.value * blob_gas_price.value);
    return data_fee;
}
