from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.dict_access import DictAccess

from src.evm import EVM, Internals
from src.model import model
from src.state import State
from tests.utils.helpers import TestHelpers

func test__jump{pedersen_ptr: HashBuiltin*, range_check_ptr}() -> model.EVM* {
    alloc_locals;
    local bytecode_len: felt;
    let (bytecode) = alloc();
    local jumpdest: felt;
    %{
        ids.bytecode_len = len(program_input["bytecode"]);
        segments.write_arg(ids.bytecode, program_input["bytecode"]);
        ids.jumpdest = program_input["jumpdest"];
    %}
    let evm = TestHelpers.init_evm_with_bytecode(bytecode_len, bytecode);
    let state = State.init();
    with state {
        let evm = EVM.jump(evm, jumpdest);
    }

    return evm;
}

func test__is_valid_jumpdest{pedersen_ptr: HashBuiltin*, range_check_ptr}() -> felt {
    alloc_locals;

    local index;

    %{
        from collections import defaultdict
        from tests.utils.hints import new_default_dict

        if '__dict_manager' not in globals():
            from starkware.cairo.common.dict import DictManager
            __dict_manager = DictManager()

        initial_dict = defaultdict(int, program_input["cached_jumpdests"])
        memory[ap] = new_default_dict(__dict_manager, segments, 0, initial_dict)
        del initial_dict

        ids.index = program_input["index"]
    %}
    ap += 1;
    let valid_jumpdests = cast([ap - 1], DictAccess*);
    let state = State.init();
    tempvar address_zero = new model.Address(starknet=0, evm=0);

    with valid_jumpdests, state {
        let result = Internals.is_valid_jumpdest(address_zero, index);
    }

    return result;
}

func test__charge_gas{pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (felt, felt) {
    alloc_locals;
    local amount;

    %{ ids.amount = program_input["amount"] %}
    let evm = TestHelpers.init_evm();
    let result = EVM.charge_gas(evm, amount);

    return (result.gas_left, result.stopped);
}
