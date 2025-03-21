from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.dict import DictAccess
from starkware.cairo.common.registers import get_fp_and_pc
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
from ethereum.exceptions import EthereumException
from ethereum_types.bytes import Bytes, Bytes0, Bytes32
from ethereum_types.numeric import Uint
from ethereum.cancun.state import State, TransientStorage
from ethereum.cancun.vm.runtime import finalize_jumpdests
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
    default_dict_finalize,
    dict_squash,
)
from ethereum.cancun.vm.evm_impl import EvmImpl, Evm, EvmStruct
from ethereum.cancun.vm.env_impl import EnvImpl

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

    // Merge child's accessed_addresses into parent
    tempvar parent_accessed_addresses = evm.value.accessed_addresses;
    let (new_accessed_addresses_start, new_accessed_addresses_end) = dict_update(
        cast(child_evm.value.accessed_addresses.value.dict_ptr_start, DictAccess*),
        cast(child_evm.value.accessed_addresses.value.dict_ptr, DictAccess*),
        cast(parent_accessed_addresses.value.dict_ptr_start, DictAccess*),
        cast(parent_accessed_addresses.value.dict_ptr, DictAccess*),
        drop=0,
    );

    tempvar new_accessed_addresses = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=cast(new_accessed_addresses_start, SetAddressDictAccess*),
            dict_ptr=cast(new_accessed_addresses_end, SetAddressDictAccess*),
        ),
    );

    // Merge child's accessed_storage_keys into parent
    let parent_accessed_storage_keys = evm.value.accessed_storage_keys;
    let (new_accessed_storage_keys_start, new_accessed_storage_keys_end) = dict_update(
        cast(child_evm.value.accessed_storage_keys.value.dict_ptr_start, DictAccess*),
        cast(child_evm.value.accessed_storage_keys.value.dict_ptr, DictAccess*),
        cast(parent_accessed_storage_keys.value.dict_ptr_start, DictAccess*),
        cast(parent_accessed_storage_keys.value.dict_ptr, DictAccess*),
        drop=0,
    );

    tempvar new_accessed_storage_keys = SetTupleAddressBytes32(
        new SetTupleAddressBytes32Struct(
            dict_ptr_start=cast(new_accessed_storage_keys_start, SetTupleAddressBytes32DictAccess*),
            dict_ptr=cast(new_accessed_storage_keys_end, SetTupleAddressBytes32DictAccess*),
        ),
    );

    // Squash dropped dicts
    default_dict_finalize(
        cast(child_evm.value.stack.value.dict_ptr_start, DictAccess*),
        cast(child_evm.value.stack.value.dict_ptr, DictAccess*),
        0,
    );

    default_dict_finalize(
        cast(child_evm.value.memory.value.dict_ptr_start, DictAccess*),
        cast(child_evm.value.memory.value.dict_ptr, DictAccess*),
        0,
    );

    let (
        squashed_valid_jump_destinations_start, squashed_valid_jump_destinations_end
    ) = dict_squash(
        cast(child_evm.value.valid_jump_destinations.value.dict_ptr_start, DictAccess*),
        cast(child_evm.value.valid_jump_destinations.value.dict_ptr, DictAccess*),
    );
    finalize_jumpdests(
        0,
        squashed_valid_jump_destinations_start,
        squashed_valid_jump_destinations_end,
        child_evm.value.message.value.code,
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
    default_dict_finalize(
        cast(child_touched_accounts_start, DictAccess*),
        cast(child_touched_accounts_end, DictAccess*),
        0,
    );

    // Drop child's accessed_addresses
    tempvar parent_accessed_addresses = evm.value.accessed_addresses;
    let child_accessed_addresses_start = child_evm.value.accessed_addresses.value.dict_ptr_start;
    let child_accessed_addresses_end = child_evm.value.accessed_addresses.value.dict_ptr;
    let (new_accessed_addresses_start, new_accessed_addresses_end) = dict_update(
        cast(child_accessed_addresses_start, DictAccess*),
        cast(child_accessed_addresses_end, DictAccess*),
        cast(parent_accessed_addresses.value.dict_ptr_start, DictAccess*),
        cast(parent_accessed_addresses.value.dict_ptr, DictAccess*),
        drop=1,
    );
    tempvar new_accessed_addresses = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=cast(new_accessed_addresses_start, SetAddressDictAccess*),
            dict_ptr=cast(new_accessed_addresses_end, SetAddressDictAccess*),
        ),
    );

    // Drop child's accessed_storage_keys
    tempvar parent_accessed_storage_keys = evm.value.accessed_storage_keys;
    let child_accessed_storage_keys_start = child_evm.value.accessed_storage_keys.value.dict_ptr_start;
    let child_accessed_storage_keys_end = child_evm.value.accessed_storage_keys.value.dict_ptr;
    let (new_accessed_storage_keys_start, new_accessed_storage_keys_end) = dict_update(
        cast(child_accessed_storage_keys_start, DictAccess*),
        cast(child_accessed_storage_keys_end, DictAccess*),
        cast(parent_accessed_storage_keys.value.dict_ptr_start, DictAccess*),
        cast(parent_accessed_storage_keys.value.dict_ptr, DictAccess*),
        drop=1,
    );
    tempvar new_accessed_storage_keys = SetTupleAddressBytes32(
        new SetTupleAddressBytes32Struct(
            dict_ptr_start=cast(new_accessed_storage_keys_start, SetTupleAddressBytes32DictAccess*),
            dict_ptr=cast(new_accessed_storage_keys_end, SetTupleAddressBytes32DictAccess*),
        ),
    );

    let accounts_to_delete = child_evm.value.accounts_to_delete;
    let accounts_to_delete_start = accounts_to_delete.value.dict_ptr_start;
    let accounts_to_delete_end = cast(accounts_to_delete.value.dict_ptr, DictAccess*);
    default_dict_finalize(cast(accounts_to_delete_start, DictAccess*), accounts_to_delete_end, 0);

    let valid_jump_destinations = child_evm.value.valid_jump_destinations;
    let valid_jump_destinations_start = valid_jump_destinations.value.dict_ptr_start;
    let valid_jump_destinations_end = cast(valid_jump_destinations.value.dict_ptr, DictAccess*);
    let (
        squashed_valid_jump_destinations_start, squashed_valid_jump_destinations_end
    ) = dict_squash(cast(valid_jump_destinations_start, DictAccess*), valid_jump_destinations_end);
    finalize_jumpdests(
        0,
        squashed_valid_jump_destinations_start,
        squashed_valid_jump_destinations_end,
        child_evm.value.message.value.code,
    );

    let stack = child_evm.value.stack;
    let stack_start = stack.value.dict_ptr_start;
    let stack_end = cast(stack.value.dict_ptr, DictAccess*);
    default_dict_finalize(cast(stack_start, DictAccess*), cast(stack_end, DictAccess*), 0);

    let memory = child_evm.value.memory;
    let memory_start = memory.value.dict_ptr_start;
    let memory_end = cast(memory.value.dict_ptr, DictAccess*);
    default_dict_finalize(cast(memory_start, DictAccess*), cast(memory_end, DictAccess*), 0);

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
            accessed_addresses=new_accessed_addresses,
            accessed_storage_keys=new_accessed_storage_keys,
        ),
    );

    return ();
}
