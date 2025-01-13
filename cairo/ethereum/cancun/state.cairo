from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc

from ethereum.cancun.fork_types import (
    Address,
    Account,
    MappingAddressAccount,
    SetAddress,
    EMPTY_ACCOUNT,
)
from ethereum.cancun.trie import (
    TrieBytes32U256,
    TrieAddressAccount,
    trie_get_TrieAddressAccount,
    trie_get_TrieBytes32U256,
    AccountStruct,
    TrieBytes32U256Struct,
)
from ethereum_types.bytes import Bytes, Bytes32
from src.utils.dict import hashdict_read, hashdict_write
from ethereum_types.numeric import U256, U256Struct

struct AddressTrieBytes32U256DictAccess {
    key: Address,
    prev_value: TrieBytes32U256,
    new_value: TrieBytes32U256,
}

struct MappingAddressTrieBytes32U256Struct {
    dict_ptr_start: AddressTrieBytes32U256DictAccess*,
    dict_ptr: AddressTrieBytes32U256DictAccess*,
    // In case this is a copy of a previous dict,
    // this field points to the address of the original mapping.
    original_mapping: MappingAddressTrieBytes32U256Struct*,
}

struct MappingAddressTrieBytes32U256 {
    value: MappingAddressTrieBytes32U256Struct*,
}

struct TupleTrieAddressAccountMappingAddressTrieBytes32U256Struct {
    trie_address_account: TrieAddressAccount,
    mapping_address_trie: MappingAddressTrieBytes32U256,
}

struct TupleTrieAddressAccountMappingAddressTrieBytes32U256 {
    value: TupleTrieAddressAccountMappingAddressTrieBytes32U256Struct*,
}

struct ListTupleTrieAddressAccountMappingAddressTrieBytes32U256Struct {
    data: TupleTrieAddressAccountMappingAddressTrieBytes32U256*,
    len: felt,
}

struct ListTupleTrieAddressAccountMappingAddressTrieBytes32U256 {
    value: ListTupleTrieAddressAccountMappingAddressTrieBytes32U256Struct*,
}

struct TransientStorageSnapshotsStruct {
    data: MappingAddressTrieBytes32U256*,
    len: felt,
}

struct TransientStorageSnapshots {
    value: TransientStorageSnapshotsStruct*,
}

struct TransientStorageStruct {
    _tries: MappingAddressTrieBytes32U256,
    _snapshots: TransientStorageSnapshots,
}

struct TransientStorage {
    value: TransientStorageStruct*,
}

struct StateStruct {
    _main_trie: TrieAddressAccount,
    _storage_tries: MappingAddressTrieBytes32U256,
    _snapshots: ListTupleTrieAddressAccountMappingAddressTrieBytes32U256,
    created_accounts: SetAddress,
}

struct State {
    value: StateStruct*,
}

using OptionalAccount = Account;
func get_account_optional{poseidon_ptr: PoseidonBuiltin*, state: State}(
    address: Address
) -> OptionalAccount {
    let trie = state.value._main_trie;
    with trie {
        let account = trie_get_TrieAddressAccount(address);
    }

    return account;
}

func get_account{poseidon_ptr: PoseidonBuiltin*, state: State}(address: Address) -> Account {
    let account = get_account_optional{state=state}(address);

    if (cast(account.value, felt) == 0) {
        let empty_account = EMPTY_ACCOUNT();
        return empty_account;
    }

    return account;
}

func get_storage{poseidon_ptr: PoseidonBuiltin*, state: State}(
    address: Address, key: Bytes32
) -> U256 {
    alloc_locals;
    let storage_tries = state.value._storage_tries;

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let storage_tries_dict_ptr = cast(storage_tries.value.dict_ptr, DictAccess*);

    let (pointer) = hashdict_read{poseidon_ptr=poseidon_ptr, dict_ptr=storage_tries_dict_ptr}(
        1, &address.value
    );

    if (cast(pointer, felt) == 0) {
        // Early return if no associated Trie at address
        let new_storage_tries_dict_ptr = cast(
            storage_tries_dict_ptr, AddressTrieBytes32U256DictAccess*
        );
        tempvar storage_tries = MappingAddressTrieBytes32U256(
            new MappingAddressTrieBytes32U256Struct(
                dict_ptr_start=storage_tries.value.dict_ptr_start,
                dict_ptr=new_storage_tries_dict_ptr,
                original_mapping=storage_tries.value.original_mapping,
            ),
        );
        tempvar state = State(
            new StateStruct(
                _main_trie=state.value._main_trie,
                _storage_tries=storage_tries,
                _snapshots=state.value._snapshots,
                created_accounts=state.value.created_accounts,
            ),
        );

        tempvar res = U256(new U256Struct(0, 0));
        return res;
    }

    let storage_trie_ptr = cast(pointer, TrieBytes32U256Struct*);
    let storage_trie = TrieBytes32U256(storage_trie_ptr);
    let value = trie_get_TrieBytes32U256{poseidon_ptr=poseidon_ptr, trie=storage_trie}(key);

    // Rebind the storage trie to the state
    let new_storage_trie_ptr = cast(storage_trie_ptr, felt);

    hashdict_write{poseidon_ptr=poseidon_ptr, dict_ptr=storage_tries_dict_ptr}(
        1, &address.value, new_storage_trie_ptr
    );

    let new_storage_tries_dict_ptr = cast(
        storage_tries_dict_ptr, AddressTrieBytes32U256DictAccess*
    );
    tempvar storage_tries = MappingAddressTrieBytes32U256(
        new MappingAddressTrieBytes32U256Struct(
            dict_ptr_start=storage_tries.value.dict_ptr_start,
            dict_ptr=new_storage_tries_dict_ptr,
            original_mapping=storage_tries.value.original_mapping,
        ),
    );
    tempvar state = State(
        new StateStruct(
            _main_trie=state.value._main_trie,
            _storage_tries=storage_tries,
            _snapshots=state.value._snapshots,
            created_accounts=state.value.created_accounts,
        ),
    );

    return value;
}
