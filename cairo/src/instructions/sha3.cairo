from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE
from starkware.cairo.common.math import split_felt
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.math_cmp import is_not_zero

from src.evm import EVM
from src.interfaces.interfaces import ICairo1Helpers
from src.gas import Gas
from src.memory import Memory
from src.model import model
from src.stack import Stack
from src.utils.bytes import keccak
from src.utils.maths import unsigned_div_rem

namespace Sha3 {
    func exec_sha3{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        stack: model.Stack*,
        memory: model.Memory*,
        state: model.State*,
    }(evm: model.EVM*) -> model.EVM* {
        alloc_locals;

        let (popped) = Stack.pop_n(2);
        let offset = popped[0];
        let size = popped[1];

        // GAS
        let memory_expansion = Gas.memory_expansion_cost_saturated(memory.words_len, offset, size);
        if (memory_expansion.cost == Gas.MEMORY_COST_U32) {
            let evm = EVM.out_of_gas(evm, memory_expansion.cost);
            return evm;
        }
        let (words, _) = unsigned_div_rem(size.low + 31, 32);
        let words_gas_cost_low = Gas.KECCAK256_WORD * words;
        tempvar words_gas_cost_high = is_not_zero(size.high) * 2 ** 128;
        let evm = EVM.charge_gas(
            evm, memory_expansion.cost + words_gas_cost_low + words_gas_cost_high
        );
        if (evm.reverted != FALSE) {
            return evm;
        }

        // OPERATION
        tempvar memory = new model.Memory(
            word_dict_start=memory.word_dict_start,
            word_dict=memory.word_dict,
            words_len=memory_expansion.new_words_len,
        );

        let (bigendian_data: felt*) = alloc();
        Memory.load_n(size.low, bigendian_data, offset.low);

        let result = keccak(size.low, bigendian_data);

        Stack.push_uint256(result);

        return evm;
    }
}
