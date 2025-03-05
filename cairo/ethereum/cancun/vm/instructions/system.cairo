// SPDX-License-Identifier: MIT

from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    KeccakBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
)
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.math_cmp import is_le
from ethereum.cancun.vm.stack import pop, push
from ethereum.cancun.vm import incorporate_child_on_error, incorporate_child_on_success
from ethereum.cancun.vm.evm_impl import Evm, EvmStruct, EvmImpl, Message, MessageStruct
from ethereum.cancun.vm.env_impl import Environment, EnvironmentStruct, EnvImpl
from ethereum.cancun.utils.address import to_address
from starkware.cairo.common.dict_access import DictAccess
from ethereum.cancun.vm.exceptions import Revert, OutOfGasError, WriteInStaticContext
from ethereum.cancun.utils.address import compute_contract_address, compute_create2_contract_address
from ethereum.cancun.vm.memory import memory_read_bytes, expand_by, memory_write
from ethereum.cancun.vm.gas import (
    init_code_cost,
    calculate_gas_extend_memory,
    charge_gas,
    GasConstants,
    max_message_call_gas,
    calculate_message_call_gas,
)
from ethereum_types.numeric import U256, U256Struct, Uint, bool, UnionUintU256, UnionUintU256Enum
from ethereum.exceptions import EthereumException
from ethereum.cancun.utils.constants import STACK_DEPTH_LIMIT, MAX_CODE_SIZE
from ethereum.cancun.fork_types import (
    OptionalAddress,
    Address,
    SetAddress,
    SetAddressStruct,
    SetTupleAddressBytes32,
    SetAddressDictAccess,
    SetTupleAddressBytes32Struct,
    SetTupleAddressBytes32DictAccess,
)
from ethereum_types.others import (
    ListTupleU256U256,
    ListTupleU256U256Struct,
    TupleU256U256,
    TupleU256U256Struct,
)
from ethereum.cancun.state import (
    State,
    StateStruct,
    account_exists_and_is_empty,
    move_ether,
    set_account_balance,
    get_account,
    account_has_code_or_nonce,
    account_has_storage,
    increment_nonce,
    is_account_alive,
)
from ethereum_types.bytes import Bytes, BytesStruct, Bytes0
from ethereum.cancun.transactions_types import To, ToStruct
from ethereum.utils.numeric import (
    U256_from_be_bytes20,
    is_not_zero,
    ceil32,
    divmod,
    U256_to_be_bytes,
    U256_le,
    U256__eq__,
)
from legacy.utils.dict import hashdict_write, dict_copy
from starkware.cairo.common.uint256 import uint256_lt
from starkware.cairo.common.alloc import alloc
from legacy.utils.dict import hashdict_read
from cairo_core.comparison import is_zero

from ethereum.utils.hash_dicts import (
    set_address_contains,
    set_address_contains_or_add,
    set_address_add,
)

func generic_call{
    process_message_label: felt*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
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

    let (empty_data: felt*) = alloc();
    tempvar empty_data_bytes = Bytes(new BytesStruct(empty_data, 0));
    EvmImpl.set_return_data(empty_data_bytes);

    let depth_too_deep = is_zero(evm.value.message.value.depth.value - STACK_DEPTH_LIMIT);
    if (depth_too_deep != 0) {
        let gas = Uint(gas.value + evm.value.gas_left.value);
        EvmImpl.set_gas_left(gas);
        let stack = evm.value.stack;
        tempvar zero = U256(new U256Struct(0, 0));
        let err = push{stack=stack}(zero);
        EvmImpl.set_stack(stack);
        if (cast(err, felt) != 0) {
            return err;
        }
        let ok = cast(0, EthereumException*);
        return ok;
    }

    let memory = evm.value.memory;
    let calldata = memory_read_bytes{memory=memory}(memory_input_start_position, memory_input_size);
    EvmImpl.set_memory(memory);

    let env = evm.value.env;
    let state = env.value.state;
    let account = get_account{state=state}(code_address);

    EnvImpl.set_state{env=env}(state);
    EvmImpl.set_env(env);

    let code = account.value.code;

    let is_static = bool(is_staticcall.value + evm.value.message.value.is_static.value);

    // Fork the accessed_addresses dict segment
    local new_dict_ptr: DictAccess*;
    tempvar parent_dict_end = cast(evm.value.accessed_addresses.value.dict_ptr, DictAccess*);
    %{ copy_tracker_to_new_ptr %}
    tempvar child_accessed_addresses = SetAddress(
        new SetAddressStruct(
            cast(new_dict_ptr, SetAddressDictAccess*), cast(new_dict_ptr, SetAddressDictAccess*)
        ),
    );

    // Fork the accessed_storage_keys dict segment
    local new_dict_ptr: DictAccess*;
    // TODO(refactor): remove the requirement for a cast
    // explicit cast because our named variables must always be of the same type as previous
    // variables
    tempvar parent_dict_end = cast(evm.value.accessed_storage_keys.value.dict_ptr, DictAccess*);
    %{ copy_tracker_to_new_ptr %}
    tempvar child_accessed_storage_keys = SetTupleAddressBytes32(
        new SetTupleAddressBytes32Struct(
            cast(new_dict_ptr, SetTupleAddressBytes32DictAccess*),
            cast(new_dict_ptr, SetTupleAddressBytes32DictAccess*),
        ),
    );

    tempvar maybe_address = OptionalAddress(&code_address);
    tempvar child_message = Message(
        new MessageStruct(
            caller=caller,
            target=To(new ToStruct(cast(0, Bytes0*), &to)),
            current_target=to,
            gas=gas,
            value=value,
            data=calldata,
            code_address=maybe_address,
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
    // MARK: args assignment
    [ap] = range_check_ptr, ap++;
    [ap] = bitwise_ptr, ap++;
    [ap] = keccak_ptr, ap++;
    [ap] = poseidon_ptr, ap++;
    [ap] = range_check96_ptr, ap++;
    [ap] = add_mod_ptr, ap++;
    [ap] = mul_mod_ptr, ap++;
    [ap] = child_message.value, ap++;
    [ap] = env.value, ap++;

    call abs process_message_label;

    let range_check_ptr = [ap - 8];
    let bitwise_ptr = cast([ap - 7], BitwiseBuiltin*);
    let keccak_ptr = cast([ap - 6], KeccakBuiltin*);
    let poseidon_ptr = cast([ap - 5], PoseidonBuiltin*);
    let range_check96_ptr = cast([ap - 4], felt*);
    let add_mod_ptr = cast([ap - 3], ModBuiltin*);
    let mul_mod_ptr = cast([ap - 2], ModBuiltin*);
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

        tempvar evm = evm;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar keccak_ptr = keccak_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        incorporate_child_on_success(child_evm);
        EvmImpl.set_return_data(child_evm.value.output);
        let stack = evm.value.stack;
        let err = push{stack=stack}(U256(new U256Struct(1, 0)));
        EvmImpl.set_stack(stack);
        if (cast(err, felt) != 0) {
            return err;
        }

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
    memory_write{memory=memory}(memory_output_start, new_output);
    EvmImpl.set_memory(memory);

    let ok = cast(0, EthereumException*);
    return ok;
}

func call_{
    process_message_label: felt*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let stack = evm.value.stack;
    with stack {
        let (_gas, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (_to, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (value, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (memory_input_start_position, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (memory_input_size, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (memory_output_start_position, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (memory_output_size, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    let high_not_zero = is_not_zero(_gas.value.high);
    let low_too_high = is_le(2 ** 64, _gas.value.low);
    if (high_not_zero + low_too_high != 0) {
        tempvar gas = Uint(2 ** 64 - 1);
    } else {
        tempvar gas = Uint(_gas.value.low);
    }
    let gas = gas;

    // Calculate memory expansion cost
    let (data: TupleU256U256*) = alloc();
    assert data[0] = TupleU256U256(
        new TupleU256U256Struct(memory_input_start_position, memory_input_size)
    );
    assert data[1] = TupleU256U256(
        new TupleU256U256Struct(memory_output_start_position, memory_output_size)
    );
    tempvar extensions_list = ListTupleU256U256(new ListTupleU256U256Struct(data, 2));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, extensions_list);

    tempvar address_u256_ = UnionUintU256(new UnionUintU256Enum(cast(0, Uint*), _to));
    let to = to_address(address_u256_);
    let accessed_addresses = evm.value.accessed_addresses;
    let is_warm = set_address_contains_or_add{set_address=accessed_addresses}(to);
    if (is_warm != 0) {
        tempvar access_gas_cost = Uint(GasConstants.GAS_WARM_ACCESS);
    } else {
        tempvar access_gas_cost = Uint(GasConstants.GAS_COLD_ACCOUNT_ACCESS);
    }
    let access_gas_cost = access_gas_cost;
    EvmImpl.set_accessed_addresses(accessed_addresses);

    let env = evm.value.env;
    let state = env.value.state;
    let _is_account_alive = is_account_alive{state=state}(to);
    let is_value_zero = U256__eq__(value, U256(new U256Struct(0, 0)));
    let is_account_alive_or_value_zero = _is_account_alive.value + is_value_zero.value;
    if (is_account_alive_or_value_zero != 0) {
        tempvar create_gas_cost = Uint(0);
    } else {
        tempvar create_gas_cost = Uint(GasConstants.GAS_NEW_ACCOUNT);
    }
    tempvar transfer_gas_cost = Uint((1 - is_value_zero.value) * GasConstants.GAS_CALL_VALUE);

    let message_call_gas = calculate_message_call_gas(
        value,
        gas,
        evm.value.gas_left,
        extend_memory.value.cost,
        Uint(access_gas_cost.value + create_gas_cost.value + transfer_gas_cost.value),
        Uint(GasConstants.GAS_CALL_STIPEND),
    );
    let err = charge_gas(Uint(message_call_gas.value.cost.value + extend_memory.value.cost.value));
    if (cast(err, felt) != 0) {
        EnvImpl.set_state{env=env}(state);
        EvmImpl.set_env(env);
        EvmImpl.set_stack(stack);
        return err;
    }
    let value_non_zero_and_is_static = evm.value.message.value.is_static.value * (
        1 - is_value_zero.value
    );
    if (value_non_zero_and_is_static != 0) {
        EvmImpl.set_stack(stack);
        EnvImpl.set_state{env=env}(state);
        EvmImpl.set_env(env);
        tempvar err = new EthereumException(WriteInStaticContext);
        return err;
    }

    let memory = evm.value.memory;
    expand_by{memory=memory}(extend_memory.value.expand_by);
    EvmImpl.set_memory(memory);

    let sender_address = evm.value.message.value.current_target;
    let sender = get_account{state=state}(sender_address);
    EnvImpl.set_state{env=env}(state);
    EvmImpl.set_env(env);
    let sender_balance = sender.value.balance;
    let sender_has_enough_balance = U256_le(value, sender_balance);
    if (sender_has_enough_balance.value == 0) {
        let err = push{stack=stack}(U256(new U256Struct(0, 0)));
        EvmImpl.set_stack(stack);
        if (cast(err, felt) != 0) {
            return err;
        }
        let (empty_data: felt*) = alloc();
        tempvar empty_data_bytes = Bytes(new BytesStruct(empty_data, 0));
        EvmImpl.set_return_data(empty_data_bytes);
        let gas_left = Uint(evm.value.gas_left.value + message_call_gas.value.stipend.value);
        EvmImpl.set_gas_left(gas_left);
        EvmImpl.set_pc(Uint(evm.value.pc.value + 1));
        let ok = cast(0, EthereumException*);
        return ok;
    }
    EvmImpl.set_stack(stack);
    let err = generic_call(
        message_call_gas.value.stipend,
        value,
        evm.value.message.value.current_target,
        to,
        to,
        bool(1),
        bool(0),
        memory_input_start_position,
        memory_input_size,
        memory_output_start_position,
        memory_output_size,
    );
    if (cast(err, felt) != 0) {
        return err;
    }
    EvmImpl.set_pc(Uint(evm.value.pc.value + 1));
    let ok = cast(0, EthereumException*);
    return ok;
}

func callcode{
    process_message_label: felt*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let stack = evm.value.stack;
    with stack {
        let (_gas, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (_code_address, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (value, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (memory_input_start_position, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (memory_input_size, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (memory_output_start_position, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (memory_output_size, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    let (data: TupleU256U256*) = alloc();
    assert data[0] = TupleU256U256(
        new TupleU256U256Struct(memory_input_start_position, memory_input_size)
    );
    assert data[1] = TupleU256U256(
        new TupleU256U256Struct(memory_output_start_position, memory_output_size)
    );
    tempvar extensions_list = ListTupleU256U256(new ListTupleU256U256Struct(data, 2));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, extensions_list);

    tempvar address_u256_ = UnionUintU256(new UnionUintU256Enum(cast(0, Uint*), _code_address));
    let code_address = to_address(address_u256_);
    let accessed_addresses = evm.value.accessed_addresses;
    let is_warm = set_address_contains_or_add{set_address=accessed_addresses}(code_address);
    if (is_warm != 0) {
        tempvar access_gas_cost = Uint(GasConstants.GAS_WARM_ACCESS);
    } else {
        tempvar access_gas_cost = Uint(GasConstants.GAS_COLD_ACCOUNT_ACCESS);
    }
    let access_gas_cost = access_gas_cost;
    EvmImpl.set_accessed_addresses(accessed_addresses);

    let high_not_zero = is_not_zero(_gas.value.high);
    let low_too_high = is_le(2 ** 64, _gas.value.low);
    if (high_not_zero + low_too_high != 0) {
        tempvar gas = Uint(2 ** 64 - 1);
    } else {
        tempvar gas = Uint(_gas.value.low);
    }
    let gas = gas;

    let is_value_zero = U256__eq__(value, U256(new U256Struct(0, 0)));
    tempvar transfer_gas_cost = Uint((1 - is_value_zero.value) * GasConstants.GAS_CALL_VALUE);

    let message_call_gas = calculate_message_call_gas(
        value,
        gas,
        evm.value.gas_left,
        extend_memory.value.cost,
        Uint(access_gas_cost.value + transfer_gas_cost.value),
        Uint(GasConstants.GAS_CALL_STIPEND),
    );

    let err = charge_gas(Uint(message_call_gas.value.cost.value + extend_memory.value.cost.value));
    if (cast(err, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err;
    }

    let memory = evm.value.memory;
    expand_by{memory=memory}(extend_memory.value.expand_by);
    EvmImpl.set_memory(memory);

    let env = evm.value.env;
    let state = env.value.state;
    let sender_address = evm.value.message.value.current_target;
    let sender = get_account{state=state}(sender_address);
    let sender_balance = sender.value.balance;
    EnvImpl.set_state{env=env}(state);
    EvmImpl.set_env(env);

    let sender_has_enough_balance = U256_le(value, sender_balance);
    if (sender_has_enough_balance.value == 0) {
        let err = push{stack=stack}(U256(new U256Struct(0, 0)));
        EvmImpl.set_stack(stack);
        if (cast(err, felt) != 0) {
            return err;
        }
        let (empty_data: felt*) = alloc();
        tempvar empty_data_bytes = Bytes(new BytesStruct(empty_data, 0));
        EvmImpl.set_return_data(empty_data_bytes);
        let gas_left = Uint(evm.value.gas_left.value + message_call_gas.value.stipend.value);
        EvmImpl.set_gas_left(gas_left);
        EvmImpl.set_pc(Uint(evm.value.pc.value + 1));
        let ok = cast(0, EthereumException*);
        return ok;
    }

    EvmImpl.set_stack(stack);
    let err = generic_call(
        message_call_gas.value.stipend,
        value,
        sender_address,
        sender_address,
        code_address,
        bool(1),
        bool(0),
        memory_input_start_position,
        memory_input_size,
        memory_output_start_position,
        memory_output_size,
    );
    if (cast(err, felt) != 0) {
        return err;
    }

    EvmImpl.set_pc(Uint(evm.value.pc.value + 1));
    let ok = cast(0, EthereumException*);
    return ok;
}

func delegatecall{
    process_message_label: felt*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let stack = evm.value.stack;
    with stack {
        let (_gas, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (_code_address, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (memory_input_start_position, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (memory_input_size, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (memory_output_start_position, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (memory_output_size, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    let (data: TupleU256U256*) = alloc();
    assert data[0] = TupleU256U256(
        new TupleU256U256Struct(memory_input_start_position, memory_input_size)
    );
    assert data[1] = TupleU256U256(
        new TupleU256U256Struct(memory_output_start_position, memory_output_size)
    );
    tempvar extensions_list = ListTupleU256U256(new ListTupleU256U256Struct(data, 2));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, extensions_list);

    tempvar address_u256_ = UnionUintU256(new UnionUintU256Enum(cast(0, Uint*), _code_address));
    let code_address = to_address(address_u256_);
    let accessed_addresses = evm.value.accessed_addresses;
    let is_warm = set_address_contains_or_add{set_address=accessed_addresses}(code_address);
    if (is_warm != 0) {
        tempvar access_gas_cost = Uint(GasConstants.GAS_WARM_ACCESS);
    } else {
        tempvar access_gas_cost = Uint(GasConstants.GAS_COLD_ACCOUNT_ACCESS);
    }
    let access_gas_cost = access_gas_cost;
    EvmImpl.set_accessed_addresses(accessed_addresses);

    let high_not_zero = is_not_zero(_gas.value.high);
    let low_too_high = is_le(2 ** 64, _gas.value.low);
    if (high_not_zero + low_too_high != 0) {
        tempvar gas = Uint(2 ** 64 - 1);
    } else {
        tempvar gas = Uint(_gas.value.low);
    }
    let gas = gas;

    let message_call_gas = calculate_message_call_gas(
        U256(new U256Struct(0, 0)),
        gas,
        evm.value.gas_left,
        extend_memory.value.cost,
        access_gas_cost,
        Uint(GasConstants.GAS_CALL_STIPEND),
    );

    let err = charge_gas(Uint(message_call_gas.value.cost.value + extend_memory.value.cost.value));
    if (cast(err, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err;
    }

    let memory = evm.value.memory;
    expand_by{memory=memory}(extend_memory.value.expand_by);
    EvmImpl.set_memory(memory);
    EvmImpl.set_stack(stack);

    let err = generic_call(
        message_call_gas.value.stipend,
        evm.value.message.value.value,
        evm.value.message.value.caller,
        evm.value.message.value.current_target,
        code_address,
        bool(0),
        bool(0),
        memory_input_start_position,
        memory_input_size,
        memory_output_start_position,
        memory_output_size,
    );
    if (cast(err, felt) != 0) {
        return err;
    }

    EvmImpl.set_pc(Uint(evm.value.pc.value + 1));
    let ok = cast(0, EthereumException*);
    return ok;
}

func staticcall{
    process_message_label: felt*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let stack = evm.value.stack;
    with stack {
        let (_gas, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (_to, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (memory_input_start_position, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (memory_input_size, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (memory_output_start_position, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (memory_output_size, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    let (data: TupleU256U256*) = alloc();
    assert data[0] = TupleU256U256(
        new TupleU256U256Struct(memory_input_start_position, memory_input_size)
    );
    assert data[1] = TupleU256U256(
        new TupleU256U256Struct(memory_output_start_position, memory_output_size)
    );
    tempvar extensions_list = ListTupleU256U256(new ListTupleU256U256Struct(data, 2));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, extensions_list);

    tempvar address_u256_ = UnionUintU256(new UnionUintU256Enum(cast(0, Uint*), _to));
    let to = to_address(address_u256_);
    let accessed_addresses = evm.value.accessed_addresses;
    let is_warm = set_address_contains_or_add{set_address=accessed_addresses}(to);
    if (is_warm != 0) {
        tempvar access_gas_cost = Uint(GasConstants.GAS_WARM_ACCESS);
    } else {
        tempvar access_gas_cost = Uint(GasConstants.GAS_COLD_ACCOUNT_ACCESS);
    }
    let access_gas_cost = access_gas_cost;
    EvmImpl.set_accessed_addresses(accessed_addresses);

    let high_not_zero = is_not_zero(_gas.value.high);
    let low_too_high = is_le(2 ** 64, _gas.value.low);
    if (high_not_zero + low_too_high != 0) {
        tempvar gas = Uint(2 ** 64 - 1);
    } else {
        tempvar gas = Uint(_gas.value.low);
    }
    let gas = gas;

    let message_call_gas = calculate_message_call_gas(
        U256(new U256Struct(0, 0)),
        gas,
        evm.value.gas_left,
        extend_memory.value.cost,
        access_gas_cost,
        Uint(GasConstants.GAS_CALL_STIPEND),
    );

    let err = charge_gas(Uint(message_call_gas.value.cost.value + extend_memory.value.cost.value));
    if (cast(err, felt) != 0) {
        EvmImpl.set_stack(stack);
        return err;
    }

    let memory = evm.value.memory;
    expand_by{memory=memory}(extend_memory.value.expand_by);
    EvmImpl.set_memory(memory);
    EvmImpl.set_stack(stack);

    let err = generic_call(
        message_call_gas.value.stipend,
        U256(new U256Struct(0, 0)),
        evm.value.message.value.current_target,
        to,
        to,
        bool(1),
        bool(1),
        memory_input_start_position,
        memory_input_size,
        memory_output_start_position,
        memory_output_size,
    );
    if (cast(err, felt) != 0) {
        return err;
    }

    EvmImpl.set_pc(Uint(evm.value.pc.value + 1));
    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Revert operation - stop execution and revert state changes, returning data from memory
func revert{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
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
    EvmImpl.set_memory(memory);
    return revert;
}

// @notice Return operation - stop execution and return data from memory
func return_{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
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
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
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
    let is_depth_max = is_zero(evm.value.message.value.depth.value - STACK_DEPTH_LIMIT);

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
    let account_has_storage_ = account_has_storage{poseidon_ptr=poseidon_ptr, state=state}(
        contract_address
    );
    if (account_has_code_or_nonce_.value + account_has_storage_.value != 0) {
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

    // Fork the accessed_addresses dict segment
    local new_dict_ptr: DictAccess*;
    tempvar parent_dict_end = cast(evm.value.accessed_addresses.value.dict_ptr, DictAccess*);
    %{ copy_tracker_to_new_ptr %}
    tempvar child_accessed_addresses = SetAddress(
        new SetAddressStruct(
            cast(new_dict_ptr, SetAddressDictAccess*), cast(new_dict_ptr, SetAddressDictAccess*)
        ),
    );

    // Fork the accessed_storage_keys dict segment
    local new_dict_ptr: DictAccess*;
    // TODO(refactor): remove the requirement for a cast
    // explicit cast because our named variables must always be of the same type as previous
    // variables
    tempvar parent_dict_end = cast(evm.value.accessed_storage_keys.value.dict_ptr, DictAccess*);
    %{ copy_tracker_to_new_ptr %}
    tempvar child_accessed_storage_keys = SetTupleAddressBytes32(
        new SetTupleAddressBytes32Struct(
            cast(new_dict_ptr, SetTupleAddressBytes32DictAccess*),
            cast(new_dict_ptr, SetTupleAddressBytes32DictAccess*),
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
            code_address=OptionalAddress(cast(0, felt*)),
            code=call_data,
            depth=Uint(evm.value.message.value.depth.value + 1),
            should_transfer_value=bool(1),
            is_static=bool(0),
            accessed_addresses=child_accessed_addresses,
            accessed_storage_keys=child_accessed_storage_keys,
            parent_evm=evm,
        ),
    );

    // MARK: args assignment
    [ap] = range_check_ptr, ap++;
    [ap] = bitwise_ptr, ap++;
    [ap] = keccak_ptr, ap++;
    [ap] = poseidon_ptr, ap++;
    [ap] = range_check96_ptr, ap++;
    [ap] = add_mod_ptr, ap++;
    [ap] = mul_mod_ptr, ap++;
    [ap] = child_message.value, ap++;
    [ap] = env.value, ap++;

    call abs process_create_message_label;

    let range_check_ptr = [ap - 8];
    let bitwise_ptr = cast([ap - 7], BitwiseBuiltin*);
    let keccak_ptr = cast([ap - 6], KeccakBuiltin*);
    let poseidon_ptr = cast([ap - 5], PoseidonBuiltin*);
    let range_check96_ptr = cast([ap - 4], felt*);
    let add_mod_ptr = cast([ap - 3], ModBuiltin*);
    let mul_mod_ptr = cast([ap - 2], ModBuiltin*);
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

// @notice Creates a new account with associated code
func create{
    process_create_message_label: felt*,
    process_message_label: felt*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (endowment, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (memory_start_position, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
        let (memory_size, err) = pop();
        EvmImpl.set_stack(stack);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // GAS
    // Calculate memory expansion cost
    tempvar extensions_tuple = new TupleU256U256(
        new TupleU256U256Struct(memory_start_position, memory_size)
    );
    tempvar extensions_list = ListTupleU256U256(new ListTupleU256U256Struct(extensions_tuple, 1));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, extensions_list);

    // Calculate init code cost
    // Avoid overflows in gas calculations by limiting memory_size to 2**64, bound at which we
    // saturate in gas calculations.
    let high_not_zero = is_not_zero(memory_size.value.high);
    let low_too_big = is_le(2 ** 64, memory_size.value.low);
    let memory_size_oog = high_not_zero + low_too_big;
    if (memory_size_oog != 0) {
        tempvar err = new EthereumException(OutOfGasError);
        return err;
    }

    // Charge gas for CREATE operation
    // Won't overflow as bounded by (MAX_MEMORY_COST + MAX_INIT_CODE_COST) < 2**128
    let init_code_gas = init_code_cost(Uint(memory_size.value.low));
    let err = charge_gas(
        Uint(GasConstants.GAS_CREATE + extend_memory.value.cost.value + init_code_gas.value)
    );
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    let memory = evm.value.memory;
    expand_by{memory=memory}(extend_memory.value.expand_by);
    EvmImpl.set_memory(memory);

    let env = evm.value.env;
    let state = env.value.state;
    let current_target = evm.value.message.value.current_target;
    let sender = get_account{state=state}(current_target);
    EnvImpl.set_state{env=env}(state);
    EvmImpl.set_env(env);
    let contract_address = compute_contract_address(current_target, sender.value.nonce);

    let err = generic_create(
        endowment, contract_address, memory_start_position, memory_size, init_code_gas
    );
    if (cast(err, felt) != 0) {
        return err;
    }

    // PROGRAM COUNTER
    let pc = evm.value.pc;
    EvmImpl.set_pc(Uint(pc.value + 1));

    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Creates a new account with associated code using CREATE2 opcode
// Similar to CREATE but the address depends on the init_code instead of sender nonce
func create2{
    process_create_message_label: felt*,
    process_message_label: felt*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    // STACK
    let stack = evm.value.stack;
    with stack {
        let (endowment, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
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
        let (salt, err) = pop();
        EvmImpl.set_stack(stack);
        if (cast(err, felt) != 0) {
            return err;
        }
    }

    // GAS
    // Calculate memory expansion cost
    tempvar extensions_tuple = new TupleU256U256(
        new TupleU256U256Struct(memory_start_position, memory_size)
    );
    tempvar extensions_list = ListTupleU256U256(new ListTupleU256U256Struct(extensions_tuple, 1));
    let extend_memory = calculate_gas_extend_memory(evm.value.memory, extensions_list);

    // Calculate init code cost and keccak word cost
    // Avoid overflows in gas calculations by limiting memory_size to 2**64, bound at which we
    // saturate in gas calculations.
    let high_not_zero = is_not_zero(memory_size.value.high);
    let low_too_big = is_le(2 ** 64, memory_size.value.low);
    let memory_size_oog = high_not_zero + low_too_big;
    if (memory_size_oog != 0) {
        tempvar err = new EthereumException(OutOfGasError);
        return err;
    }

    let init_code_gas = init_code_cost(Uint(memory_size.value.low));
    let ceiled_memory_size = ceil32(Uint(memory_size.value.low));
    let call_data_words = ceiled_memory_size.value / 32;
    let keccak_cost = GasConstants.GAS_KECCAK256_WORD * call_data_words;

    // Charge gas for CREATE2 operation
    // wont overflow because:
    // keccak_cost <= 3e18
    // extend_memory.cost <= 1e32
    // init_code_gas <= 1e17
    let err = charge_gas(
        Uint(
            GasConstants.GAS_CREATE + extend_memory.value.cost.value + init_code_gas.value +
            keccak_cost,
        ),
    );
    if (cast(err, felt) != 0) {
        return err;
    }

    // OPERATION
    let memory = evm.value.memory;
    expand_by{memory=memory}(extend_memory.value.expand_by);
    let call_data = memory_read_bytes{memory=memory}(memory_start_position, memory_size);
    EvmImpl.set_memory(memory);

    let current_target = evm.value.message.value.current_target;
    let salt_bytes32 = U256_to_be_bytes(salt);
    let contract_address = compute_create2_contract_address(
        current_target, salt_bytes32, call_data
    );

    let err = generic_create(
        endowment, contract_address, memory_start_position, memory_size, init_code_gas
    );
    if (cast(err, felt) != 0) {
        return err;
    }

    // PROGRAM COUNTER
    let pc = evm.value.pc;
    EvmImpl.set_pc(Uint(pc.value + 1));

    let ok = cast(0, EthereumException*);
    return ok;
}

// @notice Halt execution and register account for later deletion
func selfdestruct{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    // STACK
    let stack = evm.value.stack;
    with stack {
        let (beneficiary_u256, err) = pop();
        if (cast(err, felt) != 0) {
            EvmImpl.set_stack(stack);
            return err;
        }
    }

    // GAS
    tempvar beneficiary_u256_ = UnionUintU256(
        new UnionUintU256Enum(cast(0, Uint*), beneficiary_u256)
    );
    let beneficiary = to_address(beneficiary_u256_);
    let accessed_addresses = evm.value.accessed_addresses;
    let is_warm = set_address_contains_or_add{set_address=accessed_addresses}(beneficiary);
    tempvar base_gas_cost = Uint(GasConstants.GAS_SELF_DESTRUCT);
    if (is_warm != 0) {
        tempvar gas_cost = base_gas_cost;
    } else {
        tempvar gas_cost = Uint(base_gas_cost.value + GasConstants.GAS_COLD_ACCOUNT_ACCESS);
    }
    let gas_cost = gas_cost;
    EvmImpl.set_accessed_addresses(accessed_addresses);

    // Check if beneficiary account is alive and originator has balance
    let env = evm.value.env;
    let state = env.value.state;
    let originator = evm.value.message.value.current_target;
    let originator_account = get_account{state=state}(originator);
    let originator_balance = originator_account.value.balance;
    let originator_balance_zero_low = is_zero(originator_balance.value.low);
    let originator_balance_zero_high = is_zero(originator_balance.value.high);
    let originator_balance_zero = originator_balance_zero_low * originator_balance_zero_high;
    let beneficiary_is_alive = is_account_alive{state=state}(beneficiary);

    // Add additional gas cost if beneficiary not alive and originator has balance
    let is_new_account = (1 - beneficiary_is_alive.value) * (1 - originator_balance_zero);
    if (is_new_account != 0) {
        // Wont't overflow as all components are < 25k
        tempvar final_gas_cost = Uint(gas_cost.value + GasConstants.GAS_SELF_DESTRUCT_NEW_ACCOUNT);
    } else {
        tempvar final_gas_cost = gas_cost;
    }

    let err = charge_gas(final_gas_cost);
    if (cast(err, felt) != 0) {
        EnvImpl.set_state{env=env}(state);
        EvmImpl.set_env(env);
        EvmImpl.set_stack(stack);
        return err;
    }

    // OPERATION
    if (evm.value.message.value.is_static.value != 0) {
        EnvImpl.set_state{env=env}(state);
        EvmImpl.set_env(env);
        EvmImpl.set_stack(stack);
        tempvar err = new EthereumException(WriteInStaticContext);
        return err;
    }

    move_ether{state=state}(originator, beneficiary, originator_balance);

    // Register account for deletion if created in same transaction
    let created_accounts = env.value.state.value.created_accounts;
    let is_created = set_address_contains{set=created_accounts}(originator);
    tempvar state = State(
        new StateStruct(
            _main_trie=state.value._main_trie,
            _storage_tries=state.value._storage_tries,
            created_accounts=created_accounts,
            original_storage_tries=state.value.original_storage_tries,
        ),
    );

    if (is_created != 0) {
        // Set originator balance to 0
        tempvar zero_balance = U256(new U256Struct(0, 0));
        set_account_balance{state=state}(originator, zero_balance);

        // Add to accounts to delete
        let accounts_to_delete = evm.value.accounts_to_delete;
        set_address_add{set_address=accounts_to_delete}(originator);
        EvmImpl.set_accounts_to_delete(accounts_to_delete);
        tempvar evm = evm;
        tempvar state = state;
        tempvar poseidon_ptr = poseidon_ptr;
    } else {
        tempvar evm = evm;
        tempvar state = state;
        tempvar poseidon_ptr = poseidon_ptr;
    }
    let evm = Evm(cast([ap - 3], EvmStruct*));

    // Mark beneficiary as touched if empty
    let is_empty = account_exists_and_is_empty{state=state}(beneficiary);
    if (is_empty.value != 0) {
        let touched_accounts = evm.value.touched_accounts;
        set_address_add{set_address=touched_accounts}(beneficiary);
        EvmImpl.set_touched_accounts(touched_accounts);
        tempvar evm = evm;
        tempvar state = state;
        tempvar poseidon_ptr = poseidon_ptr;
    } else {
        tempvar evm = evm;
        tempvar state = state;
        tempvar poseidon_ptr = poseidon_ptr;
    }

    // Stop execution
    EvmImpl.set_running(bool(0));
    EnvImpl.set_state{env=env}(state);
    EvmImpl.set_env(env);
    EvmImpl.set_stack(stack);

    let ok = cast(0, EthereumException*);
    return ok;
}
