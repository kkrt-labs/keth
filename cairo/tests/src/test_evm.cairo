from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.dict_access import DictAccess

from src.evm import EVM
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

    let state = State.init();
    let initial_state = State.copy{state=state}();
    let evm = TestHelpers.init_evm_with_bytecode(initial_state, bytecode_len, bytecode);
    with state {
        let evm = EVM.jump(evm, jumpdest);
    }

    return evm;
}

func test__charge_gas{pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (felt, felt) {
    alloc_locals;
    local amount;

    %{ ids.amount = program_input["amount"] %}
    let state = State.init();
    let initial_state = State.copy{state=state}();
    let evm = TestHelpers.init_evm(initial_state);
    let result = EVM.charge_gas(evm, amount);

    return (result.gas_left, result.stopped);
}
