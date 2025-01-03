from ethereum_types.numeric import U256, Uint, U64, U256Struct
from ethereum.utils.numeric import is_zero, divmod, taylor_exponential, min, ceil32
from ethereum_types.bytes import BytesStruct
from ethereum.cancun.blocks import Header
from ethereum.cancun.transactions import Transaction
from ethereum_types.others import ListTupleU256U256, TupleU256U256
from ethereum.cancun.vm import Evm, EvmStruct, EvmImpl
from ethereum.cancun.vm.exceptions import ExceptionalHalt, OutOfGasError
from ethereum.cancun.vm.memory import Memory

from starkware.cairo.common.math_cmp import is_le, is_not_zero, RC_BOUND
from starkware.cairo.common.math import assert_le_felt
from starkware.cairo.common.uint256 import ALL_ONES, uint256_eq, uint256_le

from src.utils.uint256 import uint256_add
from src.constants import Constants

namespace GasConstants {
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
}

struct ExtendMemory {
    value: ExtendMemoryStruct*,
}

struct ExtendMemoryStruct {
    cost: Uint,
    expand_by: Uint,
}

struct MessageCallGasStruct {
    cost: Uint,
    stipend: Uint,
}

struct MessageCallGas {
    value: MessageCallGasStruct*,
}

// @notice Subtracts `amount` from `evm.gas_left`.
// @dev The gas left is decremented by the given amount.
// Use code adapted from is_nn.
// Assumption: gas_left < 2 ** 128
// @param evm The pointer to the current execution context.
// @param amount The amount of gas the current operation requires.
// @return EVM The pointer to the updated execution context.
func charge_gas{range_check_ptr, evm: Evm}(amount: Uint) -> ExceptionalHalt* {
    // This is equivalent to is_nn(evm.value.gas_left - amount)
    with_attr error_message("charge_gas: gas_left > 2**128") {
        assert [range_check_ptr] = evm.value.gas_left.value;
        tempvar range_check_ptr = range_check_ptr + 1;
    }

    tempvar a = evm.value.gas_left.value - amount.value;  // a is necessary for using the whitelisted hint
    %{ memory[ap] = 0 if 0 <= (ids.a % PRIME) < range_check_builtin.bound else 1 %}
    jmp out_of_range if [ap] != 0, ap++;
    [range_check_ptr] = a;
    ap += 20;
    tempvar range_check_ptr = range_check_ptr + 1;
    jmp enough_gas;

    out_of_range:
    %{ memory[ap] = 0 if 0 <= ((-ids.a - 1) % PRIME) < range_check_builtin.bound else 1 %}
    jmp need_felt_comparison if [ap] != 0, ap++;
    assert [range_check_ptr] = (-a) - 1;
    ap += 17;
    tempvar range_check_ptr = range_check_ptr + 1;
    jmp not_enough_gas;

    need_felt_comparison:
    assert_le_felt(RC_BOUND, a);
    jmp not_enough_gas;

    enough_gas:
    let range_check_ptr = [ap - 1];
    let evm_struct = cast([fp - 4], EvmStruct*);
    tempvar evm = Evm(evm_struct);
    EvmImpl.set_gas_left(Uint(a));
    tempvar ok = cast(0, ExceptionalHalt*);
    return ok;

    not_enough_gas:
    let range_check_ptr = [ap - 1];
    let evm_struct = cast([fp - 4], EvmStruct*);
    tempvar evm = Evm(evm_struct);
    tempvar err = new ExceptionalHalt(OutOfGasError);
    return err;
}

const MAX_MEMORY_COST = 0x20000000000017f7fffffffffffd;
const MAX_MEMORY_SIZE = 2 ** 64 - 32;

// @dev: assumption: not called with size_in_bytes >= 2**64
// only used by calculate_gas_extend_memory which saturates at 2**64-32
// @dev: max output value given this saturation is MAX_MEMORY_COST
func calculate_memory_gas_cost{range_check_ptr}(size_in_bytes: Uint) -> Uint {
    let size = ceil32(size_in_bytes);
    let (size_in_words, _) = divmod(size.value, 32);
    let linear_cost = size_in_words * GasConstants.GAS_MEMORY;
    let quadratic_cost = size_in_words * size_in_words;
    let (quadratic_cost, _) = divmod(quadratic_cost, 512);
    let total_gas_cost = Uint(linear_cost + quadratic_cost);
    return total_gas_cost;
}

// @dev: saturates extensions at (MAX_MEMORY_SIZE, MAX_MEMORY_COST)
func calculate_gas_extend_memory{range_check_ptr}(
    memory: Memory, extensions: ListTupleU256U256
) -> ExtendMemory {
    alloc_locals;
    let max_memory_offset = _max_offset(Uint(memory.value.len), extensions, 0);
    let size_to_extend = Uint(max_memory_offset.value - memory.value.len);
    let already_paid = calculate_memory_gas_cost(Uint(memory.value.len));
    let total_cost = calculate_memory_gas_cost(Uint(max_memory_offset.value));
    let to_be_paid = Uint(total_cost.value - already_paid.value);
    tempvar res = ExtendMemory(new ExtendMemoryStruct(to_be_paid, size_to_extend));
    return res;
}

// @dev saturates at 2**64 (Uint size)
func _max_offset{range_check_ptr}(
    before_size: Uint, extensions: ListTupleU256U256, idx: felt
) -> Uint {
    alloc_locals;
    let extensions_len = extensions.value.len - idx;
    if (extensions_len == 0) {
        return before_size;
    }

    let offset = extensions.value.data[idx].value.val_1;
    let size = extensions.value.data[idx].value.val_2;
    let (is_zero) = uint256_eq([size.value], U256Struct(0, 0));
    if (is_zero != 0) {
        return _max_offset(before_size, extensions, idx + 1);
    }

    let (max_offset, carry) = uint256_add([offset.value], [size.value]);
    if (carry != 0) {
        tempvar res = Uint(MAX_MEMORY_SIZE);
        return _max_offset(res, extensions, idx + 1);
    }
    let (is_saturated) = uint256_le(U256Struct(MAX_MEMORY_SIZE + 1, 0), max_offset);
    if (is_saturated != 0) {
        tempvar res = Uint(MAX_MEMORY_SIZE);
        return _max_offset(res, extensions, idx + 1);
    }

    let after_size = ceil32(Uint(max_offset.low));
    let is_smaller = is_le(after_size.value, before_size.value);
    if (is_smaller == 1) {
        return _max_offset(before_size, extensions, idx + 1);
    }

    return _max_offset(after_size, extensions, idx + 1);
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
    let cost = Uint(GasConstants.GAS_INIT_CODE_WORD_COST * words);
    return cost;
}

func calculate_excess_blob_gas{range_check_ptr}(parent_header: Header) -> U64 {
    let parent_blob_gas = parent_header.value.excess_blob_gas.value +
        parent_header.value.blob_gas_used.value;
    let cond = is_le(parent_blob_gas, GasConstants.TARGET_BLOB_GAS_PER_BLOCK - 1);
    if (cond == 1) {
        let excess_blob_gas = U64(0);
        return excess_blob_gas;
    }
    let excess_blob_gas = U64(parent_blob_gas - GasConstants.TARGET_BLOB_GAS_PER_BLOCK);
    return excess_blob_gas;
}

func calculate_total_blob_gas{range_check_ptr}(tx: Transaction) -> Uint {
    if (tx.value.blob_transaction.value != 0) {
        let total_blob_gas = Uint(
            GasConstants.GAS_PER_BLOB *
            tx.value.blob_transaction.value.blob_versioned_hashes.value.len,
        );
        return total_blob_gas;
    }
    let total_blob_gas = Uint(0);
    return total_blob_gas;
}

func calculate_blob_gas_price{range_check_ptr}(excess_blob_gas: U64) -> Uint {
    let blob_gas_price = taylor_exponential(
        Uint(GasConstants.MIN_BLOB_GASPRICE),
        Uint(excess_blob_gas.value),
        Uint(GasConstants.BLOB_GASPRICE_UPDATE_FRACTION),
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
