from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.default_dict import default_dict_new
from starkware.cairo.common.dict_access import DictAccess

from ethereum_types.bytes import Bytes, BytesStruct
from ethereum_types.numeric import SetUint, SetUintStruct, SetUintDictAccess

from cairo_core.comparison import is_le_unchecked
from legacy.utils.dict import dict_write

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
