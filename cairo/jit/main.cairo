from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc

// Compiled Instructions
const CALL_ABS = 0x1084800180018000;

// Modified return instruction to update the offset of return_pc.
// Putting an offset >= 0 let's dynamically chose where to return.
// Offset = -1 is the default ret opcode.
const RET_HIGH = 0x208b7fff;
const RET_LOW = 0x7fff7ffe;
const RET = RET_HIGH * 256 ** 4 + RET_LOW;
const RET_0 = (RET_HIGH + 1) * 256 ** 4 + RET_LOW;

// Bytecode Opcode
const OP_JUMP4 = 0;
const OP_RET = 1;
const OP_PUSH = 2;
const OP_PC = 3;
const OP_CALL = 4;
const OP_ADD = 5;
const OP_MUL = 6;

func compile(input: felt, code_len: felt, code_ptr: felt*) -> (
    compiled_code_len: felt, compiled_code_ptr: felt*
) {
    alloc_locals;
    let (local op: felt*) = get_label_location(opcodes_location);
    let (local compiled_code) = alloc();
    if (code_len == 0) {
        return (0, compiled_code);
    }

    tempvar i = 0;
    tempvar compiled_code = compiled_code;

    loop:
    let i = [ap - 2];
    let compiled_code = cast([ap - 1], felt*);

    let code_len = [fp - 4];
    let code = cast([fp - 3], felt*);
    let op = cast([fp], felt*);

    tempvar opcode_number = code[i];
    assert [compiled_code] = CALL_ABS;
    assert [compiled_code + 1] = cast(op + 2 * opcode_number + op[2 * opcode_number + 1], felt);

    tempvar is_push = opcode_number - OP_PUSH;
    jmp not_push if is_push != 0;

    push:
    assert [compiled_code + 3] = code[i + 1];
    tempvar stop = code_len - i - 2;
    tempvar i = i + 2;
    tempvar compiled_code = compiled_code + 4;
    jmp loop if stop != 0;
    jmp end;

    not_push:
    tempvar stop = code_len - i - 1;
    tempvar i = i + 1;
    tempvar compiled_code = compiled_code + 2;

    static_assert i == [ap - 2];
    static_assert compiled_code == [ap - 1];
    jmp loop if stop != 0;
    jmp end;

    end:
    let i = [ap - 2];
    let compiled_code = cast([ap - 1], felt*);
    assert [compiled_code] = RET;

    let compiled_code = cast([fp + 1], felt*);

    return (i, compiled_code);
}

func main() {
    alloc_locals;

    let (bytecode_start) = alloc();
    let bytecode = bytecode_start;
    assert [bytecode] = OP_JUMP4;
    let bytecode = bytecode + 1;
    assert [bytecode] = OP_RET;
    let bytecode = bytecode + 1;
    assert [bytecode] = OP_RET;
    let bytecode = bytecode + 1;
    assert [bytecode] = OP_RET;
    let bytecode = bytecode + 1;
    assert [bytecode] = OP_RET;
    let bytecode = bytecode + 1;
    assert [bytecode] = OP_PUSH;
    let bytecode = bytecode + 1;
    assert [bytecode] = OP_PC;
    let bytecode = bytecode + 1;
    assert [bytecode] = OP_PC;
    let bytecode = bytecode + 1;
    assert [bytecode] = OP_CALL;
    let bytecode = bytecode + 1;
    assert [bytecode] = OP_ADD;
    let bytecode = bytecode + 1;
    assert [bytecode] = OP_MUL;
    let bytecode = bytecode + 1;
    assert [bytecode] = OP_RET;

    tempvar input = 0xdead;
    let (compiled_code_len, compiled_code_ptr) = compile(
        input, bytecode - bytecode_start, bytecode_start
    );

    call abs compiled_code_ptr;
    let result = [ap - 1];
    assert result = 2;

    return ();
}

func op_jump(input: felt) -> felt {
    alloc_locals;
    local return_pc;
    tempvar jump_size = 4;
    assert return_pc = [fp - 1] + 2 * jump_size;

    tempvar result = 0;

    dw RET_0;
}

func op_ret(input: felt) -> felt {
    alloc_locals;
    local main_return_pc;

    let return_fp = [fp - 2];
    main_return_pc = [return_fp - 1];

    tempvar result = input;
    dw RET_0;
}

func op_push(input: felt) -> felt {
    alloc_locals;
    // [fp - 1] is next CALL_ABS instruction
    // [[fp - 1] + 1] is the word to push
    // [fp - 1] + 2 where to move the PC after the push
    local return_pc = [fp - 1] + 2;
    tempvar word = [[fp - 1] + 1];

    dw RET_0;
}

func op_pc(input: felt) -> felt {
    let return_pc = [fp - 1];
    let calling_pc = return_pc - 2;
    let return_fp = [fp - 2];
    let main_return_fp = [return_fp - 2];
    let compiled_code_ptr = [return_fp - 3];

    return (calling_pc - compiled_code_ptr) / 2;
}

func op_call(input: felt) -> felt {
    let (bytecode_start) = alloc();
    let bytecode = bytecode_start;
    assert [bytecode] = OP_PC;
    let bytecode = bytecode + 1;
    assert [bytecode] = OP_RET;

    let (compiled_code_len, compiled_code_ptr) = compile(
        input, bytecode - bytecode_start, bytecode_start
    );

    call abs compiled_code_ptr;
    ret;
}

func op_add(input: felt) -> felt {
    let result = input + 1;
    return result;
}

func op_mul(input: felt) -> felt {
    let result = input * 2;
    return result;
}

// Create a label and a list of call rel op to be able to get all the opcodes locations
// with a single call to get_label_location.
opcodes_location:
call op_jump;
call op_ret;
call op_push;
call op_pc;
call op_call;
call op_add;
call op_mul;
