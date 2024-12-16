from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE, TRUE
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.math_cmp import is_not_zero, is_nn, is_le_felt
from starkware.cairo.common.math import split_felt
from starkware.cairo.common.default_dict import default_dict_new
from starkware.cairo.common.dict import DictAccess
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc, get_ap
from starkware.cairo.common.uint256 import Uint256, uint256_le

from src.account import Account
from src.constants import opcodes_label, Constants
from src.errors import Errors
from src.evm import EVM
from src.instructions.block_information import BlockInformation
from src.instructions.duplication_operations import DuplicationOperations
from src.instructions.environmental_information import EnvironmentalInformation
from src.instructions.exchange_operations import ExchangeOperations
from src.instructions.logging_operations import LoggingOperations
from src.instructions.memory_operations import MemoryOperations
from src.instructions.push_operations import PushOperations
from src.instructions.sha3 import Sha3
from src.instructions.stop_and_math_operations import StopAndMathOperations
from src.instructions.system_operations import CallHelper, CreateHelper, SystemOperations
from src.memory import Memory
from src.model import model
from src.precompiles.precompiles import Precompiles
from src.stack import Stack
from src.state import State
from src.gas import Gas, GAS_INIT_CODE_WORD_COST
from src.utils.utils import Helpers
from src.utils.array import count_not_zero
from src.utils.uint256 import uint256_sub, uint256_add
from src.utils.maths import unsigned_div_rem

// @title EVM instructions processing.
// @notice This file contains functions related to the processing of EVM instructions.
namespace Interpreter {
    // @notice Decode the current opcode and execute associated function.
    // @dev The function uses an internal jump table to execute the corresponding opcode
    // @param evm The pointer to the execution context.
    // @return EVM The pointer to the updated execution context.
    func exec_opcode{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        keccak_ptr: KeccakBuiltin*,
        stack: model.Stack*,
        memory: model.Memory*,
        state: model.State*,
    }(evm: model.EVM*) -> model.EVM* {
        alloc_locals;

        local opcode_number;
        local opcode: model.Opcode*;

        let pc = evm.program_counter;
        let is_pc_ge_code_len = is_nn(pc - evm.message.bytecode_len);
        if (is_pc_ge_code_len != FALSE) {
            let is_precompile = Precompiles.is_precompile(evm.message.code_address);
            if (is_precompile != FALSE) {
                let (
                    output_len, output, gas_used, precompile_reverted
                ) = Precompiles.exec_precompile(
                    evm.message.code_address, evm.message.calldata_len, evm.message.calldata
                );
                let evm = EVM.charge_gas(evm, gas_used);
                let evm_reverted = is_not_zero(evm.reverted);
                let success = (1 - precompile_reverted) * (1 - evm_reverted);
                let evm = EVM.stop(evm, output_len, output, 1 - success);
                tempvar message = new model.Message(
                    bytecode=evm.message.bytecode,
                    bytecode_len=evm.message.bytecode_len,
                    valid_jumpdests_start=evm.message.valid_jumpdests_start,
                    valid_jumpdests=evm.message.valid_jumpdests,
                    calldata=evm.message.calldata,
                    calldata_len=evm.message.calldata_len,
                    value=evm.message.value,
                    caller=evm.message.caller,
                    parent=evm.message.parent,
                    address=evm.message.address,
                    code_address=evm.message.code_address,
                    read_only=evm.message.read_only,
                    is_create=evm.message.is_create,
                    depth=evm.message.depth,
                    env=evm.message.env,
                    initial_state=evm.message.initial_state,
                );
                tempvar evm = new model.EVM(
                    message=message,
                    return_data_len=evm.return_data_len,
                    return_data=evm.return_data,
                    program_counter=evm.program_counter,
                    stopped=evm.stopped,
                    gas_left=evm.gas_left,
                    gas_refund=evm.gas_refund,
                    reverted=evm.reverted,
                );
                return evm;
            } else {
                let (return_data: felt*) = alloc();
                let evm = EVM.stop(evm, 0, return_data, FALSE);
                return evm;
            }
        }
        assert opcode_number = [evm.message.bytecode + pc];

        // Get the corresponding opcode data
        // To cast the codeoffset opcodes_label to a model.Opcode*, we need to use it to offset
        // the current pc. We get the pc from the `get_fp_and_pc` util and assign a codeoffset (pc_label) to it.
        // In short, this boils down to: opcode = pc + offset - pc = offset
        let (_, cairo_pc) = get_fp_and_pc();

        pc_label:
        assert opcode = cast(
            cairo_pc + (opcodes_label - pc_label) + opcode_number * model.Opcode.SIZE, model.Opcode*
        );

        // Check stack over/under flow
        let stack_underflow = is_nn(opcode.stack_size_min - 1 - stack.size);
        if (stack_underflow != 0) {
            let (revert_reason_len, revert_reason) = Errors.stackUnderflow();
            let evm = EVM.stop(evm, revert_reason_len, revert_reason, Errors.EXCEPTIONAL_HALT);
            return evm;
        }
        let stack_overflow = is_nn(
            stack.size + opcode.stack_size_diff - (Constants.STACK_MAX_DEPTH + 1)
        );
        if (stack_overflow != 0) {
            let (revert_reason_len, revert_reason) = Errors.stackOverflow();
            let evm = EVM.stop(evm, revert_reason_len, revert_reason, Errors.EXCEPTIONAL_HALT);
            return evm;
        }

        // Update static gas
        let evm = EVM.charge_gas(evm, opcode.gas);
        if (evm.reverted != FALSE) {
            return evm;
        }

        // Compute the corresponding offset in the jump table:
        // count 1 for "next line" and 4 steps per opcode: call, opcode, jmp, end
        tempvar offset = 1 + 4 * opcode_number;

        // Prepare arguments
        [ap] = pedersen_ptr, ap++;
        [ap] = range_check_ptr, ap++;
        [ap] = bitwise_ptr, ap++;
        [ap] = keccak_ptr, ap++;
        [ap] = stack, ap++;
        [ap] = memory, ap++;
        [ap] = state, ap++;
        [ap] = evm, ap++;

        // call opcode
        jmp rel offset;
        call StopAndMathOperations.exec_stop;  // 0x0
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x1
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x2
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x3
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x4
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x5
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x6
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x7
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x8
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x9
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0xa
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0xb
        jmp end;
        call unknown_opcode;  // 0xc
        jmp end;
        call unknown_opcode;  // 0xd
        jmp end;
        call unknown_opcode;  // 0xe
        jmp end;
        call unknown_opcode;  // 0xf
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x10
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x11
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x12
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x13
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x14
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x15
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x16
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x17
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x18
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x19
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x1a
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x1b
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x1c
        jmp end;
        call StopAndMathOperations.exec_math_operation;  // 0x1d
        jmp end;
        call unknown_opcode;  // 0x1e
        jmp end;
        call unknown_opcode;  // 0x1f
        jmp end;
        call Sha3.exec_sha3;  // 0x20
        jmp end;
        call unknown_opcode;  // 0x21
        jmp end;
        call unknown_opcode;  // 0x22
        jmp end;
        call unknown_opcode;  // 0x23
        jmp end;
        call unknown_opcode;  // 0x24
        jmp end;
        call unknown_opcode;  // 0x25
        jmp end;
        call unknown_opcode;  // 0x26
        jmp end;
        call unknown_opcode;  // 0x27
        jmp end;
        call unknown_opcode;  // 0x28
        jmp end;
        call unknown_opcode;  // 0x29
        jmp end;
        call unknown_opcode;  // 0x2a
        jmp end;
        call unknown_opcode;  // 0x2b
        jmp end;
        call unknown_opcode;  // 0x2c
        jmp end;
        call unknown_opcode;  // 0x2d
        jmp end;
        call unknown_opcode;  // 0x2e
        jmp end;
        call unknown_opcode;  // 0x2f
        jmp end;
        call EnvironmentalInformation.exec_address;  // 0x30
        jmp end;
        call EnvironmentalInformation.exec_balance;  // 0x31
        jmp end;
        call EnvironmentalInformation.exec_origin;  // 0x32
        jmp end;
        call EnvironmentalInformation.exec_caller;  // 0x33
        jmp end;
        call EnvironmentalInformation.exec_callvalue;  // 0x34
        jmp end;
        call EnvironmentalInformation.exec_calldataload;  // 0x35
        jmp end;
        call EnvironmentalInformation.exec_calldatasize;  // 0x36
        jmp end;
        call EnvironmentalInformation.exec_copy;  // 0x37
        jmp end;
        call EnvironmentalInformation.exec_codesize;  // 0x38
        jmp end;
        call EnvironmentalInformation.exec_copy;  // 0x39
        jmp end;
        call EnvironmentalInformation.exec_gasprice;  // 0x3a
        jmp end;
        call EnvironmentalInformation.exec_extcodesize;  // 0x3b
        jmp end;
        call EnvironmentalInformation.exec_extcodecopy;  // 0x3c
        jmp end;
        call EnvironmentalInformation.exec_returndatasize;  // 0x3d
        jmp end;
        call EnvironmentalInformation.exec_returndatacopy;  // 0x3e
        jmp end;
        call EnvironmentalInformation.exec_extcodehash;  // 0x3f
        jmp end;
        call BlockInformation.exec_block_information;  // 0x40
        jmp end;
        call BlockInformation.exec_block_information;  // 0x41
        jmp end;
        call BlockInformation.exec_block_information;  // 0x42
        jmp end;
        call BlockInformation.exec_block_information;  // 0x43
        jmp end;
        call BlockInformation.exec_block_information;  // 0x44
        jmp end;
        call BlockInformation.exec_block_information;  // 0x45
        jmp end;
        call BlockInformation.exec_block_information;  // 0x46
        jmp end;
        call BlockInformation.exec_block_information;  // 0x47
        jmp end;
        call BlockInformation.exec_block_information;  // 0x48
        jmp end;
        call BlockInformation.exec_block_information;  // 0x49
        jmp end;
        call BlockInformation.exec_block_information;  // 0x4a
        jmp end;
        call unknown_opcode;  // 0x4b
        jmp end;
        call unknown_opcode;  // 0x4c
        jmp end;
        call unknown_opcode;  // 0x4d
        jmp end;
        call unknown_opcode;  // 0x4e
        jmp end;
        call unknown_opcode;  // 0x4f
        jmp end;
        call MemoryOperations.exec_pop;  // 0x50
        jmp end;
        call MemoryOperations.exec_mload;  // 0x51
        jmp end;
        call MemoryOperations.exec_mstore;  // 0x52
        jmp end;
        call MemoryOperations.exec_mstore8;  // 0x53
        jmp end;
        call MemoryOperations.exec_sload;  // 0x54
        jmp end;
        call MemoryOperations.exec_sstore;  // 0x55
        jmp end;
        call MemoryOperations.exec_jump;  // 0x56
        jmp end_no_pc_increment;
        call MemoryOperations.exec_jumpi;  // 0x57
        jmp end_no_pc_increment;
        call MemoryOperations.exec_pc;  // 0x58
        jmp end;
        call MemoryOperations.exec_msize;  // 0x59
        jmp end;
        call MemoryOperations.exec_gas;  // 0x5a
        jmp end;
        call MemoryOperations.exec_jumpdest;  // 0x5b
        jmp end;
        call MemoryOperations.exec_tload;  // 0x5c
        jmp end;
        call MemoryOperations.exec_tstore;  // 0x5d
        jmp end;
        call MemoryOperations.exec_mcopy;  // 0x5e
        jmp end;
        call PushOperations.exec_push;  // 0x5f
        jmp end;
        call PushOperations.exec_push;  // 0x60
        jmp end;
        call PushOperations.exec_push;  // 0x61
        jmp end;
        call PushOperations.exec_push;  // 0x62
        jmp end;
        call PushOperations.exec_push;  // 0x63
        jmp end;
        call PushOperations.exec_push;  // 0x64
        jmp end;
        call PushOperations.exec_push;  // 0x65
        jmp end;
        call PushOperations.exec_push;  // 0x66
        jmp end;
        call PushOperations.exec_push;  // 0x67
        jmp end;
        call PushOperations.exec_push;  // 0x68
        jmp end;
        call PushOperations.exec_push;  // 0x69
        jmp end;
        call PushOperations.exec_push;  // 0x6a
        jmp end;
        call PushOperations.exec_push;  // 0x6b
        jmp end;
        call PushOperations.exec_push;  // 0x6c
        jmp end;
        call PushOperations.exec_push;  // 0x6d
        jmp end;
        call PushOperations.exec_push;  // 0x6e
        jmp end;
        call PushOperations.exec_push;  // 0x6f
        jmp end;
        call PushOperations.exec_push;  // 0x70
        jmp end;
        call PushOperations.exec_push;  // 0x71
        jmp end;
        call PushOperations.exec_push;  // 0x72
        jmp end;
        call PushOperations.exec_push;  // 0x73
        jmp end;
        call PushOperations.exec_push;  // 0x74
        jmp end;
        call PushOperations.exec_push;  // 0x75
        jmp end;
        call PushOperations.exec_push;  // 0x76
        jmp end;
        call PushOperations.exec_push;  // 0x77
        jmp end;
        call PushOperations.exec_push;  // 0x78
        jmp end;
        call PushOperations.exec_push;  // 0x79
        jmp end;
        call PushOperations.exec_push;  // 0x7a
        jmp end;
        call PushOperations.exec_push;  // 0x7b
        jmp end;
        call PushOperations.exec_push;  // 0x7c
        jmp end;
        call PushOperations.exec_push;  // 0x7d
        jmp end;
        call PushOperations.exec_push;  // 0x7e
        jmp end;
        call PushOperations.exec_push;  // 0x7f
        jmp end;
        call DuplicationOperations.exec_dup;  // 0x80
        jmp end;
        call DuplicationOperations.exec_dup;  // 0x81
        jmp end;
        call DuplicationOperations.exec_dup;  // 0x82
        jmp end;
        call DuplicationOperations.exec_dup;  // 0x83
        jmp end;
        call DuplicationOperations.exec_dup;  // 0x84
        jmp end;
        call DuplicationOperations.exec_dup;  // 0x85
        jmp end;
        call DuplicationOperations.exec_dup;  // 0x86
        jmp end;
        call DuplicationOperations.exec_dup;  // 0x87
        jmp end;
        call DuplicationOperations.exec_dup;  // 0x88
        jmp end;
        call DuplicationOperations.exec_dup;  // 0x89
        jmp end;
        call DuplicationOperations.exec_dup;  // 0x8a
        jmp end;
        call DuplicationOperations.exec_dup;  // 0x8b
        jmp end;
        call DuplicationOperations.exec_dup;  // 0x8c
        jmp end;
        call DuplicationOperations.exec_dup;  // 0x8d
        jmp end;
        call DuplicationOperations.exec_dup;  // 0x8e
        jmp end;
        call DuplicationOperations.exec_dup;  // 0x8f
        jmp end;
        call ExchangeOperations.exec_swap;  // 0x90
        jmp end;
        call ExchangeOperations.exec_swap;  // 0x91
        jmp end;
        call ExchangeOperations.exec_swap;  // 0x92
        jmp end;
        call ExchangeOperations.exec_swap;  // 0x93
        jmp end;
        call ExchangeOperations.exec_swap;  // 0x94
        jmp end;
        call ExchangeOperations.exec_swap;  // 0x95
        jmp end;
        call ExchangeOperations.exec_swap;  // 0x96
        jmp end;
        call ExchangeOperations.exec_swap;  // 0x97
        jmp end;
        call ExchangeOperations.exec_swap;  // 0x98
        jmp end;
        call ExchangeOperations.exec_swap;  // 0x99
        jmp end;
        call ExchangeOperations.exec_swap;  // 0x9a
        jmp end;
        call ExchangeOperations.exec_swap;  // 0x9b
        jmp end;
        call ExchangeOperations.exec_swap;  // 0x9c
        jmp end;
        call ExchangeOperations.exec_swap;  // 0x9d
        jmp end;
        call ExchangeOperations.exec_swap;  // 0x9e
        jmp end;
        call ExchangeOperations.exec_swap;  // 0x9f
        jmp end;
        call LoggingOperations.exec_log;  // 0xa0
        jmp end;
        call LoggingOperations.exec_log;  // 0xa1
        jmp end;
        call LoggingOperations.exec_log;  // 0xa2
        jmp end;
        call LoggingOperations.exec_log;  // 0xa3
        jmp end;
        call LoggingOperations.exec_log;  // 0xa4
        jmp end;
        call unknown_opcode;  // 0xa5
        jmp end;
        call unknown_opcode;  // 0xa6
        jmp end;
        call unknown_opcode;  // 0xa7
        jmp end;
        call unknown_opcode;  // 0xa8
        jmp end;
        call unknown_opcode;  // 0xa9
        jmp end;
        call unknown_opcode;  // 0xaa
        jmp end;
        call unknown_opcode;  // 0xab
        jmp end;
        call unknown_opcode;  // 0xac
        jmp end;
        call unknown_opcode;  // 0xad
        jmp end;
        call unknown_opcode;  // 0xae
        jmp end;
        call unknown_opcode;  // 0xaf
        jmp end;
        call unknown_opcode;  // 0xb0
        jmp end;
        call unknown_opcode;  // 0xb1
        jmp end;
        call unknown_opcode;  // 0xb2
        jmp end;
        call unknown_opcode;  // 0xb3
        jmp end;
        call unknown_opcode;  // 0xb4
        jmp end;
        call unknown_opcode;  // 0xb5
        jmp end;
        call unknown_opcode;  // 0xb6
        jmp end;
        call unknown_opcode;  // 0xb7
        jmp end;
        call unknown_opcode;  // 0xb8
        jmp end;
        call unknown_opcode;  // 0xb9
        jmp end;
        call unknown_opcode;  // 0xba
        jmp end;
        call unknown_opcode;  // 0xbb
        jmp end;
        call unknown_opcode;  // 0xbc
        jmp end;
        call unknown_opcode;  // 0xbd
        jmp end;
        call unknown_opcode;  // 0xbe
        jmp end;
        call unknown_opcode;  // 0xbf
        jmp end;
        call unknown_opcode;  // 0xc0
        jmp end;
        call unknown_opcode;  // 0xc1
        jmp end;
        call unknown_opcode;  // 0xc2
        jmp end;
        call unknown_opcode;  // 0xc3
        jmp end;
        call unknown_opcode;  // 0xc4
        jmp end;
        call unknown_opcode;  // 0xc5
        jmp end;
        call unknown_opcode;  // 0xc6
        jmp end;
        call unknown_opcode;  // 0xc7
        jmp end;
        call unknown_opcode;  // 0xc8
        jmp end;
        call unknown_opcode;  // 0xc9
        jmp end;
        call unknown_opcode;  // 0xca
        jmp end;
        call unknown_opcode;  // 0xcb
        jmp end;
        call unknown_opcode;  // 0xcc
        jmp end;
        call unknown_opcode;  // 0xcd
        jmp end;
        call unknown_opcode;  // 0xce
        jmp end;
        call unknown_opcode;  // 0xcf
        jmp end;
        call unknown_opcode;  // 0xd0
        jmp end;
        call unknown_opcode;  // 0xd1
        jmp end;
        call unknown_opcode;  // 0xd2
        jmp end;
        call unknown_opcode;  // 0xd3
        jmp end;
        call unknown_opcode;  // 0xd4
        jmp end;
        call unknown_opcode;  // 0xd5
        jmp end;
        call unknown_opcode;  // 0xd6
        jmp end;
        call unknown_opcode;  // 0xd7
        jmp end;
        call unknown_opcode;  // 0xd8
        jmp end;
        call unknown_opcode;  // 0xd9
        jmp end;
        call unknown_opcode;  // 0xda
        jmp end;
        call unknown_opcode;  // 0xdb
        jmp end;
        call unknown_opcode;  // 0xdc
        jmp end;
        call unknown_opcode;  // 0xdd
        jmp end;
        call unknown_opcode;  // 0xde
        jmp end;
        call unknown_opcode;  // 0xdf
        jmp end;
        call unknown_opcode;  // 0xe0
        jmp end;
        call unknown_opcode;  // 0xe1
        jmp end;
        call unknown_opcode;  // 0xe2
        jmp end;
        call unknown_opcode;  // 0xe3
        jmp end;
        call unknown_opcode;  // 0xe4
        jmp end;
        call unknown_opcode;  // 0xe5
        jmp end;
        call unknown_opcode;  // 0xe6
        jmp end;
        call unknown_opcode;  // 0xe7
        jmp end;
        call unknown_opcode;  // 0xe8
        jmp end;
        call unknown_opcode;  // 0xe9
        jmp end;
        call unknown_opcode;  // 0xea
        jmp end;
        call unknown_opcode;  // 0xeb
        jmp end;
        call unknown_opcode;  // 0xec
        jmp end;
        call unknown_opcode;  // 0xed
        jmp end;
        call unknown_opcode;  // 0xee
        jmp end;
        call unknown_opcode;  // 0xef
        jmp end;
        call SystemOperations.exec_create;  // 0xf0
        jmp end;
        call SystemOperations.exec_call;  // 0xf1
        jmp end;
        call SystemOperations.exec_callcode;  // 0xf2
        jmp end;
        call SystemOperations.exec_return;  // 0xf3
        jmp end;
        call SystemOperations.exec_delegatecall;  // 0xf4
        jmp end;
        call SystemOperations.exec_create;  // 0xf5
        jmp end;
        call unknown_opcode;  // 0xf6
        jmp end;
        call unknown_opcode;  // 0xf7
        jmp end;
        call unknown_opcode;  // 0xf8
        jmp end;
        call unknown_opcode;  // 0xf9
        jmp end;
        call SystemOperations.exec_staticcall;  // 0xfa
        jmp end;
        call unknown_opcode;  // 0xfb
        jmp end;
        call unknown_opcode;  // 0xfc
        jmp end;
        call SystemOperations.exec_revert;  // 0xfd
        jmp end;
        call SystemOperations.exec_invalid;  // 0xfe
        jmp end;
        call SystemOperations.exec_selfdestruct;  // 0xff
        jmp end;

        end:
        let pedersen_ptr = cast([ap - 8], HashBuiltin*);
        let range_check_ptr = [ap - 7];
        let bitwise_ptr = cast([ap - 6], BitwiseBuiltin*);
        let keccak_ptr = cast([ap - 5], KeccakBuiltin*);
        let stack = cast([ap - 4], model.Stack*);
        let memory = cast([ap - 3], model.Memory*);
        let state = cast([ap - 2], model.State*);
        let evm = cast([ap - 1], model.EVM*);

        let evm_prev = cast([fp - 3], model.EVM*);

        if (evm_prev.message.depth == evm.message.depth) {
            let evm = EVM.increment_program_counter(evm, 1);
            return evm;
        } else {
            return evm;
        }

        end_no_pc_increment:
        let pedersen_ptr = cast([ap - 8], HashBuiltin*);
        let range_check_ptr = [ap - 7];
        let bitwise_ptr = cast([ap - 6], BitwiseBuiltin*);
        let keccak_ptr = cast([ap - 5], KeccakBuiltin*);
        let stack = cast([ap - 4], model.Stack*);
        let memory = cast([ap - 3], model.Memory*);
        let state = cast([ap - 2], model.State*);
        let evm = cast([ap - 1], model.EVM*);

        return evm;
    }

    // @notice A placeholder for opcodes that don't exist
    // @dev Halts execution
    // @param evm The pointer to the execution context
    func unknown_opcode{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        keccak_ptr: KeccakBuiltin*,
        stack: model.Stack*,
        memory: model.Memory*,
        state: model.State*,
    }(evm: model.EVM*) -> model.EVM* {
        let (revert_reason_len, revert_reason) = Errors.unknownOpcode();
        let evm = EVM.stop(evm, revert_reason_len, revert_reason, Errors.EXCEPTIONAL_HALT);
        return evm;
    }

    // @notice Iteratively decode and execute the bytecode of an EVM
    // @param evm The pointer to the execution context.
    // @return EVM The pointer to the updated execution context.
    func run{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        keccak_ptr: KeccakBuiltin*,
        stack: model.Stack*,
        memory: model.Memory*,
        state: model.State*,
    }(evm: model.EVM*) -> model.EVM* {
        alloc_locals;

        if (evm.stopped == FALSE) {
            let evm = exec_opcode(evm);
            return run(evm);
        }

        Memory.finalize();
        Stack.finalize();
        State.finalize();
        with evm {
            EVM.finalize();
        }

        if (evm.message.depth == 0) {
            if (evm.reverted != 0) {
                // All REVERTS in a root ctx set the gas_refund to 0.
                // Only if the execution has halted exceptionally, consume all gas
                let is_not_exceptional_revert = Helpers.is_zero(evm.reverted - 1);
                let gas_left = is_not_exceptional_revert * evm.gas_left;
                tempvar evm = new model.EVM(
                    message=evm.message,
                    return_data_len=evm.return_data_len,
                    return_data=evm.return_data,
                    program_counter=evm.program_counter,
                    stopped=evm.stopped,
                    gas_left=gas_left,
                    gas_refund=0,
                    reverted=evm.reverted,
                );
                return evm;
            }
            if (evm.message.is_create != FALSE) {
                let evm = Internals._finalize_create_tx(evm);
                return evm;
            }

            return evm;
        }

        let stack = evm.message.parent.stack;
        let memory = evm.message.parent.memory;

        if (evm.message.is_create != FALSE) {
            let evm = CreateHelper.finalize_parent(evm);
            return run(evm);
        } else {
            let evm = CallHelper.finalize_parent(evm);
            return run(evm);
        }
    }

    // @notice Run the given bytecode with the given calldata and parameters
    // @param address The target account address
    // @param is_deploy_tx Whether the transaction is a deploy tx or not
    // @param origin The caller EVM address
    // @param bytecode_len The length of the bytecode
    // @param bytecode The bytecode run
    // @param calldata_len The length of the calldata
    // @param calldata The calldata of the execution
    // @param value The value of the execution
    // @param gas_limit The gas limit of the execution
    // @param gas_price The gas price for the execution
    // @param access_list_len The length (in number of felts) of the serialized access list
    // @param access_list The access list
    // @return evm The EVM post-execution
    // @return state The state post-execution
    // @return stack The stack post-execution
    // @return memory The memory post-execution
    // @return gas_used the gas used by the transaction
    // @return required_gas The amount of gas required by the transaction to successfully execute. This is different
    // from the gas used by the transaction as it doesn't take into account any refunds.
    func execute{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        keccak_ptr: KeccakBuiltin*,
        state: model.State*,
    }(
        env: model.Environment*,
        address: felt,
        is_deploy_tx: felt,
        bytecode_len: felt,
        bytecode: felt*,
        calldata_len: felt,
        calldata: felt*,
        value: Uint256*,
        gas_limit: felt,
        access_list_len: felt,
        access_list: felt*,
    ) {
        alloc_locals;
        let fp_and_pc = get_fp_and_pc();
        local __fp__: felt* = fp_and_pc.fp_val;

        // Compute intrinsic gas usage
        // See https://www.evm.codes/about#gascosts
        let count = count_not_zero(calldata_len, calldata);
        let zeroes = calldata_len - count;
        let calldata_gas = zeroes * 4 + count * 16;
        let intrinsic_gas = Gas.TX_BASE_COST + calldata_gas;

        // If is_deploy_tx is TRUE, then
        // bytecode is data and data is empty
        // else, bytecode and data are kept as is
        let bytecode_len = calldata_len * is_deploy_tx + bytecode_len * (1 - is_deploy_tx);
        let calldata_len = calldata_len * (1 - is_deploy_tx);

        let tmp_bytecode = bytecode;
        let tmp_calldata = calldata;
        let tmp_intrinsic_gas = intrinsic_gas;
        local bytecode: felt*;
        local calldata: felt*;
        local intrinsic_gas: felt;
        local code_address: felt;
        if (is_deploy_tx != FALSE) {
            let (empty: felt*) = alloc();
            let (init_code_words, _) = unsigned_div_rem(bytecode_len + 31, 32);
            let init_code_gas = GAS_INIT_CODE_WORD_COST * init_code_words;
            assert bytecode = tmp_calldata;
            assert calldata = empty;
            assert intrinsic_gas = tmp_intrinsic_gas + Gas.CREATE + init_code_gas;
            assert code_address = 0;
            tempvar range_check_ptr = range_check_ptr;
        } else {
            assert bytecode = tmp_bytecode;
            assert calldata = tmp_calldata;
            assert intrinsic_gas = tmp_intrinsic_gas;
            assert code_address = address;
            tempvar range_check_ptr = range_check_ptr;
        }

        let (valid_jumpdests_start, valid_jumpdests) = Helpers.initialize_jumpdests(
            bytecode_len=bytecode_len, bytecode=bytecode
        );
        let valid_jumpdests_start = cast([ap - 2], DictAccess*);
        let valid_jumpdests = cast([ap - 1], DictAccess*);

        let initial_state = State.copy();
        tempvar message = new model.Message(
            bytecode=bytecode,
            bytecode_len=bytecode_len,
            valid_jumpdests_start=valid_jumpdests_start,
            valid_jumpdests=valid_jumpdests,
            calldata=calldata,
            calldata_len=calldata_len,
            value=value,
            caller=env.origin,
            parent=cast(0, model.Parent*),
            address=address,
            code_address=code_address,
            read_only=FALSE,
            is_create=is_deploy_tx,
            depth=0,
            env=env,
            initial_state=initial_state,
        );

        let stack = Stack.init();
        let memory = Memory.init();

        // Cache the coinbase, precompiles, caller, and target, making them warm
        with state {
            let coinbase = State.get_account(env.coinbase);
            State.cache_precompiles();
            State.get_account(address);
            let access_list_cost = State.cache_access_list(access_list_len, access_list);
        }

        let intrinsic_gas = intrinsic_gas + access_list_cost;
        let evm = EVM.init(message, gas_limit - intrinsic_gas);

        let is_gas_limit_enough = is_le_felt(intrinsic_gas, gas_limit);
        if (is_gas_limit_enough == FALSE) {
            let evm = EVM.halt_validation_failed(evm);
            State.finalize{state=state}();
            return ();
        }

        tempvar is_initcode_invalid = is_deploy_tx * is_nn(
            bytecode_len - (2 * Constants.MAX_CODE_SIZE + 1)
        );
        if (is_initcode_invalid != FALSE) {
            let evm = EVM.halt_validation_failed(evm);
            State.finalize{state=state}();
            return ();
        }

        // Charge the gas fee to the user without setting up a transfer.
        // Transfers with the exact amounts will be performed post-execution.
        // Note: balance > effective_fee was verified in eth_send_raw_unsigned_tx()
        let max_fee = gas_limit * env.gas_price;
        let (fee_high, fee_low) = split_felt(max_fee);
        let max_fee_u256 = Uint256(low=fee_low, high=fee_high);

        with state {
            let sender = State.get_account(env.origin);
            let (local new_balance) = uint256_sub([sender.balance], max_fee_u256);
            let sender = Account.set_balance(sender, &new_balance);
            let sender = Account.set_nonce(sender, sender.nonce + 1);
            State.update_account(env.origin, sender);

            let transfer = model.Transfer(env.origin, address, [value]);
            let success = State.add_transfer(transfer);

            // Check collision
            let account = State.get_account(address);
            let code_or_nonce = Account.has_code_or_nonce(account);
            let is_collision = code_or_nonce * is_deploy_tx;
            // Nonce is set to 1 in case of deploy_tx and account is marked as created
            let nonce = account.nonce * (1 - is_deploy_tx) + is_deploy_tx;
            let account = Account.set_nonce(account, nonce);
            let account = Account.set_created(account, is_deploy_tx);
            State.update_account(address, account);
        }

        if (is_collision != 0) {
            let (revert_reason_len, revert_reason) = Errors.addressCollision();
            tempvar evm = EVM.stop(evm, revert_reason_len, revert_reason, Errors.EXCEPTIONAL_HALT);
        } else {
            tempvar evm = evm;
        }

        if (success == 0) {
            let (revert_reason_len, revert_reason) = Errors.balanceError();
            tempvar evm = EVM.stop(evm, revert_reason_len, revert_reason, Errors.EXCEPTIONAL_HALT);
        } else {
            tempvar evm = evm;
        }

        with stack, memory, state {
            let evm = run(evm);
        }

        let required_gas = gas_limit - evm.gas_left;
        let (max_refund, _) = unsigned_div_rem(required_gas, 5);
        let is_max_refund_le_gas_refund = is_nn(evm.gas_refund - max_refund);
        tempvar gas_refund = is_max_refund_le_gas_refund * max_refund + (
            1 - is_max_refund_le_gas_refund
        ) * evm.gas_refund;

        let total_gas_used = required_gas - gas_refund;

        // Reset the state if the execution has failed.
        // Only the gas fee paid will be committed.
        State.finalize{state=state}();
        tempvar initial_state = evm.message.initial_state;
        State.finalize{state=initial_state}();

        if (evm.reverted != 0) {
            tempvar state = initial_state;
        } else {
            tempvar state = state;
        }
        let is_reverted = is_not_zero(evm.reverted);
        let success = 1 - is_reverted;
        let paid_fee_u256 = Uint256(max_fee_u256.low * success, max_fee_u256.high * success);

        with state {
            let sender = State.get_account(env.origin);
            uint256_add([sender.balance], paid_fee_u256);
            let (ap_val) = get_ap();
            let sender = Account.set_balance(sender, cast(ap_val - 3, Uint256*));
            let sender = Account.set_nonce(sender, sender.nonce + is_reverted);
            State.update_account(env.origin, sender);
        }

        // So as to not burn the base_fee_per gas, we send it to the coinbase.
        let actual_fee = total_gas_used * env.gas_price;
        let (fee_high, fee_low) = split_felt(actual_fee);
        let actual_fee_u256 = Uint256(low=fee_low, high=fee_high);
        let transfer = model.Transfer(env.origin, env.coinbase, actual_fee_u256);

        with state {
            State.add_transfer(transfer);
            State.finalize();
        }

        return ();
    }
}

namespace Internals {
    func _finalize_create_tx{
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
        keccak_ptr: KeccakBuiltin*,
        pedersen_ptr: HashBuiltin*,
        state: model.State*,
    }(evm: model.EVM*) -> model.EVM* {
        alloc_locals;
        let is_reverted = is_not_zero(evm.reverted);
        if (is_reverted != 0) {
            return evm;
        }

        // Charge final deposit gas
        let code_size_limit = is_nn(Constants.MAX_CODE_SIZE - evm.return_data_len);
        let code_deposit_cost = Gas.CODE_DEPOSIT * evm.return_data_len;
        let enough_gas = is_nn(evm.gas_left - code_deposit_cost);
        // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-3540.md
        if (evm.return_data_len == 0) {
            tempvar is_prefix_not_0xef = TRUE;
        } else {
            tempvar is_prefix_not_0xef = is_not_zero(0xef - [evm.return_data]);
        }

        let success = enough_gas * code_size_limit * is_prefix_not_0xef;

        if (success == 0) {
            // Reverts and burn all gas
            let (revert_reason_len, revert_reason) = Errors.outOfGas(
                evm.gas_left, code_deposit_cost
            );
            tempvar evm = new model.EVM(
                message=evm.message,
                return_data_len=revert_reason_len,
                return_data=revert_reason,
                program_counter=evm.program_counter,
                stopped=TRUE,
                gas_left=0,
                gas_refund=0,
                reverted=Errors.EXCEPTIONAL_HALT,
            );
            return evm;
        }

        // Write bytecode and cache the final code valid jumpdests to Account
        let account = State.get_account(evm.message.address);
        let account = Account.set_code(account, evm.return_data_len, evm.return_data);

        State.update_account(evm.message.address, account);
        State.finalize();

        // Update gas and return data - we know gas_left > code_deposit_cost
        tempvar evm = new model.EVM(
            message=evm.message,
            return_data_len=evm.return_data_len,
            return_data=evm.return_data,
            program_counter=evm.program_counter,
            stopped=evm.stopped,
            gas_left=evm.gas_left - code_deposit_cost,
            gas_refund=evm.gas_refund,
            reverted=evm.reverted,
        );

        return evm;
    }
}
