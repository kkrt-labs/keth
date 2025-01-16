from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.dict import dict_new
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.math import assert_not_zero

from ethereum.cancun.fork_types import (
    Address,
    Account,
    OptionalAccount,
    MappingAddressAccount,
    SetAddress,
    EMPTY_ACCOUNT,
    MappingBytes32U256,
    MappingBytes32U256Struct,
    Bytes32U256DictAccess,
)
from ethereum.cancun.trie import (
    TrieBytes32U256,
    TrieAddressOptionalAccount,
    trie_get_TrieAddressOptionalAccount,
    trie_set_TrieAddressOptionalAccount,
    trie_get_TrieBytes32U256,
    trie_set_TrieBytes32U256,
    AccountStruct,
    TrieBytes32U256Struct,
    TrieAddressOptionalAccountStruct,
)
from ethereum_types.bytes import Bytes, Bytes32
from ethereum_types.numeric import U256, U256Struct, Bool, bool

from src.utils.dict import hashdict_read, hashdict_write, hashdict_get

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

struct TupleTrieAddressOptionalAccountMappingAddressTrieBytes32U256Struct {
    trie_address_account: TrieAddressOptionalAccount,
    mapping_address_trie: MappingAddressTrieBytes32U256,
}

struct TupleTrieAddressOptionalAccountMappingAddressTrieBytes32U256 {
    value: TupleTrieAddressOptionalAccountMappingAddressTrieBytes32U256Struct*,
}

struct ListTupleTrieAddressOptionalAccountMappingAddressTrieBytes32U256Struct {
    data: TupleTrieAddressOptionalAccountMappingAddressTrieBytes32U256*,
    len: felt,
}

struct ListTupleTrieAddressOptionalAccountMappingAddressTrieBytes32U256 {
    value: ListTupleTrieAddressOptionalAccountMappingAddressTrieBytes32U256Struct*,
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
    _main_trie: TrieAddressOptionalAccount,
    _storage_tries: MappingAddressTrieBytes32U256,
    _snapshots: ListTupleTrieAddressOptionalAccountMappingAddressTrieBytes32U256,
    created_accounts: SetAddress,
}

struct State {
    value: StateStruct*,
}

func get_account_optional{poseidon_ptr: PoseidonBuiltin*, state: State}(
    address: Address
) -> OptionalAccount {
    let trie = state.value._main_trie;
    with trie {
        let account = trie_get_TrieAddressOptionalAccount(address);
    }

    return account;
}

func get_account{poseidon_ptr: PoseidonBuiltin*, state: State}(address: Address) -> Account {
    let account = get_account_optional{state=state}(address);

    if (cast(account.value, felt) == 0) {
        let empty_account = EMPTY_ACCOUNT();
        return empty_account;
    }

    tempvar res = Account(account.value);
    return res;
}

func set_account{poseidon_ptr: PoseidonBuiltin*, state: State}(
    address: Address, account: OptionalAccount
) {
    let trie = state.value._main_trie;
    with trie {
        trie_set_TrieAddressOptionalAccount(address, account);
    }
    tempvar state = State(
        new StateStruct(
            _main_trie=trie,
            _storage_tries=state.value._storage_tries,
            _snapshots=state.value._snapshots,
            created_accounts=state.value.created_accounts,
        ),
    );
    return ();
}

func get_storage{poseidon_ptr: PoseidonBuiltin*, state: State}(
    address: Address, key: Bytes32
) -> U256 {
    alloc_locals;
    let storage_tries = state.value._storage_tries;

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let storage_tries_dict_ptr = cast(storage_tries.value.dict_ptr, DictAccess*);

    // Use `hashdict_get` instead of `hashdict_read` because `MappingAddressTrieBytes32U256` is not a
    // `default_dict`. Accessing a key that does not exist in the dict would have panicked for `hashdict_read`.
    let (pointer) = hashdict_get{poseidon_ptr=poseidon_ptr, dict_ptr=storage_tries_dict_ptr}(
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
    let new_storage_trie_ptr = cast(storage_trie.value, felt);

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

func set_storage{poseidon_ptr: PoseidonBuiltin*, state: State}(
    address: Address, key: Bytes32, value: U256
) {
    alloc_locals;

    let storage_tries = state.value._storage_tries;
    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    // Assert that the account exists
    let account = get_account_optional(address);
    if (cast(account.value, felt) == 0) {
        // TODO: think about which cases lead to this error and decide on the correct type of exception to raise
        // perhaps AssertionError
        with_attr error_message("Cannot set storage on non-existent account") {
            assert 0 = 1;
        }
    }

    let storage_tries_dict_ptr = cast(storage_tries.value.dict_ptr, DictAccess*);
    // Use `hashdict_get` instead of `hashdict_read` because `MappingAddressTrieBytes32U256` is not a
    // `default_dict`. Accessing a key that does not exist in the dict would have panicked for `hashdict_read`.
    let (storage_trie_pointer) = hashdict_get{
        poseidon_ptr=poseidon_ptr, dict_ptr=storage_tries_dict_ptr
    }(1, &address.value);

    if (storage_trie_pointer == 0) {
        // dict_new expects an initial_dict hint argument.
        %{ initial_dict = {} %}
        let (new_mapping_dict_ptr) = dict_new();
        tempvar new_storage_trie = new TrieBytes32U256Struct(
            secured=bool(1),
            default=U256(new U256Struct(0, 0)),
            _data=MappingBytes32U256(
                new MappingBytes32U256Struct(
                    dict_ptr_start=cast(new_mapping_dict_ptr, Bytes32U256DictAccess*),
                    dict_ptr=cast(new_mapping_dict_ptr, Bytes32U256DictAccess*),
                    original_mapping=cast(0, MappingBytes32U256Struct*),
                ),
            ),
        );

        let storage_trie_pointer = cast(new_storage_trie, felt);
        hashdict_write{poseidon_ptr=poseidon_ptr, dict_ptr=storage_tries_dict_ptr}(
            1, &address.value, storage_trie_pointer
        );

        tempvar storage_trie_pointer = storage_trie_pointer;
    } else {
        tempvar storage_trie_pointer = storage_trie_pointer;
    }
    let storage_tries_dict_ptr = storage_tries_dict_ptr;

    let trie_struct = cast(storage_trie_pointer, TrieBytes32U256Struct*);
    let storage_trie = TrieBytes32U256(trie_struct);
    trie_set_TrieBytes32U256{poseidon_ptr=poseidon_ptr, trie=storage_trie}(key, value);

    // From EELS <https://github.com/ethereum/execution-specs/blob/master/src/ethereum/cancun/state.py#L318>:
    // if trie._data == {}:
    //     del state._storage_tries[address]
    // TODO: Investigate whether this is needed inside provable code
    // If the storage trie is empty, then write null ptr to the mapping address -> storage trie at address

    // Update state
    // 1. Write the updated storage trie to the mapping address -> storage trie
    let storage_trie_ptr = cast(storage_trie.value, felt);
    hashdict_write{poseidon_ptr=poseidon_ptr, dict_ptr=storage_tries_dict_ptr}(
        1, &address.value, storage_trie_ptr
    );
    // 2. Create a new storage_tries instance with the updated storage trie at address
    let new_storage_tries_dict_ptr = cast(
        storage_tries_dict_ptr, AddressTrieBytes32U256DictAccess*
    );
    tempvar new_storage_tries = MappingAddressTrieBytes32U256(
        new MappingAddressTrieBytes32U256Struct(
            dict_ptr_start=storage_tries.value.dict_ptr_start,
            dict_ptr=new_storage_tries_dict_ptr,
            original_mapping=storage_tries.value.original_mapping,
        ),
    );
    // 3. Update state with the updated storage tries
    tempvar state = State(
        new StateStruct(
            _main_trie=state.value._main_trie,
            _storage_tries=new_storage_tries,
            _snapshots=state.value._snapshots,
            created_accounts=state.value.created_accounts,
        ),
    );
    return ();
}

func get_transient_storage{poseidon_ptr: PoseidonBuiltin*, transient_storage: TransientStorage}(
    address: Address, key: Bytes32
) -> U256 {
    alloc_locals;
    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let transient_storage_tries_dict_ptr = cast(
        transient_storage.value._tries.value.dict_ptr, DictAccess*
    );
    let (trie_ptr) = hashdict_get{dict_ptr=transient_storage_tries_dict_ptr}(1, &address.value);

    // If no storage trie is associated to that address, return the 0 default
    if (trie_ptr == 0) {
        let new_transient_storage_tries_dict_ptr = cast(
            transient_storage_tries_dict_ptr, AddressTrieBytes32U256DictAccess*
        );
        tempvar transient_storage_tries = MappingAddressTrieBytes32U256(
            new MappingAddressTrieBytes32U256Struct(
                transient_storage.value._tries.value.dict_ptr_start,
                new_transient_storage_tries_dict_ptr,
                transient_storage.value._tries.value.original_mapping,
            ),
        );
        tempvar transient_storage = TransientStorage(
            new TransientStorageStruct(transient_storage_tries, transient_storage.value._snapshots)
        );
        tempvar result = U256(new U256Struct(0, 0));
        return result;
    }

    let trie = TrieBytes32U256(cast(trie_ptr, TrieBytes32U256Struct*));
    with trie {
        let value = trie_get_TrieBytes32U256(key);
    }

    // Rebind the trie to the transient storage
    hashdict_write{poseidon_ptr=poseidon_ptr, dict_ptr=transient_storage_tries_dict_ptr}(
        1, &address.value, cast(trie.value, felt)
    );
    let new_storage_tries_dict_ptr = cast(
        transient_storage_tries_dict_ptr, AddressTrieBytes32U256DictAccess*
    );
    tempvar transient_storage_tries = MappingAddressTrieBytes32U256(
        new MappingAddressTrieBytes32U256Struct(
            transient_storage.value._tries.value.dict_ptr_start,
            new_storage_tries_dict_ptr,
            transient_storage.value._tries.value.original_mapping,
        ),
    );
    tempvar transient_storage = TransientStorage(
        new TransientStorageStruct(transient_storage_tries, transient_storage.value._snapshots)
    );

    return value;
}

func set_transient_storage{poseidon_ptr: PoseidonBuiltin*, transient_storage: TransientStorage}(
    address: Address, key: Bytes32, value: U256
) {
    alloc_locals;
    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let transient_storage_tries_dict_ptr = cast(
        transient_storage.value._tries.value.dict_ptr, DictAccess*
    );
    let (trie_ptr) = hashdict_get{dict_ptr=transient_storage_tries_dict_ptr}(1, &address.value);

    if (trie_ptr == 0) {
        %{ initial_dict = {} %}
        let (empty_dict) = dict_new();
        tempvar new_trie = new TrieBytes32U256Struct(
            secured=Bool(1),
            default=U256(new U256Struct(0, 0)),
            _data=MappingBytes32U256(
                new MappingBytes32U256Struct(
                    dict_ptr_start=cast(empty_dict, Bytes32U256DictAccess*),
                    dict_ptr=cast(empty_dict, Bytes32U256DictAccess*),
                    original_mapping=cast(0, MappingBytes32U256Struct*),
                ),
            ),
        );
        let new_trie_ptr = cast(new_trie, felt);
        hashdict_write{poseidon_ptr=poseidon_ptr, dict_ptr=transient_storage_tries_dict_ptr}(
            1, &address.value, new_trie_ptr
        );
        tempvar trie_ptr = new_trie_ptr;
    } else {
        tempvar trie_ptr = trie_ptr;
    }

    let transient_storage_tries_dict_ptr = transient_storage_tries_dict_ptr;
    tempvar trie = TrieBytes32U256(cast(trie_ptr, TrieBytes32U256Struct*));
    with trie {
        trie_set_TrieBytes32U256{poseidon_ptr=poseidon_ptr}(key, value);
    }

    // Trie is not deleted if empty
    // From EELS https://github.com/ethereum/execution-specs/blob/5c82ed6ac3eb992c7d87320a3e771b5e852a06df/src/ethereum/cancun/state.py#L697:
    // if trie._data == {}:
    //    del transient_storage._tries[address]

    // Update the transient storage tries
    hashdict_write{poseidon_ptr=poseidon_ptr, dict_ptr=transient_storage_tries_dict_ptr}(
        1, &address.value, cast(trie.value, felt)
    );
    let new_storage_tries_dict_ptr = cast(
        transient_storage_tries_dict_ptr, AddressTrieBytes32U256DictAccess*
    );
    tempvar transient_storage_tries = MappingAddressTrieBytes32U256(
        new MappingAddressTrieBytes32U256Struct(
            transient_storage.value._tries.value.dict_ptr_start,
            new_storage_tries_dict_ptr,
            transient_storage.value._tries.value.original_mapping,
        ),
    );
    tempvar transient_storage = TransientStorage(
        new TransientStorageStruct(transient_storage_tries, transient_storage.value._snapshots)
    );

    return ();
}

func account_has_code_or_nonce{poseidon_ptr: PoseidonBuiltin*, state: State}(
    address: Address
) -> bool {
    let account = get_account(address);

    if (account.value.nonce.value != 0) {
        tempvar res = bool(1);
        return res;
    }

    if (account.value.code.value.len != 0) {
        tempvar res = bool(1);
        return res;
    }

    tempvar res = bool(0);
    return res;
}

func account_exists{poseidon_ptr: PoseidonBuiltin*, state: State}(address: Address) -> bool {
    let account = get_account_optional(address);

    if (cast(account.value, felt) == 0) {
        tempvar result = bool(0);
        return result;
    }
    tempvar result = bool(1);
    return result;
}

func is_account_empty{poseidon_ptr: PoseidonBuiltin*, state: State}(address: Address) -> bool {
    // Get the account at the address
    let account = get_account(address);

    // Check if nonce is 0, code is empty, and balance is 0
    if (account.value.nonce.value != 0) {
        tempvar res = bool(0);
        return res;
    }

    if (account.value.code.value.len != 0) {
        tempvar res = bool(0);
        return res;
    }

    if (account.value.balance.value.low != 0) {
        tempvar res = bool(0);
        return res;
    }

    if (account.value.balance.value.high != 0) {
        tempvar res = bool(0);
        return res;
    }

    tempvar res = bool(1);
    return res;
}
