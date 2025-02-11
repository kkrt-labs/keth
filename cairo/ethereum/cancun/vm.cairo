from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from ethereum.cancun.blocks import Log, TupleLog, TupleLogStruct
from ethereum.cancun.fork_types import (
    Address,
    OptionalAddress,
    ListHash32,
    SetAddress,
    SetAddressStruct,
    SetAddressDictAccess,
    TupleAddressBytes32,
    SetTupleAddressBytes32,
    SetTupleAddressBytes32Struct,
    SetTupleAddressBytes32DictAccess,
    TupleVersionedHash,
    VersionedHash,
)
from ethereum.cancun.state import State, TransientStorage
from ethereum.exceptions import EthereumException
from ethereum_types.bytes import Bytes, Bytes0, Bytes32
from ethereum_types.numeric import U64, U256, Uint, bool, SetUint
from ethereum.cancun.transactions_types import To
from ethereum.cancun.vm.stack import Stack
from ethereum.cancun.state import account_exists_and_is_empty
from ethereum.cancun.vm.memory import Memory
from cairo_core.comparison import is_zero
from starkware.cairo.common.memcpy import memcpy
from legacy.utils.dict import (
    hashdict_write,
    hashdict_read,
    dict_update,
    squash_and_update,
    dict_squash,
)
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.dict import DictAccess

from legacy.utils.utils import Helpers

using OptionalEvm = Evm;

struct EnvironmentStruct {
    caller: Address,
    block_hashes: ListHash32,
    origin: Address,
    coinbase: Address,
    number: Uint,
    base_fee_per_gas: Uint,
    gas_limit: Uint,
    gas_price: Uint,
    time: U256,
    prev_randao: Bytes32,
    state: State,
    chain_id: U64,
    excess_blob_gas: U64,
    blob_versioned_hashes: TupleVersionedHash,
    transient_storage: TransientStorage,
}

struct Environment {
    value: EnvironmentStruct*,
}

struct Message {
    value: MessageStruct*,
}

struct EvmStruct {
    pc: Uint,
    stack: Stack,
    memory: Memory,
    code: Bytes,
    gas_left: Uint,
    env: Environment,
    valid_jump_destinations: SetUint,
    logs: TupleLog,
    refund_counter: felt,
    running: bool,
    message: Message,
    output: Bytes,
    accounts_to_delete: SetAddress,
    touched_accounts: SetAddress,
    return_data: Bytes,
    error: EthereumException*,
    accessed_addresses: SetAddress,
    accessed_storage_keys: SetTupleAddressBytes32,
}

struct Evm {
    value: EvmStruct*,
}

struct MessageStruct {
    caller: Address,
    target: To,
    current_target: Address,
    gas: Uint,
    value: U256,
    data: Bytes,
    code_address: OptionalAddress,
    code: Bytes,
    depth: Uint,
    should_transfer_value: bool,
    is_static: bool,
    accessed_addresses: SetAddress,
    accessed_storage_keys: SetTupleAddressBytes32,
    parent_evm: OptionalEvm,
}

// @notice Incorporates the child EVM in its parent in case of a successful execution.
// @dev This merges the current logs, touched_accounts, accounts_to_delete, accessed addresses and storage keys into the parent.
// @dev The transient storage and state have been handled in `commit_transaction`, in which we
// dict accesses to the parent's state and transient storage segments.
func incorporate_child_on_success{range_check_ptr, poseidon_ptr: PoseidonBuiltin*, evm: Evm}(
    child_evm: Evm
) {
    alloc_locals;

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let new_gas_left = Uint(evm.value.gas_left.value + child_evm.value.gas_left.value);

    let dst = evm.value.logs.value.data + evm.value.logs.value.len;
    let src = child_evm.value.logs.value.data;
    let len = child_evm.value.logs.value.len;
    memcpy(dst, src, len);
    tempvar new_logs = TupleLog(
        new TupleLogStruct(data=evm.value.logs.value.data, len=evm.value.logs.value.len + len)
    );

    // 30M block gas, at least 5k gas per SSTORE, max 6k SSTOREs per block, meaning at most 6000 * 4800 = 28.8M refund counter
    // thus this won't overflow.
    let new_refund_counter = evm.value.refund_counter + child_evm.value.refund_counter;

    // Squash & update touched_accounts into parent
    let child_touched_accounts_start = child_evm.value.touched_accounts.value.dict_ptr_start;
    let child_touched_accounts_end = child_evm.value.touched_accounts.value.dict_ptr;
    let touched_accounts = evm.value.touched_accounts;
    let touched_accounts_end = touched_accounts.value.dict_ptr;
    let new_touched_accounts_end = squash_and_update(
        cast(child_touched_accounts_start, DictAccess*),
        cast(child_touched_accounts_end, DictAccess*),
        cast(touched_accounts_end, DictAccess*),
    );

    // Check if child message target account exists and is empty
    let env = evm.value.env;
    let state = env.value.state;
    let exists_and_is_empty = account_exists_and_is_empty{state=state}(
        child_evm.value.message.value.current_target
    );
    if (exists_and_is_empty.value != 0) {
        hashdict_write{dict_ptr=new_touched_accounts_end}(
            1, &child_evm.value.message.value.current_target.value, 1
        );
    } else {
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar new_touched_accounts_end = new_touched_accounts_end;
    }
    let poseidon_ptr = cast([ap - 2], PoseidonBuiltin*);
    let new_touched_accounts_end = cast([ap - 1], DictAccess*);
    EnvImpl.set_state{env=env}(state);

    tempvar new_touched_accounts = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=cast(touched_accounts.value.dict_ptr_start, SetAddressDictAccess*),
            dict_ptr=cast(new_touched_accounts_end, SetAddressDictAccess*),
        ),
    );

    // Squash & update accounts_to_delete into parent
    let accounts_to_delete = evm.value.accounts_to_delete;
    let accounts_to_delete_start = accounts_to_delete.value.dict_ptr_start;
    let accounts_to_delete_end = accounts_to_delete.value.dict_ptr;
    let new_accounts_to_delete_end = squash_and_update(
        cast(child_evm.value.accounts_to_delete.value.dict_ptr_start, DictAccess*),
        cast(child_evm.value.accounts_to_delete.value.dict_ptr, DictAccess*),
        cast(accounts_to_delete_end, DictAccess*),
    );
    tempvar new_accounts_to_delete = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=cast(accounts_to_delete_start, SetAddressDictAccess*),
            dict_ptr=cast(new_accounts_to_delete_end, SetAddressDictAccess*),
        ),
    );

    // Squash & update accessed_addresses into parent
    let accessed_addresses = evm.value.accessed_addresses;
    let accessed_addresses_start = accessed_addresses.value.dict_ptr_start;
    let accessed_addresses_end = accessed_addresses.value.dict_ptr;
    let new_accessed_addresses_end = squash_and_update(
        cast(child_evm.value.accessed_addresses.value.dict_ptr_start, DictAccess*),
        cast(child_evm.value.accessed_addresses.value.dict_ptr, DictAccess*),
        cast(accessed_addresses_end, DictAccess*),
    );

    tempvar new_accessed_addresses = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=cast(accessed_addresses_start, SetAddressDictAccess*),
            dict_ptr=cast(new_accessed_addresses_end, SetAddressDictAccess*),
        ),
    );

    // Squash & update accessed_storage_keys into parent
    let accessed_storage_keys = evm.value.accessed_storage_keys;
    let accessed_storage_keys_start = accessed_storage_keys.value.dict_ptr_start;
    let accessed_storage_keys_end = accessed_storage_keys.value.dict_ptr;
    let new_accessed_storage_keys_end = squash_and_update(
        cast(child_evm.value.accessed_storage_keys.value.dict_ptr_start, DictAccess*),
        cast(child_evm.value.accessed_storage_keys.value.dict_ptr, DictAccess*),
        cast(accessed_storage_keys_end, DictAccess*),
    );

    tempvar new_accessed_storage_keys = SetTupleAddressBytes32(
        new SetTupleAddressBytes32Struct(
            dict_ptr_start=cast(accessed_storage_keys_start, SetTupleAddressBytes32DictAccess*),
            dict_ptr=cast(new_accessed_storage_keys_end, SetTupleAddressBytes32DictAccess*),
        ),
    );

    // Squash dropped dicts
    dict_squash(
        cast(child_evm.value.stack.value.dict_ptr_start, DictAccess*),
        cast(child_evm.value.stack.value.dict_ptr, DictAccess*),
    );

    dict_squash(
        cast(child_evm.value.memory.value.dict_ptr_start, DictAccess*),
        cast(child_evm.value.memory.value.dict_ptr, DictAccess*),
    );

    let (
        squashed_valid_jump_destinations_start, squashed_valid_jump_destinations_end
    ) = dict_squash(
        cast(child_evm.value.valid_jump_destinations.value.dict_ptr_start, DictAccess*),
        cast(child_evm.value.valid_jump_destinations.value.dict_ptr, DictAccess*),
    );
    Helpers.finalize_jumpdests(
        0,
        cast(squashed_valid_jump_destinations_start, DictAccess*),
        cast(squashed_valid_jump_destinations_end, DictAccess*),
        child_evm.value.message.value.code.value.data,
    );

    // No need to squash the message's `accessed_addresses` and `accessed_storage_keys` because
    // they were moved into the Evm, which we just squashed.

    // No need to squash the env's `state` and `transient_storage` because it was handled in `commit_transaction`,
    // when we squashed and appended the prev keys to the parent's state and transient storage segments.

    tempvar evm = Evm(
        new EvmStruct(
            pc=evm.value.pc,
            stack=evm.value.stack,
            memory=evm.value.memory,
            code=evm.value.code,
            gas_left=new_gas_left,
            env=env,
            valid_jump_destinations=evm.value.valid_jump_destinations,
            logs=new_logs,
            refund_counter=new_refund_counter,
            running=evm.value.running,
            message=evm.value.message,
            output=evm.value.output,
            accounts_to_delete=new_accounts_to_delete,
            touched_accounts=new_touched_accounts,
            return_data=evm.value.return_data,
            error=evm.value.error,
            accessed_addresses=new_accessed_addresses,
            accessed_storage_keys=new_accessed_storage_keys,
        ),
    );

    return ();
}

// @notice Incorporates the child EVM in its parent in case of an error.
// @dev This squashes and drops the current logs, touched_accounts, accounts_to_delete, accessed
// addresses and storage keys that are no longer used.
// @dev The transient storage and state have been handled in `rollback_transaction`, in which we squashed the segment
// and appended the (key, prev_value, prev_value) pairs to the parent's state and transient storage segments.
func incorporate_child_on_error{range_check_ptr, poseidon_ptr: PoseidonBuiltin*, evm: Evm}(
    child_evm: Evm
) {
    alloc_locals;

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    // Special handling for RIPEMD160 precompile address (0x3)
    // TODO: unless we want to retro-prove all blocks, we could remove this logic.
    // In block 2675119, the empty account at 0x3 (the RIPEMD160 precompile) was
    // cleared despite running out of gas. This is an obscure edge case that can
    // only happen to a precompile.
    // According to the general rules governing clearing of empty accounts, the
    // touch should have been reverted. Due to client bugs, this event went
    // unnoticed and 0x3 has been exempted from the rule that touches are
    // reverted in order to preserve this historical behaviour.

    // TODO: Move this to precompiled_contracts.cairo
    const RIPEMD160_ADDRESS = 0x0300000000000000000000000000000000000000;

    // Check if RIPEMD160 address is in child's touched accounts
    let child_touched_accounts = child_evm.value.touched_accounts;
    let child_touched_accounts_start = child_touched_accounts.value.dict_ptr_start;
    let child_touched_accounts_end = cast(child_touched_accounts.value.dict_ptr, DictAccess*);
    let (ripemd_touched) = hashdict_read{dict_ptr=child_touched_accounts_end}(
        1, new RIPEMD160_ADDRESS
    );

    // Soundness requirement: squash all child dicts - including ones from message and env.

    // EVM //
    dict_squash(
        cast(child_touched_accounts_start, DictAccess*),
        cast(child_touched_accounts_end, DictAccess*),
    );

    let child_accessed_addresses = child_evm.value.accessed_addresses;
    let child_accessed_addresses_start = child_accessed_addresses.value.dict_ptr_start;
    let child_accessed_addresses_end = cast(child_accessed_addresses.value.dict_ptr, DictAccess*);
    dict_squash(cast(child_accessed_addresses_start, DictAccess*), child_accessed_addresses_end);

    let child_accessed_storage_keys = child_evm.value.accessed_storage_keys;
    let child_accessed_storage_keys_start = child_accessed_storage_keys.value.dict_ptr_start;
    let child_accessed_storage_keys_end = cast(
        child_accessed_storage_keys.value.dict_ptr, DictAccess*
    );
    dict_squash(
        cast(child_accessed_storage_keys_start, DictAccess*),
        cast(child_accessed_storage_keys_end, DictAccess*),
    );

    let accounts_to_delete = child_evm.value.accounts_to_delete;
    let accounts_to_delete_start = accounts_to_delete.value.dict_ptr_start;
    let accounts_to_delete_end = cast(accounts_to_delete.value.dict_ptr, DictAccess*);
    dict_squash(cast(accounts_to_delete_start, DictAccess*), accounts_to_delete_end);

    let valid_jump_destinations = child_evm.value.valid_jump_destinations;
    let valid_jump_destinations_start = valid_jump_destinations.value.dict_ptr_start;
    let valid_jump_destinations_end = cast(valid_jump_destinations.value.dict_ptr, DictAccess*);
    let (
        squashed_valid_jump_destinations_start, squashed_valid_jump_destinations_end
    ) = dict_squash(cast(valid_jump_destinations_start, DictAccess*), valid_jump_destinations_end);
    Helpers.finalize_jumpdests(
        0,
        cast(squashed_valid_jump_destinations_start, DictAccess*),
        cast(squashed_valid_jump_destinations_end, DictAccess*),
        child_evm.value.message.value.code.value.data,
    );

    let stack = child_evm.value.stack;
    let stack_start = stack.value.dict_ptr_start;
    let stack_end = cast(stack.value.dict_ptr, DictAccess*);
    dict_squash(cast(stack_start, DictAccess*), cast(stack_end, DictAccess*));

    let memory = child_evm.value.memory;
    let memory_start = memory.value.dict_ptr_start;
    let memory_end = cast(memory.value.dict_ptr, DictAccess*);
    dict_squash(cast(memory_start, DictAccess*), cast(memory_end, DictAccess*));

    // No need to squash the message's `accessed_addresses` and `accessed_storage_keys` because
    // they are the same segments as the ones in the EVM, which we just squashed.

    // No need to squash the env's `state` and `transient_storage` because it was handled in `rollback_transaction`,
    // when we squashed and appended the prev keys to the parent's state and transient storage segments.

    // Check if child message target is RIPEMD160 address
    let is_ripemd_target = is_zero(
        child_evm.value.message.value.current_target.value - RIPEMD160_ADDRESS
    );
    if (is_ripemd_target != 0) {
        let env = evm.value.env;
        let state = env.value.state;
        let exists_and_is_empty = account_exists_and_is_empty{state=state}(
            child_evm.value.message.value.current_target
        );
        EnvImpl.set_state{env=env}(state);
        EvmImpl.set_env(env);
        tempvar evm = evm;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar write_ripemd = exists_and_is_empty.value + ripemd_touched;
    } else {
        tempvar evm = evm;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar write_ripemd = ripemd_touched;
    }
    let evm_ = cast([ap - 3], EvmStruct*);
    let poseidon_ptr = cast([ap - 2], PoseidonBuiltin*);
    let write_ripemd = [ap - 1];
    tempvar evm = Evm(evm_);

    let touched_accounts = evm.value.touched_accounts;
    let touched_accounts_end = cast(touched_accounts.value.dict_ptr, DictAccess*);

    if (write_ripemd != 0) {
        hashdict_write{dict_ptr=touched_accounts_end}(1, new RIPEMD160_ADDRESS, 1);
    } else {
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar touched_accounts_end = touched_accounts_end;
    }
    let poseidon_ptr = cast([ap - 2], PoseidonBuiltin*);
    let new_touched_accounts_end = cast([ap - 1], DictAccess*);

    tempvar new_touched_accounts = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=cast(touched_accounts.value.dict_ptr_start, SetAddressDictAccess*),
            dict_ptr=cast(new_touched_accounts_end, SetAddressDictAccess*),
        ),
    );
    let new_gas_left = Uint(evm.value.gas_left.value + child_evm.value.gas_left.value);

    tempvar evm = Evm(
        new EvmStruct(
            pc=evm.value.pc,
            stack=evm.value.stack,
            memory=evm.value.memory,
            code=evm.value.code,
            gas_left=new_gas_left,
            env=evm.value.env,
            valid_jump_destinations=evm.value.valid_jump_destinations,
            logs=evm.value.logs,
            refund_counter=evm.value.refund_counter,
            running=evm.value.running,
            message=evm.value.message,
            output=evm.value.output,
            accounts_to_delete=evm.value.accounts_to_delete,
            touched_accounts=new_touched_accounts,
            return_data=evm.value.return_data,
            error=evm.value.error,
            accessed_addresses=evm.value.accessed_addresses,
            accessed_storage_keys=evm.value.accessed_storage_keys,
        ),
    );

    return ();
}

namespace EvmImpl {
    func set_pc{evm: Evm}(new_pc: Uint) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=new_pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_stack{evm: Evm}(new_stack: Stack) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=new_stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_memory{evm: Evm}(new_memory: Memory) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=new_memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_code{evm: Evm}(new_code: Bytes) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=new_code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_gas_left{evm: Evm}(new_gas_left: Uint) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=new_gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_env{evm: Evm}(new_env: Environment) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=new_env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_valid_jump_destinations{evm: Evm}(new_valid_jump_destinations: SetUint) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=new_valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_logs{evm: Evm}(new_logs: TupleLog) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=new_logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_refund_counter{evm: Evm}(new_refund_counter: felt) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=new_refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_running{evm: Evm}(new_running: bool) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=new_running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_message{evm: Evm}(new_message: Message) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=new_message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_output{evm: Evm}(new_output: Bytes) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=new_output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_accounts_to_delete{evm: Evm}(new_accounts_to_delete: SetAddress) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=new_accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_touched_accounts{evm: Evm}(new_touched_accounts: SetAddress) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=new_touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_return_data{evm: Evm}(new_return_data: Bytes) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=new_return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_error{evm: Evm}(new_error: EthereumException*) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=new_error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_accessed_addresses{evm: Evm}(new_accessed_addresses: SetAddress) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=new_accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_accessed_storage_keys{evm: Evm}(new_accessed_storage_keys: SetTupleAddressBytes32) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=new_accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_pc_stack{evm: Evm}(new_pc: Uint, new_stack: Stack) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=new_pc,
                stack=new_stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_pc_stack_memory{evm: Evm}(new_pc: Uint, new_stack: Stack, new_memory: Memory) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=new_pc,
                stack=new_stack,
                memory=new_memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }
}

namespace EnvImpl {
    func set_state{env: Environment}(new_state: State) {
        tempvar env = Environment(
            new EnvironmentStruct(
                caller=env.value.caller,
                block_hashes=env.value.block_hashes,
                origin=env.value.origin,
                coinbase=env.value.coinbase,
                number=env.value.number,
                base_fee_per_gas=env.value.base_fee_per_gas,
                gas_limit=env.value.gas_limit,
                gas_price=env.value.gas_price,
                time=env.value.time,
                prev_randao=env.value.prev_randao,
                state=new_state,
                chain_id=env.value.chain_id,
                excess_blob_gas=env.value.excess_blob_gas,
                blob_versioned_hashes=env.value.blob_versioned_hashes,
                transient_storage=env.value.transient_storage,
            ),
        );
        return ();
    }

    func set_transient_storage{env: Environment}(new_transient_storage: TransientStorage) {
        tempvar env = Environment(
            new EnvironmentStruct(
                caller=env.value.caller,
                block_hashes=env.value.block_hashes,
                origin=env.value.origin,
                coinbase=env.value.coinbase,
                number=env.value.number,
                base_fee_per_gas=env.value.base_fee_per_gas,
                gas_limit=env.value.gas_limit,
                gas_price=env.value.gas_price,
                time=env.value.time,
                prev_randao=env.value.prev_randao,
                state=env.value.state,
                chain_id=env.value.chain_id,
                excess_blob_gas=env.value.excess_blob_gas,
                blob_versioned_hashes=env.value.blob_versioned_hashes,
                transient_storage=new_transient_storage,
            ),
        );
        return ();
    }
}
