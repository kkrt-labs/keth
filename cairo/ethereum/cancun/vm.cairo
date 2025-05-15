from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.dict import DictAccess
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.alloc import alloc
from ethereum.cancun.blocks import TupleLog, TupleLogStruct, Log
from ethereum.cancun.fork_types import (
    SetAddress,
    SetAddressStruct,
    SetAddressDictAccess,
    SetTupleAddressBytes32,
    SetTupleAddressBytes32Struct,
    SetTupleAddressBytes32DictAccess,
)
from ethereum_types.numeric import Uint
from ethereum.cancun.vm.runtime import finalize_jumpdests
// cairo-lint: disable
from ethereum.cancun.vm.stack import Stack
from starkware.cairo.common.memcpy import memcpy
from legacy.utils.dict import dict_update, squash_and_update, default_dict_finalize, dict_squash
from ethereum.cancun.trie import (
    init_tries,
    TrieBytesOptionalUnionBytesLegacyTransaction,
    TrieBytesOptionalUnionBytesReceipt,
    TrieBytesOptionalUnionBytesWithdrawal,
)
from ethereum.cancun.vm.evm_impl import Evm, EvmStruct
from ethereum_types.numeric import U64
from ethereum_types.bytes import TupleBytes, TupleBytesStruct, Bytes

struct BlockOutputStruct {
    block_gas_used: Uint,
    transactions_trie: TrieBytesOptionalUnionBytesLegacyTransaction,
    receipts_trie: TrieBytesOptionalUnionBytesReceipt,
    receipt_keys: TupleBytes,
    block_logs: TupleLog,
    withdrawals_trie: TrieBytesOptionalUnionBytesWithdrawal,
    blob_gas_used: U64,
}

struct BlockOutput {
    value: BlockOutputStruct*,
}

func empty_block_output() -> BlockOutput {
    let (transactions_trie, receipts_trie, withdrawals_trie) = init_tries();
    let (logs: Log*) = alloc();
    tempvar block_logs = TupleLog(new TupleLogStruct(data=logs, len=0));
    let (receipt_keys: Bytes*) = alloc();
    tempvar tuple_receipt_keys = TupleBytes(new TupleBytesStruct(data=receipt_keys, len=0));


    tempvar block_output = BlockOutput(
        new BlockOutputStruct(
            block_gas_used=Uint(0),
            transactions_trie=transactions_trie,
            receipts_trie=receipts_trie,
            receipt_keys=tuple_receipt_keys,
            block_logs=block_logs,
            withdrawals_trie=withdrawals_trie,
            blob_gas_used=U64(0),
        ),
    );

    return block_output;
}

// @notice Incorporates the child EVM in its parent in case of a successful execution.
// @dev This merges the current logs, accounts_to_delete, accessed addresses and storage keys into the parent.
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
            valid_jump_destinations=evm.value.valid_jump_destinations,
            logs=new_logs,
            refund_counter=new_refund_counter,
            running=evm.value.running,
            message=evm.value.message,
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

// @notice Incorporates the child EVM in its parent in case of an error.
// @dev This squashes and drops the current logs, accounts_to_delete, accessed
// addresses and storage keys that are no longer used.
// @dev The transient storage and state have been handled in `rollback_transaction`, in which we squashed the segment
// and appended the (key, prev_value, prev_value) pairs to the parent's state and transient storage segments.
func incorporate_child_on_error{range_check_ptr, poseidon_ptr: PoseidonBuiltin*, evm: Evm}(
    child_evm: Evm
) {
    alloc_locals;

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
    let parent_accessed_storage_keys = evm.value.accessed_storage_keys;
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

    let new_gas_left = Uint(evm.value.gas_left.value + child_evm.value.gas_left.value);

    tempvar evm = Evm(
        new EvmStruct(
            pc=evm.value.pc,
            stack=evm.value.stack,
            memory=evm.value.memory,
            code=evm.value.code,
            gas_left=new_gas_left,
            valid_jump_destinations=evm.value.valid_jump_destinations,
            logs=evm.value.logs,
            refund_counter=evm.value.refund_counter,
            running=evm.value.running,
            message=evm.value.message,
            output=evm.value.output,
            accounts_to_delete=evm.value.accounts_to_delete,
            return_data=evm.value.return_data,
            error=evm.value.error,
            accessed_addresses=new_accessed_addresses,
            accessed_storage_keys=new_accessed_storage_keys,
        ),
    );

    return ();
}
