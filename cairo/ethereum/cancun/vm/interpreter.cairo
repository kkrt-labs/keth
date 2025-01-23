from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin, PoseidonBuiltin
from starkware.cairo.common.default_dict import default_dict_new
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.math_cmp import is_nn

from ethereum_types.bytes import Bytes, BytesStruct
from ethereum_types.numeric import Uint, bool
from ethereum.cancun.blocks import TupleLog, TupleLogStruct, Log
from ethereum.cancun.fork_types import SetAddress
from ethereum.cancun.fork_types import SetAddressStruct, SetAddressDictAccess
from ethereum.cancun.vm import Evm, EvmStruct, Message, Environment, EvmImpl
from ethereum.cancun.vm.exceptions import EthereumException
from ethereum.cancun.vm.exceptions import Revert
from ethereum.cancun.state import (
    State,
    begin_transaction,
    commit_transaction,
    rollback_transaction,
    touch_account,
    move_ether,
)
from ethereum.cancun.vm.instructions import op_implementation
from ethereum.cancun.vm.memory import Memory, MemoryStruct, Bytes1DictAccess
from ethereum.cancun.vm.runtime import get_valid_jump_destinations
from ethereum.cancun.vm.stack import Stack, StackStruct, StackDictAccess
from ethereum.utils.numeric import U256, U256Struct, U256__eq__

from src.utils.dict import dict_new_empty

const STACK_DEPTH_LIMIT = 1024;

func execute_code{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(message: Message, env: Environment) -> Evm {
    alloc_locals;

    // Get valid jump destinations
    let valid_jumpdests = get_valid_jump_destinations(message.value.code);
    // Create empty stack
    let (dict_start: DictAccess*) = default_dict_new(0);
    let dict_ptr = dict_start;
    tempvar empty_stack = Stack(
        new StackStruct(
            dict_ptr_start=cast(dict_start, StackDictAccess*),
            dict_ptr=cast(dict_ptr, StackDictAccess*),
            len=0,
        ),
    );
    // Create empty memory
    let (dict_start: DictAccess*) = default_dict_new(0);
    let dict_ptr = dict_start;
    tempvar empty_memory = Memory(
        new MemoryStruct(
            dict_ptr_start=cast(dict_start, Bytes1DictAccess*),
            dict_ptr=cast(dict_ptr, Bytes1DictAccess*),
            len=0,
        ),
    );
    // Create empty Logs
    let (empty_logs: Log*) = alloc();
    tempvar tuple_log_struct = TupleLog(new TupleLogStruct(data=empty_logs, len=0));
    // Create empty accounts_to_delete and touched_accounts
    let (dict_start: DictAccess*) = default_dict_new(0);
    let dict_ptr = dict_start;
    tempvar empty_accounts_to_delete = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=cast(dict_start, SetAddressDictAccess*),
            dict_ptr=cast(dict_ptr, SetAddressDictAccess*),
        ),
    );
    let (dict_start: DictAccess*) = default_dict_new(0);
    let dict_ptr = dict_start;
    tempvar empty_touched_accounts = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=cast(dict_start, SetAddressDictAccess*),
            dict_ptr=cast(dict_ptr, SetAddressDictAccess*),
        ),
    );

    // Initialize EVM state
    tempvar evm = Evm(
        new EvmStruct(
            pc=Uint(0),
            stack=empty_stack,
            memory=empty_memory,
            code=message.value.code,
            gas_left=message.value.gas,
            env=env,
            valid_jump_destinations=valid_jumpdests,
            logs=tuple_log_struct,
            refund_counter=0,
            running=bool(1),
            message=message,
            output=Bytes(new BytesStruct(cast(0, felt*), 0)),
            accounts_to_delete=empty_accounts_to_delete,
            touched_accounts=empty_touched_accounts,
            return_data=Bytes(new BytesStruct(cast(0, felt*), 0)),
            error=cast(0, EthereumException*),
            accessed_addresses=message.value.accessed_addresses,
            accessed_storage_keys=message.value.accessed_storage_keys,
        ),
    );

    // TODO: Handle precompiled contracts

    // Execute bytecode recursively
    return _execute_code(evm);
}

func _execute_code{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(evm: Evm) -> Evm {
    alloc_locals;

    // Base case: EVM not running or PC >= code length
    if (evm.value.running.value == FALSE) {
        return evm;
    }
    let is_pc_ge_code_len = is_nn(evm.value.pc.value - evm.value.code.value.len);
    if (is_pc_ge_code_len != FALSE) {
        return evm;
    }

    // Execute the opcode and handle any errors
    let opcode = [evm.value.code.value.data + evm.value.pc.value];
    with evm {
        let err = op_implementation(opcode);
        if (cast(err, felt) != 0) {
            if (err.value == Revert) {
                EvmImpl.set_error(err);
                return evm;
            }

            EvmImpl.set_gas_left(Uint(0));
            let (output_bytes: felt*) = alloc();
            tempvar output = Bytes(new BytesStruct(output_bytes, 0));
            EvmImpl.set_output(output);
            EvmImpl.set_error(err);
            return evm;
        }
    }

    // Recursive call to continue execution
    return _execute_code(evm);
}

func process_message{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(message: Message, env: Environment) -> Evm {
    alloc_locals;

    // Check if depth exceeds limit by checking if (depth - limit) is non-negative
    let is_depth_exceeded = is_nn(message.value.depth.value - STACK_DEPTH_LIMIT);
    with_attr error_message("StackDepthLimitError") {
        assert is_depth_exceeded = FALSE;
    }

    // Take snapshot of state before processing the message
    let state = env.value.state;
    let transient_storage = env.value.transient_storage;
    begin_transaction{state=state, transient_storage=transient_storage}();

    // Touch account
    touch_account{state=state}(message.value.current_target);

    // Handle value transfer if needed
    let value_eq_zero = U256__eq__(message.value.value, U256(new U256Struct(0, 0)));
    let should_move_ether = message.value.should_transfer_value.value * (1 - value_eq_zero.value);
    if (should_move_ether != FALSE) {
        move_ether{state=state}(
            message.value.caller, message.value.current_target, message.value.value
        );
        tempvar range_check_ptr = range_check_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
    } else {
        tempvar range_check_ptr = range_check_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
    }

    // Execute the code
    let evm = execute_code(message, env);

    // Handle transaction state based on execution result
    let state = env.value.state;
    let transient_storage = env.value.transient_storage;
    if (cast(evm.value.error, felt) != 0) {
        rollback_transaction{state=state, transient_storage=transient_storage}();
    } else {
        commit_transaction{state=state, transient_storage=transient_storage}();
    }

    return evm;
}
