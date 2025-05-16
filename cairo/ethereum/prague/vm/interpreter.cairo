from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, PoseidonBuiltin, ModBuiltin
from starkware.cairo.common.default_dict import default_dict_new
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.math_cmp import is_nn
from starkware.cairo.common.registers import get_label_location

from ethereum_types.bytes import Bytes, BytesStruct
from ethereum_types.numeric import Uint, bool, SetUint, SetUintStruct, SetUintDictAccess
from ethereum.prague.blocks import TupleLog, TupleLogStruct, Log
from ethereum.prague.vm.gas import GasConstants, charge_gas
from ethereum.prague.fork_types import (
    SetAddress,
    SetTupleAddressBytes32,
    SetTupleAddressBytes32Struct,
    SetAddressStruct,
    SetAddressDictAccess,
    SetTupleAddressBytes32DictAccess,
)

from ethereum.prague.trie import TrieTupleAddressBytes32U256, TrieTupleAddressBytes32U256Struct
from ethereum.prague.vm.evm_impl import Evm, EvmStruct, Message, MessageImpl
from ethereum.prague.vm.env_impl import BlockEnvironment, BlockEnvImpl, TransactionEnvImpl

from ethereum.prague.utils.constants import MAX_CODE_SIZE
from ethereum.exceptions import EthereumException
from ethereum.prague.vm.exceptions import (
    InvalidContractPrefix,
    OutOfGasError,
    Revert,
    AddressCollision,
)

from ethereum.prague.vm.precompiled_contracts.mapping import precompile_table_lookup
from ethereum.prague.vm.instructions import op_implementation
from ethereum.prague.vm.memory import Memory, MemoryStruct, Bytes1DictAccess
from ethereum.prague.vm.runtime import get_valid_jump_destinations, finalize_jumpdests
from ethereum.prague.vm.stack import Stack, StackStruct, StackDictAccess
from ethereum.utils.numeric import U256, U256Struct, U256__eq__
from ethereum.prague.state import (
    finalize_transient_storage,
    destroy_account,
    StateImpl,
    account_exists_and_is_empty,
    account_has_code_or_nonce,
    account_has_storage,
    begin_transaction,
    commit_transaction,
    increment_nonce,
    mark_account_created,
    move_ether,
    rollback_transaction,
    set_code,
    State,
    StateStruct,
)

from ethereum.prague.vm.evm_impl import EvmImpl

from legacy.utils.dict import default_dict_finalize, dict_squash

struct MessageCallOutput {
    value: MessageCallOutputStruct*,
}

struct MessageCallOutputStruct {
    gas_left: Uint,
    refund_counter: U256,
    logs: TupleLog,
    accounts_to_delete: SetAddress,
    error: EthereumException*,
    return_data: Bytes,
    accessed_storage_keys: SetTupleAddressBytes32,
}

func process_create_message{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(message: Message) -> Evm {
    alloc_locals;

    let block_env = message.value.block_env;
    let state = block_env.value.state;
    let tx_env = message.value.tx_env;
    let transient_storage = tx_env.value.transient_storage;

    // take snapshot of state before processing the message
    begin_transaction{state=state, transient_storage=transient_storage}();
    TransactionEnvImpl.set_transient_storage{tx_env=tx_env}(transient_storage);

    // If the address where the account is being created has storage, it is
    // destroyed. This can only happen in the following highly unlikely
    // circumstances:
    // * The address created by a `CREATE` call collides with a subsequent
    //   `CREATE` or `CREATE2` call.
    // * The first `CREATE` happened before Spurious Dragon and left empty
    //   code.

    // Note: diff with EELS here:
    // 1. We consider the CREATE call collision unlikely enough to happen in the same block,
    //    so if a created account has no storage before that block, we consider it not to have any storage _at all_.
    // 2. We can know whether the account has storage or not by checking the storage root.
    // 3. We can skip the storage destruction if the storage root is the empty root.
    let is_empty = account_exists_and_is_empty{state=state}(message.value.current_target);
    if (is_empty.value != FALSE) {
        destroy_account{state=state}(message.value.current_target);
        tempvar range_check_ptr = range_check_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar state = state;
    } else {
        tempvar range_check_ptr = range_check_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar state = state;
    }
    let range_check_ptr = [ap - 3];
    let poseidon_ptr = cast([ap - 2], PoseidonBuiltin*);
    let state = State(cast([ap - 1], StateStruct*));

    // In the previously mentioned edge case the preexisting storage is ignored
    // for gas refund purposes. In order to do this we must track created
    // accounts.
    mark_account_created{state=state}(message.value.current_target);

    increment_nonce{state=state}(message.value.current_target);
    BlockEnvImpl.set_state{block_env=block_env}(state);
    MessageImpl.set_block_env{message=message}(block_env);
    MessageImpl.set_tx_env{message=message}(tx_env);
    let evm = process_message(message);

    // Rebind variables mutated in environment
    let block_env = evm.value.message.value.block_env;
    let state = block_env.value.state;
    let tx_env = evm.value.message.value.tx_env;
    let transient_storage = tx_env.value.transient_storage;

    if (cast(evm.value.error, felt) != 0) {
        // Error case
        rollback_transaction{state=state, transient_storage=transient_storage}();
        BlockEnvImpl.set_state{block_env=block_env}(state);
        TransactionEnvImpl.set_transient_storage{tx_env=tx_env}(transient_storage);
        EvmImpl.set_block_env{evm=evm}(block_env);
        EvmImpl.set_tx_env{evm=evm}(tx_env);
        return evm;
    }
    let contract_code = evm.value.output;
    let contract_code_gas = Uint(contract_code.value.len * GasConstants.GAS_CODE_DEPOSIT);

    if (contract_code.value.len != 0) {
        let first_opcode = contract_code.value.data[0];
        if (first_opcode == 0xEF) {
            tempvar err = new EthereumException(InvalidContractPrefix);
            _process_create_message_error{evm=evm}(err);
            return evm;
        }
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar range_check_ptr = range_check_ptr;
    }
    let range_check_ptr = [ap - 1];
    let err = charge_gas{evm=evm}(contract_code_gas);
    if (cast(err, felt) != 0) {
        _process_create_message_error{evm=evm}(err);
        return evm;
    }
    let is_max_code_size_exceeded = is_nn(contract_code.value.len - (MAX_CODE_SIZE + 1));
    if (is_max_code_size_exceeded != FALSE) {
        tempvar err = new EthereumException(OutOfGasError);
        _process_create_message_error{evm=evm}(err);
        return evm;
    }
    set_code{state=state}(message.value.current_target, contract_code);
    commit_transaction{state=state, transient_storage=transient_storage}();
    BlockEnvImpl.set_state{block_env=block_env}(state);
    TransactionEnvImpl.set_transient_storage{tx_env=tx_env}(transient_storage);
    EvmImpl.set_block_env{evm=evm}(block_env);
    EvmImpl.set_tx_env{evm=evm}(tx_env);
    return evm;
}

func _process_create_message_error{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}(error: EthereumException*) {
    let block_env = evm.value.message.value.block_env;
    let state = block_env.value.state;
    let tx_env = evm.value.message.value.tx_env;
    let transient_storage = tx_env.value.transient_storage;
    rollback_transaction{state=state, transient_storage=transient_storage}();
    BlockEnvImpl.set_state{block_env=block_env}(state);
    TransactionEnvImpl.set_transient_storage{tx_env=tx_env}(transient_storage);
    EvmImpl.set_block_env{evm=evm}(block_env);
    EvmImpl.set_tx_env{evm=evm}(tx_env);
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
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(message: Message) -> Evm {
    alloc_locals;

    // EELS checks whether the stack depth limit is reached here.
    // However, this case is never triggered, because `generic_call` and `generic_create`
    // check the stack depth limit before calling `process_message`.

    // Take snapshot of state before processing the message
    let block_env = message.value.block_env;
    let state = block_env.value.state;
    let tx_env = message.value.tx_env;
    let transient_storage = tx_env.value.transient_storage;
    begin_transaction{state=state, transient_storage=transient_storage}();
    TransactionEnvImpl.set_transient_storage{tx_env=tx_env}(transient_storage);

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
    BlockEnvImpl.set_state{block_env=block_env}(state);
    MessageImpl.set_block_env{message=message}(block_env);
    MessageImpl.set_tx_env{message=message}(tx_env);
    let evm = execute_code(message);

    // Handle transaction state based on execution result
    let block_env = evm.value.message.value.block_env;
    let state = block_env.value.state;
    let tx_env = evm.value.message.value.tx_env;
    let transient_storage = tx_env.value.transient_storage;
    if (cast(evm.value.error, felt) != 0) {
        rollback_transaction{state=state, transient_storage=transient_storage}();
    } else {
        commit_transaction{state=state, transient_storage=transient_storage}();
    }
    BlockEnvImpl.set_state{block_env=block_env}(state);
    TransactionEnvImpl.set_transient_storage{tx_env=tx_env}(transient_storage);
    EvmImpl.set_block_env{evm=evm}(block_env);
    EvmImpl.set_tx_env{evm=evm}(tx_env);

    return evm;
}

func execute_code{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(message: Message) -> Evm {
    alloc_locals;

    // Get valid jump destinations
    let valid_jump_destinations = get_valid_jump_destinations(message.value.code);

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
    // Create empty accounts_to_delete
    let (dict_start: DictAccess*) = default_dict_new(0);
    let dict_ptr = dict_start;
    tempvar empty_accounts_to_delete = SetAddress(
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
            valid_jump_destinations=valid_jump_destinations,
            logs=tuple_log_struct,
            refund_counter=0,
            running=bool(1),
            message=message,
            output=Bytes(new BytesStruct(cast(0, felt*), 0)),
            accounts_to_delete=empty_accounts_to_delete,
            return_data=Bytes(new BytesStruct(cast(0, felt*), 0)),
            error=cast(0, EthereumException*),
            accessed_addresses=message.value.accessed_addresses,
            accessed_storage_keys=message.value.accessed_storage_keys,
        ),
    );

    // code_address might be optional in create scenarios at this point.
    if (cast(evm.value.message.value.code_address.value, felt) != 0) {
        let (local precompile_address, precompile_fn) = precompile_table_lookup(
            [evm.value.message.value.code_address.value]
        );
        // Addresses that are not precompiles return 0.
        if (precompile_address != 0) {
            %{
                precompile_address_bytes = ids.precompile_address.to_bytes(20, "little")
                logger.trace_cairo(f"PrecompileStart: {precompile_address_bytes}")
            %}
            // Prepare arguments
            // MARK: args assignment
            [ap] = range_check_ptr, ap++;
            [ap] = bitwise_ptr, ap++;
            [ap] = keccak_ptr, ap++;
            [ap] = poseidon_ptr, ap++;
            [ap] = range_check96_ptr, ap++;
            [ap] = add_mod_ptr, ap++;
            [ap] = mul_mod_ptr, ap++;
            [ap] = evm.value, ap++;

            call abs precompile_fn;

            let range_check_ptr = [ap - 9];
            let bitwise_ptr = cast([ap - 8], BitwiseBuiltin*);
            let keccak_ptr = cast([ap - 7], felt*);
            let poseidon_ptr = cast([ap - 6], PoseidonBuiltin*);
            let range_check96_ptr = cast([ap - 5], felt*);
            let add_mod_ptr = cast([ap - 4], ModBuiltin*);
            let mul_mod_ptr = cast([ap - 3], ModBuiltin*);
            let evm = Evm(cast([ap - 2], EvmStruct*));
            let err = cast([ap - 1], EthereumException*);

            %{
                precompile_address_bytes = ids.precompile_address.to_bytes(20, "little")
                logger.trace_cairo(f"PrecompileEnd: {precompile_address_bytes}")
            %}

            if (cast(err, felt) != 0) {
                %{ logger.trace_cairo(f"OpException: {serialize(ids.err)}") %}
                EvmImpl.set_gas_left{evm=evm}(Uint(0));
                let (output_bytes: felt*) = alloc();
                tempvar output = Bytes(new BytesStruct(output_bytes, 0));
                EvmImpl.set_output{evm=evm}(output);
                EvmImpl.set_error{evm=evm}(err);
                return evm;
            }
            return evm;
        }
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar range_check_ptr = range_check_ptr;
    }

    // Execute bytecode recursively
    let (process_create_message_label) = get_label_location(process_create_message);
    let (process_message_label) = get_label_location(process_message);
    let res = _execute_code{
        process_create_message_label=process_create_message_label,
        process_message_label=process_message_label,
    }(evm);
    return res;
}

func _execute_code{
    process_create_message_label: felt*,
    process_message_label: felt*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(evm: Evm) -> Evm {
    alloc_locals;

    // Base case: EVM not running or PC >= code length
    if (evm.value.running.value == FALSE) {
        %{ logger.trace_cairo(f"EvmStop") %}
        return evm;
    }

    let is_pc_ge_code_len = is_nn(evm.value.pc.value - evm.value.code.value.len);
    if (is_pc_ge_code_len != FALSE) {
        %{ logger.trace_cairo(f"EvmStop") %}
        return evm;
    }

    // Execute the opcode and handle any errors
    tempvar opcode = [evm.value.code.value.data + evm.value.pc.value];
    local opcode_hex = opcode;
    with evm {
        %{ logger.trace_cairo(f"OpStart: {hex(ids.opcode_hex)}") %}
        let err = op_implementation(
            process_create_message_label=process_create_message_label,
            process_message_label=process_message_label,
            opcode=opcode,
        );
        %{
            if ids.err.value == 0:
                logger.trace_cairo(f"OpEnd")
        %}
        if (cast(err, felt) != 0) {
            if (err.value == Revert) {
                %{ logger.trace_cairo(f"Revert: {serialize(ids.err)}") %}
                EvmImpl.set_error(err);
                return evm;
            }

            %{
                error_bytes = memory[ids.err.address_].to_bytes(32, "big")
                ascii_value = error_bytes.decode().strip("\x00")
                logger.trace_cairo(f"OpException: {ascii_value}")
            %}
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

func process_message_call{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    block_env: BlockEnvironment,
}(message: Message) -> MessageCallOutput {
    alloc_locals;

    let block_env = message.value.block_env;
    let state = block_env.value.state;

    // Check if this is a contract creation (target is empty)
    if (cast(message.value.target.value.address, felt) == 0) {
        let has_collision = account_has_code_or_nonce{state=state}(message.value.current_target);
        let has_storage = account_has_storage{state=state}(message.value.current_target);
        BlockEnvImpl.set_state{block_env=block_env}(state);
        MessageImpl.set_block_env{message=message}(block_env);
        if (has_collision.value + has_storage.value != FALSE) {
            // Return early with collision error
            tempvar collision_error = new EthereumException(AddressCollision);
            finalize_message(message);
            let msg = create_empty_message_call_output(Uint(0), collision_error);
            return msg;
        }

        // Process create message
        let evm = process_create_message(message);

        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar keccak_ptr = keccak_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
        tempvar evm = evm;
    } else {
        // Regular message call path
        let evm = process_message(message);
        // Re-bind the evm's mutated `env` object to the original `env` object.
        let block_env = evm.value.message.value.block_env;

        // Check if account exists and is empty - and rebind the `evm` object with the mutated env.state.
        let state = block_env.value.state;
        let is_empty = account_exists_and_is_empty{state=state}(
            [message.value.target.value.address]
        );
        BlockEnvImpl.set_state{block_env=block_env}(state);
        EvmImpl.set_block_env{evm=evm}(block_env);

        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar keccak_ptr = keccak_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
        tempvar evm = evm;
    }
    let range_check_ptr = [ap - 8];
    let bitwise_ptr = cast([ap - 7], BitwiseBuiltin*);
    let keccak_ptr = cast([ap - 6], felt*);
    let poseidon_ptr = cast([ap - 5], PoseidonBuiltin*);
    let range_check96_ptr = cast([ap - 4], felt*);
    let add_mod_ptr = cast([ap - 3], ModBuiltin*);
    let mul_mod_ptr = cast([ap - 2], ModBuiltin*);
    let evm_struct = cast([ap - 1], EvmStruct*);
    tempvar evm = Evm(evm_struct);
    let block_env = evm.value.message.value.block_env;

    // Prepare return values based on error state
    if (cast(evm.value.error, felt) != 0) {
        finalize_evm{evm=evm}();
        let msg = create_empty_message_call_output(evm.value.gas_left, evm.value.error);
        return msg;
    }

    assert [range_check_ptr] = evm.value.refund_counter;
    let range_check_ptr = range_check_ptr + 1;

    finalize_evm{evm=evm}();

    let squashed_evm = evm;
    %{
        initial_gas = serialize(ids.evm.value.message.value.gas)
        final_gas = serialize(ids.squashed_evm.value.gas_left)
        output = serialize(ids.squashed_evm.value.output)
        error_int = serialize(ids.squashed_evm.value.error)["value"]
        if error_int == 0:
            error = None
        else:
            error_bytes = error_int.to_bytes(32, "big")
            ascii_value = error_bytes.decode().strip("\x00")
            error = ascii_value
        gas_used = initial_gas - final_gas
        logger.trace_cairo(f"TransactionEnd: gas_used: {gas_used}, output: {output}, error: {error}")
    %}
    tempvar msg = MessageCallOutput(
        new MessageCallOutputStruct(
            gas_left=squashed_evm.value.gas_left,
            refund_counter=U256(new U256Struct(squashed_evm.value.refund_counter, 0)),
            logs=squashed_evm.value.logs,
            accounts_to_delete=squashed_evm.value.accounts_to_delete,
            error=squashed_evm.value.error,
            return_data=squashed_evm.value.return_data,
            accessed_storage_keys=squashed_evm.value.accessed_storage_keys,
        ),
    );
    return msg;
}

func create_empty_message_call_output(
    gas_left: Uint, error: EthereumException*
) -> MessageCallOutput {
    alloc_locals;
    let (empty_logs: Log*) = alloc();
    tempvar empty_tuple_log = TupleLog(new TupleLogStruct(data=empty_logs, len=0));

    // Create first empty set for accounts_to_delete
    let (dict_start1: DictAccess*) = default_dict_new(0);
    let dict_ptr1 = dict_start1;
    tempvar empty_set1 = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=cast(dict_start1, SetAddressDictAccess*),
            dict_ptr=cast(dict_ptr1, SetAddressDictAccess*),
        ),
    );

    let (dict_start3: DictAccess*) = default_dict_new(0);
    let dict_ptr3 = dict_start3;
    tempvar empty_set3 = SetTupleAddressBytes32(
        new SetTupleAddressBytes32Struct(
            dict_ptr_start=cast(dict_start3, SetTupleAddressBytes32DictAccess*),
            dict_ptr=cast(dict_ptr3, SetTupleAddressBytes32DictAccess*),
        ),
    );

    tempvar return_data = Bytes(new BytesStruct(cast(0, felt*), 0));

    tempvar msg = MessageCallOutput(
        new MessageCallOutputStruct(
            gas_left=gas_left,
            refund_counter=U256(new U256Struct(0, 0)),
            logs=empty_tuple_log,
            accounts_to_delete=empty_set1,
            error=error,
            return_data=return_data,
            accessed_storage_keys=empty_set3,
        ),
    );
    return msg;
}

// @notice Finalizes a `Message` struct by squashing its inner dicts
func finalize_message{range_check_ptr}(message: Message) {
    alloc_locals;

    // INVARIANT: this should always be 0 as finalize_message can only be called on a create_tx that has a collision.
    assert cast(message.value.parent_evm.value, felt) = 0;

    let accessed_addresses = message.value.accessed_addresses;
    let accessed_addresses_start = accessed_addresses.value.dict_ptr_start;
    let accessed_addresses_end = cast(accessed_addresses.value.dict_ptr, DictAccess*);
    default_dict_finalize(cast(accessed_addresses_start, DictAccess*), accessed_addresses_end, 0);

    let accessed_storage_keys = message.value.accessed_storage_keys;
    let accessed_storage_keys_start = accessed_storage_keys.value.dict_ptr_start;
    let accessed_storage_keys_end = cast(accessed_storage_keys.value.dict_ptr, DictAccess*);
    default_dict_finalize(
        cast(accessed_storage_keys_start, DictAccess*), accessed_storage_keys_end, 0
    );

    return ();
}

// @notice Finalizes an `Evm` struct by squashing all of its fields except for the `state`'s main_trie
// and storage_tries inside the Environment - which is only finalized after processing full blocks.
// There's no need to finalize the inner `message` as well - as its dicts (accessed_addresses, accessed_storage_keys, etc)
// are inlined in the `Evm` struct already - and the message is not consumed again after the `Evm` is finalized.
func finalize_evm{range_check_ptr, evm: Evm}() {
    alloc_locals;

    // Squash stack
    let stack = evm.value.stack;
    let stack_start = stack.value.dict_ptr_start;
    let stack_end = cast(stack.value.dict_ptr, DictAccess*);
    let (new_stack_start, new_stack_end) = default_dict_finalize(
        cast(stack_start, DictAccess*), cast(stack_end, DictAccess*), 0
    );
    tempvar new_stack = Stack(
        new StackStruct(
            dict_ptr_start=cast(new_stack_start, StackDictAccess*),
            dict_ptr=cast(new_stack_end, StackDictAccess*),
            len=stack.value.len,
        ),
    );

    // Squash memory
    let memory = evm.value.memory;
    let memory_start = memory.value.dict_ptr_start;
    let memory_end = cast(memory.value.dict_ptr, DictAccess*);
    let (new_memory_start, new_memory_end) = default_dict_finalize(
        cast(memory_start, DictAccess*), cast(memory_end, DictAccess*), 0
    );
    tempvar new_memory = Memory(
        new MemoryStruct(
            dict_ptr_start=cast(new_memory_start, Bytes1DictAccess*),
            dict_ptr=cast(new_memory_end, Bytes1DictAccess*),
            len=memory.value.len,
        ),
    );

    // No squash for Env which is an implicit argument in `process_message_call`

    // Squash valid_jump_destinations
    let valid_jump_destinations = evm.value.valid_jump_destinations;
    let valid_jump_destinations_start = valid_jump_destinations.value.dict_ptr_start;
    let valid_jump_destinations_end = cast(valid_jump_destinations.value.dict_ptr, DictAccess*);
    let (
        squashed_valid_jump_destinations_start, squashed_valid_jump_destinations_end
    ) = dict_squash(cast(valid_jump_destinations_start, DictAccess*), valid_jump_destinations_end);
    finalize_jumpdests(
        0,
        squashed_valid_jump_destinations_start,
        squashed_valid_jump_destinations_end,
        evm.value.message.value.code,
    );
    tempvar new_valid_jump_destinations = SetUint(
        new SetUintStruct(
            cast(squashed_valid_jump_destinations_start, SetUintDictAccess*),
            cast(squashed_valid_jump_destinations_end, SetUintDictAccess*),
        ),
    );

    // Squash accounts_to_delete
    let accounts_to_delete = evm.value.accounts_to_delete;
    let accounts_to_delete_start = accounts_to_delete.value.dict_ptr_start;
    let accounts_to_delete_end = cast(accounts_to_delete.value.dict_ptr, DictAccess*);
    let (new_accounts_to_delete_start, new_accounts_to_delete_end) = default_dict_finalize(
        cast(accounts_to_delete_start, DictAccess*), accounts_to_delete_end, 0
    );
    tempvar new_accounts_to_delete = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=cast(new_accounts_to_delete_start, SetAddressDictAccess*),
            dict_ptr=cast(new_accounts_to_delete_end, SetAddressDictAccess*),
        ),
    );

    // Squash accessed_addresses
    let accessed_addresses = evm.value.accessed_addresses;
    let accessed_addresses_start = accessed_addresses.value.dict_ptr_start;
    let accessed_addresses_end = cast(accessed_addresses.value.dict_ptr, DictAccess*);
    let (new_accessed_addresses_start, new_accessed_addresses_end) = default_dict_finalize(
        cast(accessed_addresses_start, DictAccess*), accessed_addresses_end, 0
    );
    tempvar new_accessed_addresses = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=cast(new_accessed_addresses_start, SetAddressDictAccess*),
            dict_ptr=cast(new_accessed_addresses_end, SetAddressDictAccess*),
        ),
    );

    // Squash accessed_storage_keys
    let accessed_storage_keys = evm.value.accessed_storage_keys;
    let accessed_storage_keys_start = accessed_storage_keys.value.dict_ptr_start;
    let accessed_storage_keys_end = cast(accessed_storage_keys.value.dict_ptr, DictAccess*);
    let (new_accessed_storage_keys_start, new_accessed_storage_keys_end) = default_dict_finalize(
        cast(accessed_storage_keys_start, DictAccess*),
        cast(accessed_storage_keys_end, DictAccess*),
        0,
    );
    tempvar new_accessed_storage_keys = SetTupleAddressBytes32(
        new SetTupleAddressBytes32Struct(
            cast(new_accessed_storage_keys_start, SetTupleAddressBytes32DictAccess*),
            cast(new_accessed_storage_keys_end, SetTupleAddressBytes32DictAccess*),
        ),
    );

    let tx_env = evm.value.message.value.tx_env;
    let transient_storage = tx_env.value.transient_storage;
    finalize_transient_storage{transient_storage=transient_storage}();
    TransactionEnvImpl.set_transient_storage{tx_env=tx_env}(transient_storage);

    // The `original_storage_tries` are specific to each transaction in the block - and as such MUST be squashed and reset
    // at the end of each execution.
    // Consequently, we must also set back the `parent_dict` of the `main_trie` to `0`
    let block_env = evm.value.message.value.block_env;
    let state = block_env.value.state;
    let original_storage_tries = state.value.original_storage_tries;
    dict_squash(
        cast(original_storage_tries.value._data.value.dict_ptr_start, DictAccess*),
        cast(original_storage_tries.value._data.value.dict_ptr, DictAccess*),
    );
    StateImpl.set_original_storage_tries{state=state}(
        TrieTupleAddressBytes32U256(cast(0, TrieTupleAddressBytes32U256Struct*))
    );
    // INVARIANT: there should not be a parent_dict to the main_trie at this point.
    assert cast(state.value._main_trie.value._data.value.parent_dict, felt) = 0;

    // Ensure the state in the block_env and tx_env is properly updated
    let message = evm.value.message;
    BlockEnvImpl.set_state{block_env=block_env}(state);
    MessageImpl.set_block_env{message=message}(block_env);
    MessageImpl.set_tx_env{message=message}(tx_env);

    // Rebind all dicts to the evm struct
    tempvar evm = Evm(
        new EvmStruct(
            pc=evm.value.pc,
            stack=new_stack,
            memory=new_memory,
            code=evm.value.code,
            gas_left=evm.value.gas_left,
            valid_jump_destinations=new_valid_jump_destinations,
            logs=evm.value.logs,
            refund_counter=evm.value.refund_counter,
            running=evm.value.running,
            message=message,
            output=evm.value.output,
            accounts_to_delete=new_accounts_to_delete,
            return_data=evm.value.return_data,
            error=evm.value.error,
            accessed_addresses=new_accessed_addresses,
            accessed_storage_keys=new_accessed_storage_keys,
        ),
    );

    return ();
}
