from ethereum.base_types import U64, U256, Uint
from ethereum.trace import GasAndRefund
from ethereum.utils.numeric import ceil32, taylor_exponential
from ethereum.cancun.blocks import Header
from ethereum.cancun.transactions import BlobTransaction, Transaction
from ethereum.cancun.vm import Evm

const GAS_JUMPDEST = 1;
const GAS_BASE = 2;
const GAS_VERY_LOW = 3;
const GAS_STORAGE_SET = 20000;
const GAS_STORAGE_UPDATE = 5000;
const GAS_STORAGE_CLEAR_REFUND = 4800;
const GAS_LOW = 5;
const GAS_MID = 8;
const GAS_HIGH = 10;
const GAS_EXPONENTIATION = 10;
const GAS_EXPONENTIATION_PER_BYTE = 50;
const GAS_MEMORY = 3;
const GAS_KECCAK256 = 30;
const GAS_KECCAK256_WORD = 6;
const GAS_COPY = 3;
const GAS_BLOCK_HASH = 20;
const GAS_LOG = 375;
const GAS_LOG_DATA = 8;
const GAS_LOG_TOPIC = 375;
const GAS_CREATE = 32000;
const GAS_CODE_DEPOSIT = 200;
const GAS_ZERO = 0;
const GAS_NEW_ACCOUNT = 25000;
const GAS_CALL_VALUE = 9000;
const GAS_CALL_STIPEND = 2300;
const GAS_SELF_DESTRUCT = 5000;
const GAS_SELF_DESTRUCT_NEW_ACCOUNT = 25000;
const GAS_ECRECOVER = 3000;
const GAS_SHA256 = 60;
const GAS_SHA256_WORD = 12;
const GAS_RIPEMD160 = 600;
const GAS_RIPEMD160_WORD = 120;
const GAS_IDENTITY = 15;
const GAS_IDENTITY_WORD = 3;
const GAS_RETURN_DATA_COPY = 3;
const GAS_FAST_STEP = 5;
const GAS_BLAKE2_PER_ROUND = 1;
const GAS_COLD_SLOAD = 2100;
const GAS_COLD_ACCOUNT_ACCESS = 2600;
const GAS_WARM_ACCESS = 100;
const GAS_INIT_CODE_WORD_COST = 2;
const GAS_BLOBHASH_OPCODE = 3;
const GAS_POINT_EVALUATION = 50000;
const TARGET_BLOB_GAS_PER_BLOCK = 393216;
const GAS_PER_BLOB = 2 ** 17;
const MIN_BLOB_GASPRICE = 1;
const BLOB_GASPRICE_UPDATE_FRACTION = 3338477;

struct ExtendMemory {
    cost: Uint,
    expand_by: Uint,
}

struct MessageCallGas {
    cost: Uint,
    stipend: Uint,
}

func charge_gas(evm: Evm, amount: Uint) {
    // evm_trace(evm, GasAndRefund(amount))
    with_attr error_message("OutOfGasError") {
        assert [range_check_ptr] = evm.gas_left.value - amount.value;
    }
    evm.gas_left -= U256(amount);
    return ();
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

func calculate_gas_extend_memory(memory: bytearray, extensions: Tuple[U256, U256]) -> ExtendMemory {
    // Implementation:
    // size_to_extend = Uint(0)
    // to_be_paid = Uint(0)
    // current_size = Uint(len(memory))
    // for (start_position, size) in extensions:
    // if size == 0:
    // continue
    // before_size = ceil32(current_size)
    // after_size = ceil32(Uint(start_position) + Uint(size))
    // if after_size <= before_size:
    // continue
    // size_to_extend += after_size - before_size
    // already_paid = calculate_memory_gas_cost(before_size)
    // total_cost = calculate_memory_gas_cost(after_size)
    // to_be_paid += total_cost - already_paid
    // current_size = after_size
        // if size == 0:
        // continue
            // continue
        // before_size = ceil32(current_size)
        // after_size = ceil32(Uint(start_position) + Uint(size))
        // if after_size <= before_size:
        // continue
            // continue
        // size_to_extend += after_size - before_size
        // already_paid = calculate_memory_gas_cost(before_size)
        // total_cost = calculate_memory_gas_cost(after_size)
        // to_be_paid += total_cost - already_paid
        // current_size = after_size
    // return ExtendMemory(to_be_paid, size_to_extend)
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
        let message_call_gas = MessageCallGas(
            Uint(gas.value + extra_gas.value), Uint(gas.value + stipend)
        );
        return message_call_gas;
    }

    let max_allowed_gas = max_message_call_gas(
        Uint(gas_left.value - memory_cost.value - extra_gas.value)
    );
    let actual_gas = min(gas.value, max_allowed_gas.value);

    let message_call_gas = MessageCallGas(
        Uint(actual_gas + extra_gas.value), Uint(actual_gas + stipend)
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
