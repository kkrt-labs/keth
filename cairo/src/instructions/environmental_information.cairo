from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.memset import memset
from starkware.cairo.common.math import split_felt
from starkware.cairo.common.math_cmp import is_not_zero, is_nn
from starkware.cairo.common.uint256 import Uint256, uint256_le

from src.account import Account
from src.errors import Errors
from src.evm import EVM
from src.gas import Gas
from src.memory import Memory
from src.model import model
from src.stack import Stack
from src.state import State
from src.utils.array import slice
from src.utils.maths import unsigned_div_rem
from src.utils.uint256 import uint256_to_uint160, uint256_add, uint256_eq
from src.utils.utils import Helpers

// @title Environmental information opcodes.
// @notice This file contains the functions to execute for environmental information opcodes.
namespace EnvironmentalInformation {
    func exec_address{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        stack: model.Stack*,
        memory: model.Memory*,
        state: model.State*,
    }(evm: model.EVM*) -> model.EVM* {
        let address = Helpers.to_uint256(evm.message.address);
        Stack.push(address);
        return evm;
    }

    func exec_balance{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        stack: model.Stack*,
        memory: model.Memory*,
        state: model.State*,
    }(evm: model.EVM*) -> model.EVM* {
        alloc_locals;

        let (address_uint256) = Stack.pop();
        let evm_address = uint256_to_uint160([address_uint256]);

        // Gas
        // Calling `get_account` subsequently will make the account warm for the next interaction
        let is_warm = State.is_account_warm(evm_address);
        tempvar gas = is_warm * Gas.WARM_ACCESS + (1 - is_warm) * Gas.COLD_ACCOUNT_ACCESS;
        let evm = EVM.charge_gas(evm, gas);
        if (evm.reverted != FALSE) {
            return evm;
        }

        let account = State.get_account(evm_address);
        Stack.push(account.balance);

        return evm;
    }

    func exec_origin{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        stack: model.Stack*,
        memory: model.Memory*,
        state: model.State*,
    }(evm: model.EVM*) -> model.EVM* {
        let origin_address = Helpers.to_uint256(evm.message.env.origin);

        Stack.push(origin_address);
        return evm;
    }

    func exec_caller{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        stack: model.Stack*,
        memory: model.Memory*,
        state: model.State*,
    }(evm: model.EVM*) -> model.EVM* {
        let address = Helpers.to_uint256(evm.message.caller);
        Stack.push(address);
        return evm;
    }

    func exec_callvalue{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        stack: model.Stack*,
        memory: model.Memory*,
        state: model.State*,
    }(evm: model.EVM*) -> model.EVM* {
        Stack.push(evm.message.value);

        return evm;
    }

    func exec_calldataload{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        stack: model.Stack*,
        memory: model.Memory*,
        state: model.State*,
    }(evm: model.EVM*) -> model.EVM* {
        alloc_locals;

        let (offset) = Stack.pop();

        if (offset.high != 0) {
            Stack.push_uint128(0);
            return evm;
        }

        let (sliced_calldata: felt*) = alloc();
        slice(sliced_calldata, evm.message.calldata_len, evm.message.calldata, offset.low, 32);
        let calldata = Helpers.bytes32_to_uint256(sliced_calldata);
        Stack.push_uint256(calldata);

        return evm;
    }

    func exec_calldatasize{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        stack: model.Stack*,
        memory: model.Memory*,
        state: model.State*,
    }(evm: model.EVM*) -> model.EVM* {
        Stack.push_uint128(evm.message.calldata_len);
        return evm;
    }

    func exec_returndatacopy{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        stack: model.Stack*,
        memory: model.Memory*,
        state: model.State*,
    }(evm: model.EVM*) -> model.EVM* {
        alloc_locals;

        // STACK
        let (popped) = Stack.pop_n(3);
        let memory_offset = popped[0];
        let returndata_offset = popped[1];
        let size = popped[2];

        // GAS
        let memory_expansion = Gas.memory_expansion_cost_saturated(
            memory.words_len, memory_offset, size
        );

        if (memory_expansion.cost == Gas.MEMORY_COST_U32) {
            let evm = EVM.out_of_gas(evm, memory_expansion.cost);
            return evm;
        }

        // Any size upper than 2**128 will cause an OOG error, considering the maximum gas for a transaction.
        // here with size.low = 2**128 - 1, copy_gas_cost is 0x18000000000000000000000000000000, ie is between 2**124 and 2**125
        let upper_bytes_bound = size.low + 31;
        let (words, _) = unsigned_div_rem(upper_bytes_bound, 32);
        let copy_gas_cost = words * Gas.COPY;

        // static cost handled in jump table
        let evm = EVM.charge_gas(evm, memory_expansion.cost + copy_gas_cost);
        if (evm.reverted != FALSE) {
            return evm;
        }
        // OPERATION
        tempvar memory = new model.Memory(
            word_dict_start=memory.word_dict_start,
            word_dict=memory.word_dict,
            words_len=memory_expansion.new_words_len,
        );

        // Offset.high != 0 means that the sliced data is surely 0x00...00
        // And storing 0 in Memory is just doing nothing.
        if (returndata_offset.high != 0) {
            // We still check for OOB returndatacopy
            let (max_index, carry) = uint256_add(returndata_offset, size);
            let (high, low) = split_felt(evm.return_data_len);
            let (is_in_bounds) = uint256_le(max_index, Uint256(low=low, high=high));
            let is_in_bounds = is_in_bounds * (1 - carry);
            if (is_in_bounds == FALSE) {
                let (revert_reason_len, revert_reason) = Errors.outOfBoundsRead();
                let evm = EVM.stop(evm, revert_reason_len, revert_reason, Errors.EXCEPTIONAL_HALT);
                return evm;
            }
            return evm;
        }

        let (sliced_data: felt*) = alloc();
        tempvar is_in_bounds = is_nn(evm.return_data_len - (returndata_offset.low + size.low));
        if (is_in_bounds == FALSE) {
            let (revert_reason_len, revert_reason) = Errors.outOfBoundsRead();
            let evm = EVM.stop(evm, revert_reason_len, revert_reason, Errors.EXCEPTIONAL_HALT);
            return evm;
        }
        slice(sliced_data, evm.return_data_len, evm.return_data, returndata_offset.low, size.low);

        Memory.store_n(size.low, sliced_data, memory_offset.low);

        return evm;
    }

    func exec_copy{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        stack: model.Stack*,
        memory: model.Memory*,
        state: model.State*,
    }(evm: model.EVM*) -> model.EVM* {
        alloc_locals;

        // STACK
        let (popped) = Stack.pop_n(3);
        let dest_offset = popped[0];
        let offset = popped[1];
        let size = popped[2];

        // if size == 0, we can optimize by returning early
        // fixed opcode cost has already been charged as both
        // calldatacopy and codecopy don't have additional checks
        let (is_zero) = uint256_eq(size, Uint256(low=0, high=0));
        if (is_zero != FALSE) {
            return evm;
        }

        // GAS
        let memory_expansion = Gas.memory_expansion_cost_saturated(
            memory.words_len, dest_offset, size
        );

        if (memory_expansion.cost == Gas.MEMORY_COST_U32) {
            let evm = EVM.out_of_gas(evm, memory_expansion.cost);
            return evm;
        }

        // Any size upper than 2**128 will cause an OOG error, considering the maximum gas for a transaction.
        // here with size.low = 2**128 - 1, copy_gas_cost is 0x18000000000000000000000000000000, ie is between 2**124 and 2**125
        let upper_bytes_bound = size.low + 31;
        let (words, _) = unsigned_div_rem(upper_bytes_bound, 32);
        let copy_gas_cost = words * Gas.COPY;

        // static cost handled in jump table
        let evm = EVM.charge_gas(evm, memory_expansion.cost + copy_gas_cost);
        if (evm.reverted != FALSE) {
            return evm;
        }

        // OPERATION
        tempvar memory = new model.Memory(
            word_dict_start=memory.word_dict_start,
            word_dict=memory.word_dict,
            words_len=memory_expansion.new_words_len,
        );

        let opcode_number = [evm.message.bytecode + evm.program_counter];

        let (data_to_store: felt*) = alloc();
        // Offset.high != 0 means that the sliced data is surely 0x00...00
        // Store 0 in memory
        if (offset.high != 0) {
            memset(dst=data_to_store, value=0, n=size.low);
            Memory.store_n(size.low, data_to_store, dest_offset.low);
            return evm;
        }

        // 0x37: calldatacopy
        // 0x39: codecopy
        local data_len;
        local data: felt*;
        if (opcode_number == 0x37) {
            assert data_len = evm.message.calldata_len;
            assert data = evm.message.calldata;
            tempvar range_check_ptr = range_check_ptr;
        } else {
            assert data_len = evm.message.bytecode_len;
            assert data = evm.message.bytecode;
            tempvar range_check_ptr = range_check_ptr;
        }
        let range_check_ptr = [ap - 1];
        slice(data_to_store, data_len, data, offset.low, size.low);

        Memory.store_n(size.low, data_to_store, dest_offset.low);

        return evm;
    }

    func exec_codesize{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        stack: model.Stack*,
        memory: model.Memory*,
        state: model.State*,
    }(evm: model.EVM*) -> model.EVM* {
        Stack.push_uint128(evm.message.bytecode_len);
        return evm;
    }

    func exec_gasprice{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        stack: model.Stack*,
        memory: model.Memory*,
        state: model.State*,
    }(evm: model.EVM*) -> model.EVM* {
        // TODO: since gas_price is a felt, it might panic when being cast to a Uint256.low,
        // Add check gas_price < 2 ** 128
        // `split_felt` might be too expensive for this if we know gas_price < 2 ** 128
        Stack.push_uint128(evm.message.env.gas_price);

        return evm;
    }

    func exec_extcodesize{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        stack: model.Stack*,
        memory: model.Memory*,
        state: model.State*,
    }(evm: model.EVM*) -> model.EVM* {
        alloc_locals;

        let (address_uint256) = Stack.pop();
        let evm_address = uint256_to_uint160([address_uint256]);

        // Gas
        // Calling `get_account` subsequently will make the account warm for the next interaction
        let is_warm = State.is_account_warm(evm_address);
        tempvar gas = is_warm * Gas.WARM_ACCESS + (1 - is_warm) * Gas.COLD_ACCOUNT_ACCESS;
        let evm = EVM.charge_gas(evm, gas);
        if (evm.reverted != FALSE) {
            return evm;
        }

        let account = State.get_account(evm_address);

        // bytecode_len cannot be greater than 24k in the EVM
        Stack.push_uint128(account.code_len);

        return evm;
    }

    func exec_extcodecopy{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        stack: model.Stack*,
        memory: model.Memory*,
        state: model.State*,
    }(evm: model.EVM*) -> model.EVM* {
        alloc_locals;

        let (popped) = Stack.pop_n(4);
        let evm_address = uint256_to_uint160(popped[0]);
        let dest_offset = popped[1];
        let offset = popped[2];
        let size = popped[3];

        // Gas
        // Calling `get_account` subsequently will make the account warm for the next interaction
        let is_warm = State.is_account_warm(evm_address);
        tempvar access_gas_cost = is_warm * Gas.WARM_ACCESS + (1 - is_warm) *
            Gas.COLD_ACCOUNT_ACCESS;

        // Any size upper than 2**128 will cause an OOG error, considering the maximum gas for a transaction.
        // here with size.low = 2**128 - 1, copy_gas_cost is 0x18000000000000000000000000000000, ie is between 2**124 and 2**125
        let upper_bytes_bound = size.low + 31;
        let (words, _) = unsigned_div_rem(upper_bytes_bound, 32);
        let copy_gas_cost = words * Gas.COPY;

        let memory_expansion = Gas.memory_expansion_cost_saturated(
            memory.words_len, dest_offset, size
        );

        if (memory_expansion.cost == Gas.MEMORY_COST_U32) {
            let evm = EVM.out_of_gas(evm, memory_expansion.cost);
            return evm;
        }

        let evm = EVM.charge_gas(evm, access_gas_cost + copy_gas_cost + memory_expansion.cost);
        if (evm.reverted != FALSE) {
            return evm;
        }

        tempvar memory = new model.Memory(
            word_dict_start=memory.word_dict_start,
            word_dict=memory.word_dict,
            words_len=memory_expansion.new_words_len,
        );

        let (data_to_store: felt*) = alloc();
        // Offset.high != 0 means that the sliced data is surely 0x00...00
        // Store 0 in memory
        if (offset.high != 0) {
            memset(dst=data_to_store, value=0, n=size.low);
            Memory.store_n(size.low, data_to_store, dest_offset.low);
            return evm;
        }

        let account = State.get_account(evm_address);
        slice(data_to_store, account.code_len, account.code, offset.low, size.low);

        Memory.store_n(size.low, data_to_store, dest_offset.low);

        return evm;
    }

    func exec_returndatasize{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        stack: model.Stack*,
        memory: model.Memory*,
        state: model.State*,
    }(evm: model.EVM*) -> model.EVM* {
        Stack.push_uint128(evm.return_data_len);
        return evm;
    }

    func exec_extcodehash{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        stack: model.Stack*,
        memory: model.Memory*,
        state: model.State*,
    }(evm: model.EVM*) -> model.EVM* {
        alloc_locals;

        let (address_uint256) = Stack.pop();
        let evm_address = uint256_to_uint160([address_uint256]);

        // Gas
        // Calling `get_account` subsequently will make the account warm for the next interaction
        let is_warm = State.is_account_warm(evm_address);
        tempvar access_gas_cost = is_warm * Gas.WARM_ACCESS + (1 - is_warm) *
            Gas.COLD_ACCOUNT_ACCESS;
        let evm = EVM.charge_gas(evm, access_gas_cost);
        if (evm.reverted != FALSE) {
            return evm;
        }

        let account = State.get_account(evm_address);
        let has_code_or_nonce = Account.has_code_or_nonce(account);
        let account_exists = has_code_or_nonce + account.balance.low + account.balance.high;
        // Relevant cases:
        // https://github.com/ethereum/go-ethereum/blob/master/core/vm/instructions.go#L392
        if (account_exists == FALSE) {
            Stack.push_uint128(0);
            return evm;
        }

        Stack.push_uint256([account.code_hash]);

        return evm;
    }
}
