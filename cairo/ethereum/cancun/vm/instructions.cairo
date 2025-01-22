from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin, PoseidonBuiltin
from starkware.cairo.common.alloc import alloc
from ethereum.cancun.vm import Evm, EvmStruct, EvmImpl
from ethereum.cancun.vm.exceptions import Revert, EthereumException
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
from ethereum.cancun.vm.instructions.system import revert
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
}(opcode: felt) -> EthereumException* {
    // call opcode
    // count 1 for "next line" and 4 steps per opcode: call, opcode, jmp, end
    tempvar offset = opcode * 4 + 1;

    // Prepare arguments
    [ap] = range_check_ptr, ap++;
    [ap] = bitwise_ptr, ap++;
    [ap] = keccak_ptr, ap++;
    [ap] = poseidon_ptr, ap++;
    [ap] = evm.value, ap++;

    jmp rel offset;
    call stop;  // 0x0
    jmp end;
    call add;  // 0x1 - ADD
    jmp end;
    call mul;  // 0x2 - MUL
    jmp end;
    call sub;  // 0x3 - SUB
    jmp end;
    call div;  // 0x4 - DIV
    jmp end;
    call sdiv;  // 0x5 - SDIV
    jmp end;
    call mod;  // 0x6 - MOD
    jmp end;
    call smod;  // 0x7 - SMOD
    jmp end;
    call addmod;  // 0x8 - ADDMOD
    jmp end;
    call mulmod;  // 0x9 - MULMOD
    jmp end;
    call exp;  // 0xa - EXP
    jmp end;
    call signextend;  // 0xb - SIGNEXTEND
    jmp end;
    call unknown_opcode;  // 0xc
    jmp end;
    call unknown_opcode;  // 0xd
    jmp end;
    call unknown_opcode;  // 0xe
    jmp end;
    call unknown_opcode;  // 0xf
    jmp end;
    call less_than;  // 0x10 - LT
    jmp end;
    call greater_than;  // 0x11 - GT
    jmp end;
    call signed_less_than;  // 0x12 - SLT
    jmp end;
    call signed_greater_than;  // 0x13 - SGT
    jmp end;
    call equal;  // 0x14 - EQ
    jmp end;
    call is_zero;  // 0x15 - ISZERO
    jmp end;
    call bitwise_and;  // 0x16 - AND
    jmp end;
    call bitwise_or;  // 0x17 - OR
    jmp end;
    call bitwise_xor;  // 0x18 - XOR
    jmp end;
    call bitwise_not;  // 0x19 - NOT
    jmp end;
    call get_byte;  // 0x1a - BYTE
    jmp end;
    call bitwise_shl;  // 0x1b - SHL
    jmp end;
    call bitwise_shr;  // 0x1c - SHR
    jmp end;
    call bitwise_sar;  // 0x1d - SAR
    jmp end;
    call unknown_opcode;  // 0x1e
    jmp end;
    call unknown_opcode;  // 0x1f
    jmp end;
    call keccak;  // 0x20 - KECCAK
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
    call address;  // 0x30 - ADDRESS
    jmp end;
    call balance;  // 0x31 - BALANCE
    jmp end;
    call origin;  // 0x32 - ORIGIN
    jmp end;
    call caller;  // 0x33 - CALLER
    jmp end;
    call callvalue;  // 0x34 - CALLVALUE
    jmp end;
    call calldataload;  // 0x35 - CALLDATALOAD
    jmp end;
    call calldatasize;  // 0x36 - CALLDATASIZE
    jmp end;
    call calldatacopy;  // 0x37 - CALLDATACOPY
    jmp end;
    call codesize;  // 0x38 - CODESIZE
    jmp end;
    call codecopy;  // 0x39 - CODECOPY
    jmp end;
    call gasprice;  // 0x3a - GASPRICE
    jmp end;
    call extcodesize;  // 0x3b - EXTCODESIZE
    jmp end;
    call extcodecopy;  // 0x3c - EXTCODECOPY
    jmp end;
    call returndatasize;  // 0x3d - RETURNDATASIZE
    jmp end;
    call returndatacopy;  // 0x3e - RETURNDATACOPY
    jmp end;
    call extcodehash;  // 0x3f - EXTCODEHASH
    jmp end;
    call block_hash;  // 0x40 - BLOCKHASH
    jmp end;
    call coinbase;  // 0x41 - COINBASE
    jmp end;
    call timestamp;  // 0x42 - TIMESTAMP
    jmp end;
    call number;  // 0x43 - NUMBER
    jmp end;
    call prev_randao;  // 0x44 - PREVRANDAO
    jmp end;
    call gas_limit;  // 0x45 - GASLIMIT
    jmp end;
    call chain_id;  // 0x46 - CHAINID
    jmp end;
    call self_balance;  // 0x47 - SELFBALANCE
    jmp end;
    call base_fee;  // 0x48 - BASEFEE
    jmp end;
    call blob_hash;  // 0x49 - BLOBHASH
    jmp end;
    call blob_base_fee;  // 0x4a - BLOBBASEFEE
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
    call pop;  // 0x50 - POP
    jmp end;
    call mload;  // 0x51 - MLOAD
    jmp end;
    call mstore;  // 0x52 - MSTORE
    jmp end;
    call mstore8;  // 0x53 - MSTORE8
    jmp end;
    call sload;  // 0x54 - SLOAD
    jmp end;
    call sstore;  // 0x55 - SSTORE
    jmp end;
    call jump;  // 0x56 - JUMP
    jmp end;
    call jumpi;  // 0x57 - JUMPI
    jmp end;
    call pc;  // 0x58 - PC
    jmp end;
    call msize;  // 0x59 - MSIZE
    jmp end;
    call gas_left;  // 0x5a - GAS
    jmp end;
    call jumpdest;  // 0x5b - JUMPDEST
    jmp end;
    call tload;  // 0x5c - TLOAD
    jmp end;
    call tstore;  // 0x5d - TSTORE
    jmp end;
    call mcopy;  // 0x5e - MCOPY
    jmp end;
    call push0;  // 0x5f - PUSH0
    jmp end;
    call push1;  // 0x60 - PUSH1
    jmp end;
    call push2;  // 0x61 - PUSH2
    jmp end;
    call push3;  // 0x62 - PUSH3
    jmp end;
    call push4;  // 0x63 - PUSH4
    jmp end;
    call push5;  // 0x64 - PUSH5
    jmp end;
    call push6;  // 0x65 - PUSH6
    jmp end;
    call push7;  // 0x66 - PUSH7
    jmp end;
    call push8;  // 0x67 - PUSH8
    jmp end;
    call push9;  // 0x68 - PUSH9
    jmp end;
    call push10;  // 0x69 - PUSH10
    jmp end;
    call push11;  // 0x6a - PUSH11
    jmp end;
    call push12;  // 0x6b - PUSH12
    jmp end;
    call push13;  // 0x6c - PUSH13
    jmp end;
    call push14;  // 0x6d - PUSH14
    jmp end;
    call push15;  // 0x6e - PUSH15
    jmp end;
    call push16;  // 0x6f - PUSH16
    jmp end;
    call push17;  // 0x70 - PUSH17
    jmp end;
    call push18;  // 0x71 - PUSH18
    jmp end;
    call push19;  // 0x72 - PUSH19
    jmp end;
    call push20;  // 0x73 - PUSH20
    jmp end;
    call push21;  // 0x74 - PUSH21
    jmp end;
    call push22;  // 0x75 - PUSH22
    jmp end;
    call push23;  // 0x76 - PUSH23
    jmp end;
    call push24;  // 0x77 - PUSH24
    jmp end;
    call push25;  // 0x78 - PUSH25
    jmp end;
    call push26;  // 0x79 - PUSH26
    jmp end;
    call push27;  // 0x7a - PUSH27
    jmp end;
    call push28;  // 0x7b - PUSH28
    jmp end;
    call push29;  // 0x7c - PUSH29
    jmp end;
    call push30;  // 0x7d - PUSH30
    jmp end;
    call push31;  // 0x7e - PUSH31
    jmp end;
    call push32;  // 0x7f - PUSH32
    jmp end;
    call dup1;  // 0x80 - DUP1
    jmp end;
    call dup2;  // 0x81 - DUP2
    jmp end;
    call dup3;  // 0x82 - DUP3
    jmp end;
    call dup4;  // 0x83 - DUP4
    jmp end;
    call dup5;  // 0x84 - DUP5
    jmp end;
    call dup6;  // 0x85 - DUP6
    jmp end;
    call dup7;  // 0x86 - DUP7
    jmp end;
    call dup8;  // 0x87 - DUP8
    jmp end;
    call dup9;  // 0x88 - DUP9
    jmp end;
    call dup10;  // 0x89 - DUP10
    jmp end;
    call dup11;  // 0x8a - DUP11
    jmp end;
    call dup12;  // 0x8b - DUP12
    jmp end;
    call dup13;  // 0x8c - DUP13
    jmp end;
    call dup14;  // 0x8d - DUP14
    jmp end;
    call dup15;  // 0x8e - DUP15
    jmp end;
    call dup16;  // 0x8f - DUP16
    jmp end;
    call swap1;  // 0x90 - SWAP1
    jmp end;
    call swap2;  // 0x91 - SWAP2
    jmp end;
    call swap3;  // 0x92 - SWAP3
    jmp end;
    call swap4;  // 0x93 - SWAP4
    jmp end;
    call swap5;  // 0x94 - SWAP5
    jmp end;
    call swap6;  // 0x95 - SWAP6
    jmp end;
    call swap7;  // 0x96 - SWAP7
    jmp end;
    call swap8;  // 0x97 - SWAP8
    jmp end;
    call swap9;  // 0x98 - SWAP9
    jmp end;
    call swap10;  // 0x99 - SWAP10
    jmp end;
    call swap11;  // 0x9a - SWAP11
    jmp end;
    call swap12;  // 0x9b - SWAP12
    jmp end;
    call swap13;  // 0x9c - SWAP13
    jmp end;
    call swap14;  // 0x9d - SWAP14
    jmp end;
    call swap15;  // 0x9e - SWAP15
    jmp end;
    call swap16;  // 0x9f - SWAP16
    jmp end;
    call log0;  // 0xa0 - LOG0
    jmp end;
    call log1;  // 0xa1 - LOG1
    jmp end;
    call log2;  // 0xa2 - LOG2
    jmp end;
    call log3;  // 0xa3 - LOG3
    jmp end;
    call log4;  // 0xa4 - LOG4
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
    call unknown_opcode;  // 0xf0 //TODO: create
    jmp end;
    call unknown_opcode;  // 0xf1 //TODO: call
    jmp end;
    call unknown_opcode;  // 0xf2 //TODO: callcode
    jmp end;
    call unknown_opcode;  // 0xf3 //TODO: return
    jmp end;
    call unknown_opcode;  // 0xf4 //TODO: delegatecall
    jmp end;
    call unknown_opcode;  // 0xf5 //TODO: create2
    jmp end;
    call unknown_opcode;  // 0xf6
    jmp end;
    call unknown_opcode;  // 0xf7
    jmp end;
    call unknown_opcode;  // 0xf8
    jmp end;
    call unknown_opcode;  // 0xf9
    jmp end;
    call unknown_opcode;  // 0xfa: TODO: staticcall
    jmp end;
    call unknown_opcode;  // 0xfb
    jmp end;
    call unknown_opcode;  // 0xfc
    jmp end;
    call revert;  // 0xfd
    jmp end;
    call unknown_opcode;  // 0xfe
    jmp end;
    call unknown_opcode;  // 0xff TODO: selfdestruct
    jmp end;

    end:
    let range_check_ptr = [ap - 6];
    let bitwise_ptr = cast([ap - 5], BitwiseBuiltin*);
    let keccak_ptr = cast([ap - 4], KeccakBuiltin*);
    let poseidon_ptr = cast([ap - 3], PoseidonBuiltin*);
    let evm_ = cast([ap - 2], EvmStruct*);
    let evm = Evm(evm_);
    let error = cast([ap - 1], EthereumException*);

    return error;
}

func unknown_opcode{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() {
    with_attr error_message("ValueError") {
        assert 1 = 0;
    }
    return ();
}
