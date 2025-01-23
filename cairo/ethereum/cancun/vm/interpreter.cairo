from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin, PoseidonBuiltin
from starkware.cairo.common.default_dict import default_dict_new
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.math_cmp import is_nn

from ethereum_types.bytes import Bytes, BytesStruct
from ethereum_types.numeric import Uint, bool
from ethereum.cancun.blocks import TupleLog, TupleLogStruct, Log
from ethereum.cancun.vm.gas import GasConstants, charge_gas
from ethereum.cancun.fork_types import SetAddress
from ethereum.cancun.fork_types import SetAddressStruct, SetAddressDictAccess
from ethereum.cancun.vm import Evm, EvmStruct, Message, Environment, EvmImpl, EnvImpl
from ethereum.cancun.vm.exceptions import (
    EthereumException,
    InvalidContractPrefix,
    OutOfGasError,
    StackDepthLimitError,
    Revert,
)
from ethereum.cancun.vm.instructions import op_implementation
from ethereum.cancun.vm.memory import Memory, MemoryStruct, Bytes1DictAccess
from ethereum.cancun.vm.runtime import get_valid_jump_destinations
from ethereum.cancun.vm.stack import Stack, StackStruct, StackDictAccess
from ethereum.utils.numeric import U256, U256Struct, U256__eq__
from ethereum.cancun.state import (
    State,
    begin_transaction,
    destroy_storage,
    mark_account_created,
    increment_nonce,
    commit_transaction,
    rollback_transaction,
    move_ether,
    touch_account,
    set_code,
)

from src.utils.dict import dict_new_empty

const STACK_DEPTH_LIMIT = 1024;
const MAX_CODE_SIZE = 0x6000;

func process_create_message{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(message: Message, env: Environment) -> (Evm, EthereumException*) {
    alloc_locals;

    let state = env.value.state;
    let transient_storage = env.value.transient_storage;

    // take snapshot of state before processing the message
    begin_transaction{state=state, transient_storage=transient_storage}();

    // If the address where the account is being created has storage, it is
    // destroyed. This can only happen in the following highly unlikely
    // circumstances:
    // * The address created by a `CREATE` call collides with a subsequent
    //   `CREATE` or `CREATE2` call.
    // * The first `CREATE` happened before Spurious Dragon and left empty
    //   code.
    destroy_storage{state=state}(message.value.current_target);

    // In the previously mentioned edge case the preexisting storage is ignored
    // for gas refund purposes. In order to do this we must track created
    // accounts.
    mark_account_created{state=state}(message.value.current_target);

    increment_nonce{state=state}(message.value.current_target);
    EnvImpl.set_state{env=env}(state);
    EnvImpl.set_transient_storage{env=env}(transient_storage);
    let (evm, err) = process_message(message, env);
    if (cast(err, felt) != 0) {
        return (evm, err);
    }

    // Success case
    if (cast(evm.value.error, felt) == 0) {
        let contract_code = evm.value.output;
        let contract_code_gas = Uint(contract_code.value.len * GasConstants.GAS_CODE_DEPOSIT);

        if (contract_code.value.len != 0) {
            let first_opcode = contract_code.value.data[0];
            if (first_opcode == 0xEF) {
                tempvar err = new EthereumException(InvalidContractPrefix);
                _process_create_message_error{evm=evm}(err);
                tempvar ok = cast(0, EthereumException*);
                return (evm, ok);
            }
        }
        let err = charge_gas{evm=evm}(contract_code_gas);
        if (cast(err, felt) != 0) {
            _process_create_message_error{evm=evm}(err);
            tempvar ok = cast(0, EthereumException*);
            return (evm, ok);
        }
        let is_max_code_size_exceeded = is_nn(contract_code.value.len - MAX_CODE_SIZE);
        if (is_max_code_size_exceeded != FALSE) {
            tempvar err = new EthereumException(OutOfGasError);
            _process_create_message_error{evm=evm}(err);
            tempvar ok = cast(0, EthereumException*);
            return (evm, ok);
        }

        // Success case
        let env = evm.value.env;
        let state = env.value.state;
        set_code{state=state}(message.value.current_target, contract_code);
        commit_transaction{state=state, transient_storage=transient_storage}();
        EnvImpl.set_state{env=env}(state);
        EnvImpl.set_transient_storage{env=env}(transient_storage);
        EvmImpl.set_env{evm=evm}(env);
        tempvar ok = cast(0, EthereumException*);
        return (evm, ok);
    }

    // Error case
    let env = evm.value.env;
    let state = env.value.state;
    rollback_transaction{state=state, transient_storage=transient_storage}();
    EnvImpl.set_state{env=env}(state);
    EnvImpl.set_transient_storage{env=env}(transient_storage);
    EvmImpl.set_env{evm=evm}(env);

    tempvar ok = cast(0, EthereumException*);
    return (evm, ok);
}

func _process_create_message_error{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}(error: EthereumException*) {
    let env = evm.value.env;
    let state = env.value.state;
    let transient_storage = env.value.transient_storage;
    rollback_transaction{state=state, transient_storage=transient_storage}();
    EnvImpl.set_state{env=env}(state);
    EnvImpl.set_transient_storage{env=env}(transient_storage);
    EvmImpl.set_env(env);
    EvmImpl.set_gas_left(Uint(0));
    let output_bytes: felt* = alloc();
    tempvar output = Bytes(new BytesStruct(output_bytes, 0));
    EvmImpl.set_output(output);
    EvmImpl.set_error(error);
    return ();
}

func process_message{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(message: Message, env: Environment) -> (Evm, EthereumException*) {
    alloc_locals;

    // Check if depth exceeds limit by checking if (depth - limit) is non-negative
    let is_depth_exceeded = is_nn(message.value.depth.value - STACK_DEPTH_LIMIT);
    if (is_depth_exceeded != FALSE) {
        tempvar err = new EthereumException(StackDepthLimitError);
        tempvar evm = Evm(cast(0, EvmStruct*));
        return (evm, err);
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
        tempvar state = state;
        tempvar range_check_ptr = range_check_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
    } else {
        tempvar state = state;
        tempvar range_check_ptr = range_check_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
    }

    // Execute the code
    EnvImpl.set_state{env=env}(state);
    EnvImpl.set_transient_storage{env=env}(transient_storage);
    let evm = execute_code(message, env);

    // Handle transaction state based on execution result
    let env = evm.value.env;
    let state = env.value.state;
    let transient_storage = env.value.transient_storage;
    if (cast(evm.value.error, felt) != 0) {
        rollback_transaction{state=state, transient_storage=transient_storage}();
    } else {
        commit_transaction{state=state, transient_storage=transient_storage}();
    }
    EnvImpl.set_state{env=env}(state);
    EnvImpl.set_transient_storage{env=env}(transient_storage);
    EvmImpl.set_env{evm=evm}(env);

    let ok = cast(0, EthereumException*);
    return (evm, ok);
}

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
