from ethereum.cancun.vm.instructions.arithmetic import (
    add,
    mul,
    sub,
    div,
    sdiv,
    mod,
    smod,
    addmod,
    mulmod,
    exp,
    signextend,
)
from ethereum.cancun.vm.instructions.comparison import (
    less_than,
    greater_than,
    signed_less_than,
    signed_greater_than,
    equal,
    is_zero,
)
from ethereum.cancun.vm.instructions.bitwise import (
    bitwise_and,
    bitwise_or,
    bitwise_xor,
    bitwise_not,
    get_byte,
    bitwise_shl,
    bitwise_shr,
    bitwise_sar,
)
from ethereum.cancun.vm.instructions.keccak import keccak
from ethereum.cancun.vm.instructions.block import (
    block_hash,
    coinbase,
    timestamp,
    number,
    prev_randao,
    gas_limit,
    chain_id,
)
from ethereum.cancun.vm.instructions.control_flow import stop, jump, jumpi, pc, gas_left, jumpdest
// from ethereum.cancun.vm.instructions.storage import sload, sstore, tload, tstore
from ethereum.cancun.vm.instructions.stack_instructions import pop
from ethereum.cancun.vm.instructions.stack_instructions import (
    push0,
    push1,
    push2,
    push3,
    push4,
    push5,
    push6,
    push7,
    push8,
    push9,
    push10,
    push11,
    push12,
    push13,
    push14,
    push15,
    push16,
    push17,
    push18,
    push19,
    push20,
    push21,
    push22,
    push23,
    push24,
    push25,
    push26,
    push27,
    push28,
    push29,
    push30,
    push31,
    push32,
)
from ethereum.cancun.vm.instructions.stack_instructions import (
    dup1,
    dup2,
    dup3,
    dup4,
    dup5,
    dup6,
    dup7,
    dup8,
    dup9,
    dup10,
    dup11,
    dup12,
    dup13,
    dup14,
    dup15,
    dup16,
)
from ethereum.cancun.vm.instructions.stack_instructions import (
    swap1,
    swap2,
    swap3,
    swap4,
    swap5,
    swap6,
    swap7,
    swap8,
    swap9,
    swap10,
    swap11,
    swap12,
    swap13,
    swap14,
    swap15,
    swap16,
)
from ethereum.cancun.vm.instructions.memory_instructions import mstore, mstore8, mload, msize, mcopy
from ethereum.cancun.vm.instructions.log import log0, log1, log2, log3, log4
// from ethereum.cancun.vm.instructions.system

func op_implementation(opcode: felt) {
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
