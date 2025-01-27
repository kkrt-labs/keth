// SPDX-License-Identifier: MIT

from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin, PoseidonBuiltin
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.math_cmp import is_le
from ethereum.cancun.vm.stack import pop, push
from ethereum.cancun.vm import (
    Evm,
    EvmImpl,
    EvmStruct,
    EnvImpl,
    Message,
    MessageStruct,
    incorporate_child_on_error,
    incorporate_child_on_success,
)
from starkware.cairo.common.dict_access import DictAccess
from ethereum.cancun.vm.exceptions import Revert, OutOfGasError, WriteInStaticContext
from ethereum.cancun.utils.address import compute_contract_address, compute_create2_contract_address
from ethereum.cancun.vm.memory import memory_read_bytes, expand_by, memory_write
from ethereum.cancun.vm.gas import (
    calculate_gas_extend_memory,
    charge_gas,
    GasConstants,
    max_message_call_gas,
)
from ethereum_types.numeric import U256, U256Struct, Uint, bool
from ethereum.exceptions import EthereumException
from ethereum.cancun.utils.constants import STACK_DEPTH_LIMIT, MAX_CODE_SIZE
from ethereum.utils.numeric import U256_le, is_zero, U256_from_be_bytes20
from ethereum.cancun.fork_types import (
    Address,
    SetAddress,
    SetAddressStruct,
    SetTupleAddressBytes32,
    SetAddressDictAccess,
    SetTupleAddressBytes32Struct,
    SetTupleAddressBytes32DictAccess,
)
from ethereum_types.bytes import Bytes, BytesStruct, Bytes0
from ethereum.cancun.state import get_account, account_has_code_or_nonce, increment_nonce
from ethereum.cancun.transactions import To, ToStruct
from src.utils.dict import hashdict_write, dict_copy
from starkware.cairo.common.uint256 import uint256_lt
from starkware.cairo.common.alloc import alloc

from ethereum_types.others import (
    ListTupleU256U256,
    ListTupleU256U256Struct,
    TupleU256U256,
    TupleU256U256Struct,
)

func generic_call{
    process_message_label: felt*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}(
    gas: Uint,
    value: U256,
    caller: Address,
    to: Address,
    code_address: Address,
    should_transfer_value: bool,
    is_staticcall: bool,
    memory_input_start_position: U256,
    memory_input_size: U256,
    memory_output_start: U256,
    memory_output_size: U256,
) -> EthereumException* {
    alloc_locals;
    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    tempvar return_data = Bytes(new BytesStruct(cast(0, felt*), 0));
    EvmImpl.set_return_data(return_data);

    let depth_too_deep = is_le(STACK_DEPTH_LIMIT, evm.value.message.value.depth.value);
    if (depth_too_deep != 0) {
        let gas = Uint(gas.value + evm.value.gas_left.value);
        EvmImpl.set_gas_left(gas);
        let stack = evm.value.stack;
        tempvar zero = U256(new U256Struct(0, 0));
        let err = push{stack=stack}(zero);
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let ok = cast(0, EthereumException*);
        return ok;
    }

    let memory = evm.value.memory;
    with memory {
        let calldata = memory_read_bytes(memory_input_start_position, memory_input_size);
    }
    EvmImpl.set_memory(memory);
    let env = evm.value.env;
    let state = env.value.state;
    let account = get_account{state=state}(code_address);
    EnvImpl.set_state{env=env}(state);
    EvmImpl.set_env(env);
    let code = account.value.code;

    if (is_staticcall.value != 0) {
        tempvar is_static = bool(1);
    } else {
        tempvar is_static = evm.value.message.value.is_static;
    }
    let is_static = is_static;

    // TODO: this could be optimized using a non-copy mechanism.
    let (accessed_addresses_copy_start, accessed_addresses_copy) = dict_copy(
        cast(evm.value.accessed_addresses.value.dict_ptr_start, DictAccess*),
        cast(evm.value.accessed_addresses.value.dict_ptr, DictAccess*),
    );
    let (accessed_storage_keys_copy_start, accessed_storage_keys_copy) = dict_copy(
        cast(evm.value.accessed_storage_keys.value.dict_ptr_start, DictAccess*),
        cast(evm.value.accessed_storage_keys.value.dict_ptr, DictAccess*),
    );
    tempvar child_accessed_addresses = SetAddress(
        new SetAddressStruct(
            cast(accessed_addresses_copy_start, SetAddressDictAccess*),
            cast(accessed_addresses_copy, SetAddressDictAccess*),
        ),
    );
    tempvar child_accessed_storage_keys = SetTupleAddressBytes32(
        new SetTupleAddressBytes32Struct(
            cast(accessed_storage_keys_copy_start, SetTupleAddressBytes32DictAccess*),
            cast(accessed_storage_keys_copy, SetTupleAddressBytes32DictAccess*),
        ),
    );

    tempvar child_message = Message(
        new MessageStruct(
            caller=caller,
            target=To(new ToStruct(cast(0, Bytes0*), &to)),
            current_target=to,
            gas=gas,
            value=value,
            data=calldata,
            code_address=&code_address,
            code=code,
            depth=Uint(evm.value.message.value.depth.value + 1),
            should_transfer_value=should_transfer_value,
            is_static=is_static,
            accessed_addresses=child_accessed_addresses,
            accessed_storage_keys=child_accessed_storage_keys,
            parent_evm=evm,
        ),
    );

    // prepare arguments to jump to process_message
    [ap] = range_check_ptr, ap++;
    [ap] = bitwise_ptr, ap++;
    [ap] = keccak_ptr, ap++;
    [ap] = poseidon_ptr, ap++;
    [ap] = child_message.value, ap++;
    [ap] = env.value, ap++;

    call abs process_message_label;

    let range_check_ptr = [ap - 6];
    let bitwise_ptr = cast([ap - 5], BitwiseBuiltin*);
    let keccak_ptr = cast([ap - 4], KeccakBuiltin*);
    let poseidon_ptr = cast([ap - 3], PoseidonBuiltin*);
    let child_evm_ = cast([ap - 2], EvmStruct*);
    let err = cast([ap - 1], EthereumException*);
    tempvar child_evm = Evm(child_evm_);

    if (cast(err, felt) != 0) {
        // TODO: <https://github.com/kkrt-labs/keth/issues/568> we still need to drop dicts and get the child evm state etc
        return err;
    }

    // The previous operations have mutated the `env` passed to the function, which
    // is now located in child_evm.value.env. Notably, we must rebind env.state and env.transient_storage
    // to their new mutated values. The reset is handled on a per-case basis in incorporate_child.
    let updated_state = child_evm.value.env.value.state;
    let updated_transient_storage = child_evm.value.env.value.transient_storage;
    let old_env = evm.value.env;
    EnvImpl.set_state{env=old_env}(updated_state);
    EnvImpl.set_transient_storage{env=old_env}(updated_transient_storage);
    EvmImpl.set_env{evm=evm}(old_env);

    if (cast(child_evm.value.error, felt) != 0) {
        incorporate_child_on_error(child_evm);
        EvmImpl.set_return_data(child_evm.value.output);
        let stack = evm.value.stack;
        push{stack=stack}(U256(new U256Struct(0, 0)));
        EvmImpl.set_stack(stack);

        tempvar evm = evm;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar keccak_ptr = keccak_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar evm = evm;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar keccak_ptr = keccak_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }
    let evm = evm;
    let poseidon_ptr = poseidon_ptr;
    let keccak_ptr = keccak_ptr;
    let bitwise_ptr = bitwise_ptr;
    let range_check_ptr = range_check_ptr;

    incorporate_child_on_success(child_evm);
    EvmImpl.set_return_data(child_evm.value.output);
    let stack = evm.value.stack;
    push{stack=stack}(U256(new U256Struct(1, 0)));
    EvmImpl.set_stack(stack);

    let len = child_evm.value.output.value.len;
    assert [range_check_ptr] = len;
    let range_check_ptr = range_check_ptr + 1;
    tempvar child_output_len = U256(new U256Struct(len, 0));
    let output_size_is_le = U256_le(memory_output_size, child_output_len);
    if (output_size_is_le.value != 0) {
        tempvar actual_output_size = memory_output_size;
    } else {
        tempvar actual_output_size = child_output_len;
    }
    let actual_output_size = actual_output_size;
    let memory = evm.value.memory;
    tempvar new_output = Bytes(
        new BytesStruct(child_evm.value.output.value.data, actual_output_size.value.low)
    );
    // This is safe because the gas cost associated with memory_output_start and memory_output_size
    // are checked in outer functions.
    with memory {
        memory_write(memory_output_start, new_output);
    }
    EvmImpl.set_memory(memory);

    // TODO: drop stack and memory from child_evm
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Revert operation - stop execution and revert state changes, returning data from memory
func revert{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (memory_start_index, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (size, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    // GAS
    // Calculate memory expansion cost
    // If size > 2**128 - 1, OutOfGasError
    if (size.value.high != 0) {
        EvmImpl.set_stack(stack);
        tempvar err = new EthereumException(OutOfGasError);
        return err;
    }
    tempvar extensions_tuple = new TupleU256U256(new TupleU256U256Struct(memory_start_index, size));
    tempvar extensions_list = ListTupleU256U256(new ListTupleU256U256Struct(extensions_tuple, 1));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, extensions_list);

    let err = charge_gas(Uint(extend_memory.value.cost.value));
    if (cast(err, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err;
    }

    // OPERATION
    let memory = evm.value.memory;
    with memory {
        expand_by(extend_memory.value.expand_by);
        let output = memory_read_bytes(memory_start_index, size);
        EvmImpl.set_output(output);
    }

    // Raise revert
    tempvar revert = new EthereumException(Revert);
    EvmImpl.set_stack(stack);
    return revert;
}

// @notice Return operation - stop execution and return data from memory
func return_{range_check_ptr, evm: Evm}() -> EthereumException* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (memory_start_position, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (memory_size, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    // GAS
    // Calculate memory expansion cost
    // If memory_size > 2**128 - 1, OutOfGasError
    if (memory_size.value.high != 0) {
        EvmImpl.set_stack(stack);
        tempvar err = new EthereumException(OutOfGasError);
        return err;
    }

    tempvar extensions_tuple = new TupleU256U256(
        new TupleU256U256Struct(memory_start_position, memory_size)
    );
    tempvar extensions_list = ListTupleU256U256(new ListTupleU256U256Struct(extensions_tuple, 1));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, extensions_list);

    let err = charge_gas(Uint(GasConstants.GAS_ZERO + extend_memory.value.cost.value));
    if (cast(err, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err;
    }

    // OPERATION
    let memory = evm.value.memory;
    with memory {
        expand_by(extend_memory.value.expand_by);
        let output = memory_read_bytes(memory_start_position, memory_size);
        EvmImpl.set_output(output);
    }

    // Stop execution
    EvmImpl.set_running(bool(0));
    EvmImpl.set_memory(memory);
    EvmImpl.set_stack(stack);
    let ok = cast(0, EthereumException*);
    return ok;
}

func generic_create{
    process_create_message_label: felt*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    evm: Evm,
}(
    endowment: U256,
    contract_address: Address,
    memory_start_position: U256,
    memory_size: U256,
    init_code_gas: Uint,
) -> EthereumException* {
    alloc_locals;

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let memory = evm.value.memory;
    let call_data = memory_read_bytes{memory=memory}(memory_start_position, memory_size);
    EvmImpl.set_memory(memory);

    let is_gt_two_max_code_size = is_le(2 * MAX_CODE_SIZE + 1, call_data.value.len);
    if (is_gt_two_max_code_size != 0) {
        tempvar err = new EthereumException(OutOfGasError);
        return err;
    }

    let accessed_addresses = evm.value.accessed_addresses;
    let accessed_addresses_end = cast(accessed_addresses.value.dict_ptr, DictAccess*);
    hashdict_write{dict_ptr=accessed_addresses_end}(1, &contract_address, 1);

    tempvar new_accessed_addresses = SetAddress(
        new SetAddressStruct(
            accessed_addresses.value.dict_ptr_start,
            cast(accessed_addresses_end, SetAddressDictAccess*),
        ),
    );
    EvmImpl.set_accessed_addresses(new_accessed_addresses);

    let create_message_gas = max_message_call_gas(evm.value.gas_left);
    let new_gas_left = evm.value.gas_left.value - create_message_gas.value;
    EvmImpl.set_gas_left(Uint(new_gas_left));

    if (evm.value.message.value.is_static.value != 0) {
        tempvar err = new EthereumException(WriteInStaticContext);
        return err;
    }
    let (empty_data: felt*) = alloc();
    tempvar empty_data_bytes = Bytes(new BytesStruct(empty_data, 0));
    EvmImpl.set_return_data(empty_data_bytes);

    let env = evm.value.env;
    let state = env.value.state;
    let sender_address = evm.value.message.value.current_target;
    let sender = get_account{state=state}(sender_address);

    let (sender_balance_not_enough) = uint256_lt([sender.value.balance.value], [endowment.value]);
    let sender_nonce_max = is_zero(sender.value.nonce.value - (2 ** 64 - 1));
    let is_depth_max = is_zero((evm.value.message.value.depth.value + 1) - STACK_DEPTH_LIMIT);

    let is_invalid = sender_balance_not_enough + sender_nonce_max + is_depth_max;
    if (is_invalid != 0) {
        let new_gas_left = evm.value.gas_left.value + create_message_gas.value;
        EvmImpl.set_gas_left(Uint(new_gas_left));
        tempvar zero = U256(new U256Struct(0, 0));
        let stack = evm.value.stack;
        let err = push{stack=stack}(zero);
        EnvImpl.set_state{env=env}(state);
        EvmImpl.set_env(env);
        EvmImpl.set_stack(stack);
        if (cast(err, felt) != 0) {
            return err;
        }
        tempvar ok = cast(0, EthereumException*);
        return ok;
    }

    let account_has_code_or_nonce_ = account_has_code_or_nonce{state=state}(contract_address);
    if (account_has_code_or_nonce_.value != 0) {
        increment_nonce{state=state}(evm.value.message.value.current_target);
        tempvar zero = U256(new U256Struct(0, 0));
        let stack = evm.value.stack;
        let err = push{stack=stack}(zero);
        EnvImpl.set_state{env=env}(state);
        EvmImpl.set_env(env);
        EvmImpl.set_stack(stack);
        if (cast(err, felt) != 0) {
            return err;
        }
        tempvar ok = cast(0, EthereumException*);
        return ok;
    }

    increment_nonce{state=state}(evm.value.message.value.current_target);
    EnvImpl.set_state{env=env}(state);
    EvmImpl.set_env(env);

    // TODO: this could be optimized using a non-copy mechanism.
    let (accessed_addresses_copy_start, accessed_addresses_copy) = dict_copy(
        cast(evm.value.accessed_addresses.value.dict_ptr_start, DictAccess*),
        cast(evm.value.accessed_addresses.value.dict_ptr, DictAccess*),
    );
    let (accessed_storage_keys_copy_start, accessed_storage_keys_copy) = dict_copy(
        cast(evm.value.accessed_storage_keys.value.dict_ptr_start, DictAccess*),
        cast(evm.value.accessed_storage_keys.value.dict_ptr, DictAccess*),
    );
    tempvar child_accessed_addresses = SetAddress(
        new SetAddressStruct(
            cast(accessed_addresses_copy_start, SetAddressDictAccess*),
            cast(accessed_addresses_copy, SetAddressDictAccess*),
        ),
    );
    tempvar child_accessed_storage_keys = SetTupleAddressBytes32(
        new SetTupleAddressBytes32Struct(
            cast(accessed_storage_keys_copy_start, SetTupleAddressBytes32DictAccess*),
            cast(accessed_storage_keys_copy, SetTupleAddressBytes32DictAccess*),
        ),
    );
    tempvar to = To(new ToStruct(new Bytes0(0), cast(0, Address*)));
    tempvar child_message = Message(
        new MessageStruct(
            caller=evm.value.message.value.current_target,
            target=to,
            current_target=contract_address,
            gas=create_message_gas,
            value=endowment,
            data=empty_data_bytes,
            code_address=cast(0, Address*),
            code=call_data,
            depth=Uint(evm.value.message.value.depth.value + 1),
            should_transfer_value=bool(1),
            is_static=bool(0),
            accessed_addresses=child_accessed_addresses,
            accessed_storage_keys=child_accessed_storage_keys,
            parent_evm=evm,
        ),
    );

    [ap] = range_check_ptr, ap++;
    [ap] = bitwise_ptr, ap++;
    [ap] = keccak_ptr, ap++;
    [ap] = poseidon_ptr, ap++;
    [ap] = child_message.value, ap++;
    [ap] = env.value, ap++;

    call abs process_create_message_label;

    let range_check_ptr = [ap - 5];
    let bitwise_ptr = cast([ap - 4], BitwiseBuiltin*);
    let keccak_ptr = cast([ap - 3], KeccakBuiltin*);
    let poseidon_ptr = cast([ap - 2], PoseidonBuiltin*);
    let child_evm_ = cast([ap - 1], EvmStruct*);
    tempvar child_evm = Evm(child_evm_);

    // The previous operations have mutated the `env` passed to the function, which
    // is now located in child_evm.value.env. Notably, we must rebind env.state and env.transient_storage
    // to their new mutated values. The reset is handled on a per-case basis in incorporate_child.
    let updated_state = child_evm.value.env.value.state;
    let updated_transient_storage = child_evm.value.env.value.transient_storage;
    let old_env = evm.value.env;
    EnvImpl.set_state{env=old_env}(updated_state);
    EnvImpl.set_transient_storage{env=old_env}(updated_transient_storage);
    EvmImpl.set_env{evm=evm}(old_env);

    if (cast(child_evm.value.error, felt) != 0) {
        incorporate_child_on_error(child_evm);
        EvmImpl.set_return_data(child_evm.value.output);
        let stack = evm.value.stack;
        let err = push{stack=stack}(U256(new U256Struct(0, 0)));
        EvmImpl.set_stack(stack);
        if (cast(err, felt) != 0) {
            return err;
        }
        tempvar ok = cast(0, EthereumException*);
        return ok;
    }

    incorporate_child_on_success(child_evm);
    EvmImpl.set_return_data(empty_data_bytes);
    let stack = evm.value.stack;
    let to_push = U256_from_be_bytes20(child_evm.value.message.value.current_target);
    let err = push{stack=stack}(to_push);
    EvmImpl.set_stack(stack);
    if (cast(err, felt) != 0) {
        return err;
    }
    tempvar ok = cast(0, EthereumException*);
    return ok;
}
