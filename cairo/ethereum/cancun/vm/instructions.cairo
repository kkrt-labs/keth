from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin, PoseidonBuiltin
from starkware.cairo.common.alloc import alloc
from ethereum.cancun.vm import Evm, EvmStruct, EvmImpl
from ethereum.cancun.vm.exceptions import Revert, EthereumException, InvalidOpcode
from ethereum_types.numeric import Uint
from ethereum_types.bytes import Bytes, BytesStruct
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
from ethereum.cancun.vm.instructions.keccak import keccak as keccak_instruction
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
from ethereum.cancun.vm.instructions.storage import sload, sstore, tload, tstore
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
from ethereum.cancun.vm.instructions.system import return_, revert, create, create2
from ethereum.cancun.vm.instructions.environment import (
    address,
    balance,
    origin,
    caller,
    callvalue,
    calldataload,
    calldatasize,
    calldatacopy,
    codesize,
    codecopy,
    gasprice,
    extcodesize,
    extcodecopy,
    returndatasize,
    returndatacopy,
    extcodehash,
    self_balance,
    base_fee,
    blob_hash,
    blob_base_fee,
)

func op_implementation{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}(
    process_create_message_label: felt*, process_message_label: felt*, opcode: felt
) -> EthereumException* {
    // call opcode
    // count 1 for "next line" and 4 steps per opcode: call, opcode, ret
    tempvar offset = opcode * 3 + 1;

    // Prepare arguments
    [ap] = process_create_message_label, ap++;
    [ap] = process_message_label, ap++;
    [ap] = range_check_ptr, ap++;
    [ap] = bitwise_ptr, ap++;
    [ap] = keccak_ptr, ap++;
    [ap] = poseidon_ptr, ap++;
    [ap] = evm.value, ap++;

    jmp rel offset;
    call stop;  // 0x0
    ret;
    call add;  // 0x1 - ADD
    ret;
    call mul;  // 0x2 - MUL
    ret;
    call sub;  // 0x3 - SUB
    ret;
    call div;  // 0x4 - DIV
    ret;
    call sdiv;  // 0x5 - SDIV
    ret;
    call mod;  // 0x6 - MOD
    ret;
    call smod;  // 0x7 - SMOD
    ret;
    call addmod;  // 0x8 - ADDMOD
    ret;
    call mulmod;  // 0x9 - MULMOD
    ret;
    call exp;  // 0xa - EXP
    ret;
    call signextend;  // 0xb - SIGNEXTEND
    ret;
    call unknown_opcode;  // 0xc
    ret;
    call unknown_opcode;  // 0xd
    ret;
    call unknown_opcode;  // 0xe
    ret;
    call unknown_opcode;  // 0xf
    ret;
    call less_than;  // 0x10 - LT
    ret;
    call greater_than;  // 0x11 - GT
    ret;
    call signed_less_than;  // 0x12 - SLT
    ret;
    call signed_greater_than;  // 0x13 - SGT
    ret;
    call equal;  // 0x14 - EQ
    ret;
    call is_zero;  // 0x15 - ISZERO
    ret;
    call bitwise_and;  // 0x16 - AND
    ret;
    call bitwise_or;  // 0x17 - OR
    ret;
    call bitwise_xor;  // 0x18 - XOR
    ret;
    call bitwise_not;  // 0x19 - NOT
    ret;
    call get_byte;  // 0x1a - BYTE
    ret;
    call bitwise_shl;  // 0x1b - SHL
    ret;
    call bitwise_shr;  // 0x1c - SHR
    ret;
    call bitwise_sar;  // 0x1d - SAR
    ret;
    call unknown_opcode;  // 0x1e
    ret;
    call unknown_opcode;  // 0x1f
    ret;
    call keccak_instruction;  // 0x20 - KECCAK
    ret;
    call unknown_opcode;  // 0x21
    ret;
    call unknown_opcode;  // 0x22
    ret;
    call unknown_opcode;  // 0x23
    ret;
    call unknown_opcode;  // 0x24
    ret;
    call unknown_opcode;  // 0x25
    ret;
    call unknown_opcode;  // 0x26
    ret;
    call unknown_opcode;  // 0x27
    ret;
    call unknown_opcode;  // 0x28
    ret;
    call unknown_opcode;  // 0x29
    ret;
    call unknown_opcode;  // 0x2a
    ret;
    call unknown_opcode;  // 0x2b
    ret;
    call unknown_opcode;  // 0x2c
    ret;
    call unknown_opcode;  // 0x2d
    ret;
    call unknown_opcode;  // 0x2e
    ret;
    call unknown_opcode;  // 0x2f
    ret;
    call address;  // 0x30 - ADDRESS
    ret;
    call balance;  // 0x31 - BALANCE
    ret;
    call origin;  // 0x32 - ORIGIN
    ret;
    call caller;  // 0x33 - CALLER
    ret;
    call callvalue;  // 0x34 - CALLVALUE
    ret;
    call calldataload;  // 0x35 - CALLDATALOAD
    ret;
    call calldatasize;  // 0x36 - CALLDATASIZE
    ret;
    call calldatacopy;  // 0x37 - CALLDATACOPY
    ret;
    call codesize;  // 0x38 - CODESIZE
    ret;
    call codecopy;  // 0x39 - CODECOPY
    ret;
    call gasprice;  // 0x3a - GASPRICE
    ret;
    call extcodesize;  // 0x3b - EXTCODESIZE
    ret;
    call extcodecopy;  // 0x3c - EXTCODECOPY
    ret;
    call returndatasize;  // 0x3d - RETURNDATASIZE
    ret;
    call returndatacopy;  // 0x3e - RETURNDATACOPY
    ret;
    call extcodehash;  // 0x3f - EXTCODEHASH
    ret;
    call block_hash;  // 0x40 - BLOCKHASH
    ret;
    call coinbase;  // 0x41 - COINBASE
    ret;
    call timestamp;  // 0x42 - TIMESTAMP
    ret;
    call number;  // 0x43 - NUMBER
    ret;
    call prev_randao;  // 0x44 - PREVRANDAO
    ret;
    call gas_limit;  // 0x45 - GASLIMIT
    ret;
    call chain_id;  // 0x46 - CHAINID
    ret;
    call self_balance;  // 0x47 - SELFBALANCE
    ret;
    call base_fee;  // 0x48 - BASEFEE
    ret;
    call blob_hash;  // 0x49 - BLOBHASH
    ret;
    call blob_base_fee;  // 0x4a - BLOBBASEFEE
    ret;
    call unknown_opcode;  // 0x4b
    ret;
    call unknown_opcode;  // 0x4c
    ret;
    call unknown_opcode;  // 0x4d
    ret;
    call unknown_opcode;  // 0x4e
    ret;
    call unknown_opcode;  // 0x4f
    ret;
    call pop;  // 0x50 - POP
    ret;
    call mload;  // 0x51 - MLOAD
    ret;
    call mstore;  // 0x52 - MSTORE
    ret;
    call mstore8;  // 0x53 - MSTORE8
    ret;
    call sload;  // 0x54 - SLOAD
    ret;
    call sstore;  // 0x55 - SSTORE
    ret;
    call jump;  // 0x56 - JUMP
    ret;
    call jumpi;  // 0x57 - JUMPI
    ret;
    call pc;  // 0x58 - PC
    ret;
    call msize;  // 0x59 - MSIZE
    ret;
    call gas_left;  // 0x5a - GAS
    ret;
    call jumpdest;  // 0x5b - JUMPDEST
    ret;
    call tload;  // 0x5c - TLOAD
    ret;
    call tstore;  // 0x5d - TSTORE
    ret;
    call mcopy;  // 0x5e - MCOPY
    ret;
    call push0;  // 0x5f - PUSH0
    ret;
    call push1;  // 0x60 - PUSH1
    ret;
    call push2;  // 0x61 - PUSH2
    ret;
    call push3;  // 0x62 - PUSH3
    ret;
    call push4;  // 0x63 - PUSH4
    ret;
    call push5;  // 0x64 - PUSH5
    ret;
    call push6;  // 0x65 - PUSH6
    ret;
    call push7;  // 0x66 - PUSH7
    ret;
    call push8;  // 0x67 - PUSH8
    ret;
    call push9;  // 0x68 - PUSH9
    ret;
    call push10;  // 0x69 - PUSH10
    ret;
    call push11;  // 0x6a - PUSH11
    ret;
    call push12;  // 0x6b - PUSH12
    ret;
    call push13;  // 0x6c - PUSH13
    ret;
    call push14;  // 0x6d - PUSH14
    ret;
    call push15;  // 0x6e - PUSH15
    ret;
    call push16;  // 0x6f - PUSH16
    ret;
    call push17;  // 0x70 - PUSH17
    ret;
    call push18;  // 0x71 - PUSH18
    ret;
    call push19;  // 0x72 - PUSH19
    ret;
    call push20;  // 0x73 - PUSH20
    ret;
    call push21;  // 0x74 - PUSH21
    ret;
    call push22;  // 0x75 - PUSH22
    ret;
    call push23;  // 0x76 - PUSH23
    ret;
    call push24;  // 0x77 - PUSH24
    ret;
    call push25;  // 0x78 - PUSH25
    ret;
    call push26;  // 0x79 - PUSH26
    ret;
    call push27;  // 0x7a - PUSH27
    ret;
    call push28;  // 0x7b - PUSH28
    ret;
    call push29;  // 0x7c - PUSH29
    ret;
    call push30;  // 0x7d - PUSH30
    ret;
    call push31;  // 0x7e - PUSH31
    ret;
    call push32;  // 0x7f - PUSH32
    ret;
    call dup1;  // 0x80 - DUP1
    ret;
    call dup2;  // 0x81 - DUP2
    ret;
    call dup3;  // 0x82 - DUP3
    ret;
    call dup4;  // 0x83 - DUP4
    ret;
    call dup5;  // 0x84 - DUP5
    ret;
    call dup6;  // 0x85 - DUP6
    ret;
    call dup7;  // 0x86 - DUP7
    ret;
    call dup8;  // 0x87 - DUP8
    ret;
    call dup9;  // 0x88 - DUP9
    ret;
    call dup10;  // 0x89 - DUP10
    ret;
    call dup11;  // 0x8a - DUP11
    ret;
    call dup12;  // 0x8b - DUP12
    ret;
    call dup13;  // 0x8c - DUP13
    ret;
    call dup14;  // 0x8d - DUP14
    ret;
    call dup15;  // 0x8e - DUP15
    ret;
    call dup16;  // 0x8f - DUP16
    ret;
    call swap1;  // 0x90 - SWAP1
    ret;
    call swap2;  // 0x91 - SWAP2
    ret;
    call swap3;  // 0x92 - SWAP3
    ret;
    call swap4;  // 0x93 - SWAP4
    ret;
    call swap5;  // 0x94 - SWAP5
    ret;
    call swap6;  // 0x95 - SWAP6
    ret;
    call swap7;  // 0x96 - SWAP7
    ret;
    call swap8;  // 0x97 - SWAP8
    ret;
    call swap9;  // 0x98 - SWAP9
    ret;
    call swap10;  // 0x99 - SWAP10
    ret;
    call swap11;  // 0x9a - SWAP11
    ret;
    call swap12;  // 0x9b - SWAP12
    ret;
    call swap13;  // 0x9c - SWAP13
    ret;
    call swap14;  // 0x9d - SWAP14
    ret;
    call swap15;  // 0x9e - SWAP15
    ret;
    call swap16;  // 0x9f - SWAP16
    ret;
    call log0;  // 0xa0 - LOG0
    ret;
    call log1;  // 0xa1 - LOG1
    ret;
    call log2;  // 0xa2 - LOG2
    ret;
    call log3;  // 0xa3 - LOG3
    ret;
    call log4;  // 0xa4 - LOG4
    ret;
    call unknown_opcode;  // 0xa5
    ret;
    call unknown_opcode;  // 0xa6
    ret;
    call unknown_opcode;  // 0xa7
    ret;
    call unknown_opcode;  // 0xa8
    ret;
    call unknown_opcode;  // 0xa9
    ret;
    call unknown_opcode;  // 0xaa
    ret;
    call unknown_opcode;  // 0xab
    ret;
    call unknown_opcode;  // 0xac
    ret;
    call unknown_opcode;  // 0xad
    ret;
    call unknown_opcode;  // 0xae
    ret;
    call unknown_opcode;  // 0xaf
    ret;
    call unknown_opcode;  // 0xb0
    ret;
    call unknown_opcode;  // 0xb1
    ret;
    call unknown_opcode;  // 0xb2
    ret;
    call unknown_opcode;  // 0xb3
    ret;
    call unknown_opcode;  // 0xb4
    ret;
    call unknown_opcode;  // 0xb5
    ret;
    call unknown_opcode;  // 0xb6
    ret;
    call unknown_opcode;  // 0xb7
    ret;
    call unknown_opcode;  // 0xb8
    ret;
    call unknown_opcode;  // 0xb9
    ret;
    call unknown_opcode;  // 0xba
    ret;
    call unknown_opcode;  // 0xbb
    ret;
    call unknown_opcode;  // 0xbc
    ret;
    call unknown_opcode;  // 0xbd
    ret;
    call unknown_opcode;  // 0xbe
    ret;
    call unknown_opcode;  // 0xbf
    ret;
    call unknown_opcode;  // 0xc0
    ret;
    call unknown_opcode;  // 0xc1
    ret;
    call unknown_opcode;  // 0xc2
    ret;
    call unknown_opcode;  // 0xc3
    ret;
    call unknown_opcode;  // 0xc4
    ret;
    call unknown_opcode;  // 0xc5
    ret;
    call unknown_opcode;  // 0xc6
    ret;
    call unknown_opcode;  // 0xc7
    ret;
    call unknown_opcode;  // 0xc8
    ret;
    call unknown_opcode;  // 0xc9
    ret;
    call unknown_opcode;  // 0xca
    ret;
    call unknown_opcode;  // 0xcb
    ret;
    call unknown_opcode;  // 0xcc
    ret;
    call unknown_opcode;  // 0xcd
    ret;
    call unknown_opcode;  // 0xce
    ret;
    call unknown_opcode;  // 0xcf
    ret;
    call unknown_opcode;  // 0xd0
    ret;
    call unknown_opcode;  // 0xd1
    ret;
    call unknown_opcode;  // 0xd2
    ret;
    call unknown_opcode;  // 0xd3
    ret;
    call unknown_opcode;  // 0xd4
    ret;
    call unknown_opcode;  // 0xd5
    ret;
    call unknown_opcode;  // 0xd6
    ret;
    call unknown_opcode;  // 0xd7
    ret;
    call unknown_opcode;  // 0xd8
    ret;
    call unknown_opcode;  // 0xd9
    ret;
    call unknown_opcode;  // 0xda
    ret;
    call unknown_opcode;  // 0xdb
    ret;
    call unknown_opcode;  // 0xdc
    ret;
    call unknown_opcode;  // 0xdd
    ret;
    call unknown_opcode;  // 0xde
    ret;
    call unknown_opcode;  // 0xdf
    ret;
    call unknown_opcode;  // 0xe0
    ret;
    call unknown_opcode;  // 0xe1
    ret;
    call unknown_opcode;  // 0xe2
    ret;
    call unknown_opcode;  // 0xe3
    ret;
    call unknown_opcode;  // 0xe4
    ret;
    call unknown_opcode;  // 0xe5
    ret;
    call unknown_opcode;  // 0xe6
    ret;
    call unknown_opcode;  // 0xe7
    ret;
    call unknown_opcode;  // 0xe8
    ret;
    call unknown_opcode;  // 0xe9
    ret;
    call unknown_opcode;  // 0xea
    ret;
    call unknown_opcode;  // 0xeb
    ret;
    call unknown_opcode;  // 0xec
    ret;
    call unknown_opcode;  // 0xed
    ret;
    call unknown_opcode;  // 0xee
    ret;
    call unknown_opcode;  // 0xef
    ret;
    call create;  // 0xf0 //TODO: create
    ret;
    call unknown_opcode;  // 0xf1 //TODO: call
    ret;
    call unknown_opcode;  // 0xf2 //TODO: callcode
    ret;
    call return_;  // 0xf3 - RETURN
    ret;
    call unknown_opcode;  // 0xf4 //TODO: delegatecall
    ret;
    call create2;  // 0xf5 - CREATE2
    ret;
    call unknown_opcode;  // 0xf6
    ret;
    call unknown_opcode;  // 0xf7
    ret;
    call unknown_opcode;  // 0xf8
    ret;
    call unknown_opcode;  // 0xf9
    ret;
    call unknown_opcode;  // 0xfa: TODO: staticcall
    ret;
    call unknown_opcode;  // 0xfb
    ret;
    call unknown_opcode;  // 0xfc
    ret;
    call revert;  // 0xfd
    ret;
    call unknown_opcode;  // 0xfe
    ret;
    call unknown_opcode;  // 0xff TODO: selfdestruct
    ret;
}

func unknown_opcode{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    tempvar err = new EthereumException(InvalidOpcode);
    return err;
}
