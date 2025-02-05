from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.default_dict import default_dict_new
from starkware.cairo.common.dict_access import DictAccess

from ethereum_types.bytes import Bytes, BytesStruct
from ethereum_types.numeric import SetUint, SetUintStruct, SetUintDictAccess

from src.utils.utils import Helpers
from src.utils.dict import dict_write

func get_valid_jump_destinations{range_check_ptr}(code: Bytes) -> SetUint {
    alloc_locals;
    let (local valid_jumpdests_start: DictAccess*) = default_dict_new(0);
    tempvar code_len = code.value.len;
    tempvar range_check_ptr = range_check_ptr;
    tempvar valid_jumpdests = valid_jumpdests_start;
    tempvar i = 0;
    jmp body if code_len != 0;

    static_assert range_check_ptr == [ap - 3];
    jmp end;

    body:
    let bytecode = cast([fp - 3], BytesStruct*);
    let range_check_ptr = [ap - 3];
    let valid_jumpdests = cast([ap - 2], DictAccess*);
    let i = [ap - 1];

    with_attr error_message("Reading out of bounds bytecode") {
        assert [range_check_ptr] = bytecode.len - 1 - i;
    }
    let range_check_ptr = range_check_ptr + 1;

    tempvar opcode = [bytecode.data + i];
    let is_opcode_ge_0x5f = Helpers.is_le_unchecked(0x5f, opcode);
    let is_opcode_le_0x7f = Helpers.is_le_unchecked(opcode, 0x7f);
    let is_push_opcode = is_opcode_ge_0x5f * is_opcode_le_0x7f;
    let next_i = i + 1 + is_push_opcode * (opcode - 0x5f);  // 0x5f is the first PUSHN opcode, opcode - 0x5f is the number of arguments.

    if (opcode == 0x5b) {
        dict_write{dict_ptr=valid_jumpdests}(i, TRUE);
        tempvar valid_jumpdests = valid_jumpdests;
        tempvar next_i = next_i;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar valid_jumpdests = valid_jumpdests;
        tempvar next_i = next_i;
        tempvar range_check_ptr = range_check_ptr;
    }

    // continue_loop != 0 => next_i - bytecode_len < 0 <=> next_i < bytecode_len
    tempvar a = next_i - bytecode.len;
    %{ memory[ap] = 0 if 0 <= (ids.a % PRIME) < range_check_builtin.bound else 1 %}
    ap += 1;
    let continue_loop = [ap - 1];
    tempvar range_check_ptr = range_check_ptr;
    tempvar valid_jumpdests = valid_jumpdests;
    tempvar i = next_i;
    static_assert range_check_ptr == [ap - 3];
    static_assert valid_jumpdests == [ap - 2];
    static_assert i == [ap - 1];
    jmp body if continue_loop != 0;

    end:
    let range_check_ptr = [ap - 3];
    let i = [ap - 1];
    // Verify that i >= bytecode_len to ensure loop terminated correctly.
    let check = Helpers.is_le_unchecked(code.value.len, i);
    assert check = 1;

    let dict_ptr_start = cast(valid_jumpdests_start, SetUintDictAccess*);
    let dict_ptr = cast(valid_jumpdests, SetUintDictAccess*);
    tempvar valid_jumpdests_set = SetUint(new SetUintStruct(dict_ptr_start, dict_ptr));
    return valid_jumpdests_set;
}
