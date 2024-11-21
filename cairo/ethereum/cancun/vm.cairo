from ethereum.base_types import U64, U256, Bytes, Bytes0, Bytes32, Uint, Dict, TupleDict, DictAccess
from ethereum.crypto.hash import Hash32, TupleHash32
from ethereum.cancun.blocks import Log, TupleLog
from ethereum.cancun.fork_types import (
    Address,
    VersionedHash,
    OptionalAddress,
    OptionalException,
    TupleAddress,
)
from ethereum.cancun.state import State, TransientStorage, account_exists_and_is_empty
from ethereum.cancun.vm.precompiled_contracts import RIPEMD160_ADDRESS
from ethereum.cancun.transactions import To

struct Environment {
    caller: Address,
    block_hashes: TupleHash32,
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
    traces: TupleDict,
    excess_blob_gas: U64,
    blob_versioned_hashes: TupleVersionedHash,
    transient_storage: TransientStorage,
}

struct AccessedStorageKeyStruct {
    address: Address,
    key: Bytes32,
}

struct AccessedStorageKey {
    value: AccessedStorageKeyStruct*,
}

struct TupleAccessedStorageKeyStruct {
    value: AccessedStorageKey*,
    len: felt,
}

struct Message {
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
    accessed_addresses: TupleAddress,
    accessed_storage_keys: TupleAccessedStorageKey,
    parent_evm: OptionalEvm,
}

struct ValidJumpDestinationsStruct {
    value: Dict,
}

struct ValidJumpDestinations {
    value: ValidJumpDestinationsStruct*,
}

struct StackStruct {
    value: Dict,
    size: felt,
}

struct Stack {
    value: StackStruct*,
}

struct Evm {
    pc: Uint,
    stack: Stack,
    memory: Bytes,
    code: Bytes,
    gas_left: Uint,
    env: Environment,
    valid_jump_destinations: ValidJumpDestinations,
    logs: TupleLog,
    refund_counter: felt,
    running: bool,
    message: Message,
    output: Bytes,
    accounts_to_delete: TupleAddress,
    touched_accounts: TupleAddress,
    return_data: Bytes,
    error: OptionalException,
    accessed_addresses: TupleAddress,
    accessed_storage_keys: TupleAccessedStorageKey,
}

struct OptionalEvmStruct {
    is_some: bool,
    value: Evm*,
}

struct OptionalEvm {
    value: OptionalEvmStruct*,
}

func incorporate_child_on_success(evm: Evm, child_evm: Evm) {
    let gas_left = evm.gas_left.value + child_evm.gas_left.value;
    let logs_len = evm.logs.value.len + child_evm.logs.value.len;
    memcpy(evm.logs.value.value, child_evm.logs.value.value, logs_len);
    let logs = TupleLog(new TupleLogStruct(evm.logs.value.value, logs_len));

    let refund_counter = evm.refund_counter + child_evm.refund_counter;

    let accounts_to_delete_len = evm.accounts_to_delete.value.len +
        child_evm.accounts_to_delete.value.len;
    memcpy(
        evm.accounts_to_delete.value.value,
        child_evm.accounts_to_delete.value.value,
        accounts_to_delete_len,
    );
    let accounts_to_delete = TupleAddress(
        new TupleAddressStruct(evm.accounts_to_delete.value.value, accounts_to_delete_len)
    );

    let touched_accounts_len = evm.touched_accounts.value.len +
        child_evm.touched_accounts.value.len;
    memcpy(
        evm.touched_accounts.value.value,
        child_evm.touched_accounts.value.value,
        touched_accounts_len,
    );
    let touched_accounts = TupleAddress(
        new TupleAddressStruct(evm.touched_accounts.value.value, touched_accounts_len)
    );
}

func incorporate_child_on_error(evm: Evm, child_evm: Evm) {
    // Implementation:
    // if RIPEMD160_ADDRESS in child_evm.touched_accounts:
    // evm.touched_accounts.add(RIPEMD160_ADDRESS)
    // evm.touched_accounts.add(RIPEMD160_ADDRESS)
    // if child_evm.message.current_target == RIPEMD160_ADDRESS:
    // if account_exists_and_is_empty(evm.env.state, child_evm.message.current_target):
    // evm.touched_accounts.add(RIPEMD160_ADDRESS)
    // if account_exists_and_is_empty(evm.env.state, child_evm.message.current_target):
    // evm.touched_accounts.add(RIPEMD160_ADDRESS)
    // evm.touched_accounts.add(RIPEMD160_ADDRESS)
    // evm.gas_left += child_evm.gas_left
}
