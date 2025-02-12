from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.math_cmp import is_in_range

from ethereum_types.bytes import Bytes
from ethereum_types.numeric import SetUint, SetUintStruct, SetUintDictAccess

from cairo_core.maths import unsigned_div_rem

// @notice Initializes a dictionary of valid jump destinations in EVM bytecode.
// @dev This function is an oracle and doesn't enforce anything. During the EVM execution, the prover
// commits to the valid or invalid jumpdest responses, and the verifier checks the response in the
// finalize_jumpdests function.
func get_valid_jump_destinations{range_check_ptr}(code: Bytes) -> SetUint {
    alloc_locals;
    let bytecode = code.value.data;
    let bytecode_len = code.value.len;

    %{ initialize_jumpdests %}
    ap += 1;
    let valid_jumpdests_start = cast([ap - 1], DictAccess*);
    tempvar valid_jump_destinations = SetUint(
        new SetUintStruct(
            cast(valid_jumpdests_start, SetUintDictAccess*),
            cast(valid_jumpdests_start, SetUintDictAccess*),
        ),
    );

    return valid_jump_destinations;
}

// @notice Assert that the dictionary of valid jump destinations in EVM bytecode is valid.
// @dev Iterate over the list of DictAccesses and assert that
//       - the prev_value is equal to the new_value (no dict_writes)
//       - if the prev_value is TRUE
//          - assert that the bytecode at the key is 0x5b (JUMPDEST)
//          - assert that no PUSH are right before the JUMPDEST
//       - if the prev_value is FALSE, assert that the bytecode at the key is not 0x5b (JUMPDEST)
// @dev The keys are supposed to be sorted in ascending order, it's not a soundness issue if it's
//      not the case as the final assert will fail.
func finalize_jumpdests{range_check_ptr}(
    index: felt, valid_jumpdests_start: DictAccess*, valid_jumpdests: DictAccess*, bytecode: felt*
) {
    alloc_locals;

    if (valid_jumpdests_start == valid_jumpdests) {
        return ();
    }

    // Assert that the jumpdests are sorted in ascending order
    assert [range_check_ptr] = valid_jumpdests_start.key - index;
    let range_check_ptr = range_check_ptr + 1;

    assert_valid_jumpdest(index, bytecode, valid_jumpdests_start);

    return finalize_jumpdests(
        index=valid_jumpdests_start.key + 1,
        valid_jumpdests_start=valid_jumpdests_start + DictAccess.SIZE,
        valid_jumpdests=valid_jumpdests,
        bytecode=bytecode,
    );
}

// @notice Assert that a single valid_jumpdest is valid.
// @dev Use a hint to determine if the easy case (no PUSHes before the JUMPDEST) is true
//      Otherwise, starts back at the given start_index, ie analyse the whole bytecode[start_index:key] segment.
func assert_valid_jumpdest{range_check_ptr}(
    start_index: felt, bytecode: felt*, valid_jumpdest: DictAccess*
) {
    alloc_locals;
    // Assert that the dict access is only read (same prev and new value)
    assert valid_jumpdest.prev_value = valid_jumpdest.new_value;
    let bytecode_at_jumpdest = [bytecode + valid_jumpdest.key];

    if (bytecode_at_jumpdest != 0x5b) {
        with_attr error_message("assert_valid_jumpdest: invalid jumpdest") {
            assert valid_jumpdest.prev_value = 0;
        }
        return ();
    }

    // At this stage, we know that the jumpdest is a JUMPDEST byte. We still need to check if there is a PUSH
    // before or if it's actually a JUMPDEST opcode. There are two cases:
    // 1. Optimized case: We can just assert that there is no PUSH in the 32 bytes before the JUMPDEST
    // 2. General case: We incrementally update the PC from start_index and check if we eventually reach the JUMPDEST.
    //    This is generally speaking more step consuming and will be used if the optimized case is not possible. Note that
    //    the start_index needs to point to a real opcode and is not checked to be itself a PUSH argument. 0 will always
    //    be sound; if some previous JUMPDEST are already checked, they can be used to shorten the range of the general case.
    if (valid_jumpdest.key == 0) {
        with_attr error_message("assert_valid_jumpdest: invalid jumpdest") {
            assert valid_jumpdest.prev_value = 1;
        }
        return ();
    }

    tempvar is_no_push_case;
    %{
        # Get the 32 previous bytes
        bytecode = [memory[ids.bytecode + ids.valid_jumpdest.key - i - 1] for i in range(min(ids.valid_jumpdest.key, 32))][::-1]
        # Check if any PUSH may prevent this to be a JUMPDEST
        memory[ap - 1] = int(not any([0x60 + i <= byte <= 0x7f for i, byte in enumerate(bytecode[::-1])]))
    %}
    jmp no_push_case if is_no_push_case != 0;

    general_case:
    tempvar range_check_ptr = range_check_ptr;
    tempvar i = start_index;

    body_general_case:
    let bytecode = cast([fp - 4], felt*);
    let range_check_ptr = [ap - 2];
    let i = [ap - 1];

    tempvar opcode = [bytecode + i];
    let is_push_opcode = is_in_range(opcode, 0x60, 0x80);
    tempvar next_i = i + 1 + is_push_opcode * (opcode - 0x5f);

    tempvar cond;
    tempvar range_check_ptr = range_check_ptr;
    tempvar i = next_i;
    %{ ids.cond = 1 if ids.i < ids.valid_jumpdest.key else 0 %}
    jmp body_general_case if cond != 0;

    let range_check_ptr = [ap - 2];
    let i = [ap - 1];

    // We stop the loop when i >= valid_jumpdest.key
    assert [range_check_ptr] = i - valid_jumpdest.key;
    let range_check_ptr = range_check_ptr + 1;

    // Either the jumpdest is valid and we've reached it, or it's not and we've overpassed it
    with_attr error_message("assert_valid_jumpdest: invalid jumpdest") {
        assert (i - valid_jumpdest.key) * valid_jumpdest.prev_value = 0;
    }

    return ();

    no_push_case:
    tempvar offset = 1;
    tempvar range_check_ptr = range_check_ptr;

    body_no_push_case:
    let offset = [ap - 2];
    let range_check_ptr = [ap - 1];
    let bytecode = cast([fp - 4], felt*);
    let valid_jumpdest = cast([fp - 3], DictAccess*);

    let opcode = [bytecode + valid_jumpdest.key - offset];
    // offset is the distance from the JUMPDEST, so offset = i means that any PUSH_i
    // with i > offset may prevent this to be a JUMPDEST
    let is_push_opcode = is_in_range(opcode, 0x5f + offset, 0x80);
    assert is_push_opcode = 0;
    tempvar cond;
    tempvar offset = offset + 1;
    tempvar range_check_ptr = range_check_ptr;

    static_assert offset == [ap - 2];
    static_assert range_check_ptr == [ap - 1];
    %{ ids.cond = 0 if ids.offset > 32 or ids.valid_jumpdest.key < ids.offset else 1 %}
    jmp body_no_push_case if cond != 0;

    let offset = [ap - 2];
    let range_check_ptr = [ap - 1];
    let valid_jumpdest = cast([fp - 3], DictAccess*);

    // Offset should be either 33 or key + 1, meaning we've been up until the beginning of the
    // bytecode, or up to 32 bytes earlier
    assert (32 + 1 - offset) * (valid_jumpdest.key + 1 - offset) = 0;
    with_attr error_message("assert_valid_jumpdest: invalid jumpdest") {
        assert valid_jumpdest.prev_value = 1;
    }

    return ();
}
