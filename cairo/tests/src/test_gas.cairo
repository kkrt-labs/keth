%builtins range_check
from starkware.cairo.common.alloc import alloc

from src.gas import Gas
from starkware.cairo.common.uint256 import Uint256
from ethereum_types.numeric import U256
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc

func test__memory_cost{range_check_ptr}(words_len: felt) -> felt {
    let cost = Gas.memory_cost(words_len);

    return cost;
}

func test__memory_expansion_cost{range_check_ptr}(words_len: felt, max_offset: felt) -> felt {
    let memory_expansion = Gas.calculate_gas_extend_memory(words_len, max_offset);

    return memory_expansion.cost;
}

func test__max_memory_expansion_cost{range_check_ptr}(
    offset_1: U256, size_1: U256, offset_2: U256, size_2: U256, words_len: felt
) -> felt {
    alloc_locals;
    let memory_expansion = Gas.max_memory_expansion_cost(
        words_len, offset_1.value, size_1.value, offset_2.value, size_2.value
    );

    return memory_expansion.cost;
}

func test__memory_expansion_cost_saturated{range_check_ptr}(
    words_len: felt, offset: U256, size: U256
) -> felt {
    alloc_locals;
    let memory_expansion = Gas.memory_expansion_cost_saturated(
        words_len, [offset.value], [size.value]
    );
    return memory_expansion.cost;
}

func test__compute_message_call_gas{range_check_ptr}(gas_param: U256, gas_left: felt) -> felt {
    let gas = Gas.compute_message_call_gas([gas_param.value], gas_left);

    return gas;
}
