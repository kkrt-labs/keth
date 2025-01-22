from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.uint256 import Uint256
from src.utils.uint256 import uint256_add, uint256_sub
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.squash_dict import squash_dict
from starkware.cairo.common.memcpy import memcpy

from ethereum.cancun.fork_types import (
    Address,
    Account,
    OptionalAccount,
    MappingAddressAccount,
    MappingAddressAccountStruct,
    AddressAccountDictAccess,
    SetAddress,
    SetAddressStruct,
    SetAddressDictAccess,
    EMPTY_ACCOUNT,
    MappingTupleAddressBytes32U256,
    MappingTupleAddressBytes32U256Struct,
    Account__eq__,
    TupleAddressBytes32U256DictAccess,
    HashedTupleAddressBytes32,
    TupleAddressBytes32,
    ListTupleAddressBytes32,
    ListTupleAddressBytes32Struct,
)
from ethereum.cancun.trie import (
    TrieTupleAddressBytes32U256,
    TrieAddressOptionalAccount,
    trie_get_TrieAddressOptionalAccount,
    trie_set_TrieAddressOptionalAccount,
    trie_get_TrieTupleAddressBytes32U256,
    trie_set_TrieTupleAddressBytes32U256,
    AccountStruct,
    TrieTupleAddressBytes32U256Struct,
    TrieAddressOptionalAccountStruct,
    copy_TrieAddressOptionalAccount,
    copy_TrieTupleAddressBytes32U256,
)
from ethereum_types.bytes import Bytes, Bytes32
from ethereum_types.numeric import U256, U256Struct, Bool, bool, Uint
from ethereum.utils.numeric import is_zero, U256_le, U256_sub, U256_add

from src.utils.dict import (
    hashdict_read,
    hashdict_write,
    hashdict_get,
    dict_new_empty,
    get_keys_for_address_prefix,
    dict_update,
)

struct TupleTrieAddressOptionalAccountTrieTupleAddressBytes32U256Struct {
    trie_address_account: TrieAddressOptionalAccount,
    trie_tuple_address_bytes32_u256: TrieTupleAddressBytes32U256,
}

struct TupleTrieAddressOptionalAccountTrieTupleAddressBytes32U256 {
    value: TupleTrieAddressOptionalAccountTrieTupleAddressBytes32U256Struct*,
}

struct ListTupleTrieAddressOptionalAccountTrieTupleAddressBytes32U256Struct {
    data: TupleTrieAddressOptionalAccountTrieTupleAddressBytes32U256*,
    len: felt,
}

struct ListTupleTrieAddressOptionalAccountTrieTupleAddressBytes32U256 {
    value: ListTupleTrieAddressOptionalAccountTrieTupleAddressBytes32U256Struct*,
}

struct ListTrieTupleAddressBytes32U256Struct {
    data: TrieTupleAddressBytes32U256*,
    len: felt,
}

struct ListTrieTupleAddressBytes32U256 {
    value: ListTrieTupleAddressBytes32U256Struct*,
}

struct TransientStorageStruct {
    _tries: TrieTupleAddressBytes32U256,
    _snapshots: ListTrieTupleAddressBytes32U256,
}

struct TransientStorage {
    value: TransientStorageStruct*,
}

struct StateStruct {
    _main_trie: TrieAddressOptionalAccount,
    _storage_tries: TrieTupleAddressBytes32U256,
    _snapshots: ListTupleTrieAddressOptionalAccountTrieTupleAddressBytes32U256,
    created_accounts: SetAddress,
    original_storage_tries: TrieTupleAddressBytes32U256,
}

struct State {
    value: StateStruct*,
}

namespace StateImpl {
    func set_created_accounts{state: State}(new_created_accounts: SetAddress) {
        tempvar state = State(
            new StateStruct(
                _main_trie=state.value._main_trie,
                _storage_tries=state.value._storage_tries,
                _snapshots=state.value._snapshots,
                created_accounts=new_created_accounts,
                original_storage_tries=state.value.original_storage_tries,
            ),
        );
        return ();
    }

    func set_original_storage_tries{state: State}(
        new_original_storage_tries: TrieTupleAddressBytes32U256
    ) {
        tempvar state = State(
            new StateStruct(
                _main_trie=state.value._main_trie,
                _storage_tries=state.value._storage_tries,
                _snapshots=state.value._snapshots,
                created_accounts=state.value.created_accounts,
                original_storage_tries=new_original_storage_tries,
            ),
        );
        return ();
    }
}

func get_account_optional{poseidon_ptr: PoseidonBuiltin*, state: State}(
    address: Address
) -> OptionalAccount {
    let trie = state.value._main_trie;
    with trie {
        let account = trie_get_TrieAddressOptionalAccount(address);
    }

    tempvar state = State(
        new StateStruct(
            _main_trie=trie,
            _storage_tries=state.value._storage_tries,
            _snapshots=state.value._snapshots,
            created_accounts=state.value.created_accounts,
            original_storage_tries=state.value.original_storage_tries,
        ),
    );

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
            original_storage_tries=state.value.original_storage_tries,
        ),
    );
    return ();
}

func move_ether{range_check_ptr, poseidon_ptr: PoseidonBuiltin*, state: State}(
    sender_address: Address, recipient_address: Address, amount: U256
) {
    alloc_locals;
    let sender_account = get_account(sender_address);
    let sender_balance = sender_account.value.balance;

    let is_sender_balance_sufficient = U256_le(amount, sender_balance);
    with_attr error_message("Sender has insufficient balance") {
        assert is_sender_balance_sufficient.value = 1;
    }

    let new_sender_account_balance = U256_sub(sender_balance, amount);
    set_account_balance(sender_address, new_sender_account_balance);

    let recipient_account = get_account(recipient_address);
    let new_recipient_account_balance = U256_add(recipient_account.value.balance, amount);
    set_account_balance(recipient_address, new_recipient_account_balance);
    return ();
}

func get_storage{poseidon_ptr: PoseidonBuiltin*, state: State}(
    address: Address, key: Bytes32
) -> U256 {
    alloc_locals;
    let storage_tries_data = state.value._storage_tries.value._data;

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let storage_data_dict_ptr = cast(storage_tries_data.value.dict_ptr, DictAccess*);

    let (keys) = alloc();
    assert keys[0] = address.value;
    assert keys[1] = key.value.low;
    assert keys[2] = key.value.high;
    let (value_ptr) = hashdict_read{poseidon_ptr=poseidon_ptr, dict_ptr=storage_data_dict_ptr}(
        3, keys
    );

    let new_storage_data_dict_ptr = cast(storage_data_dict_ptr, TupleAddressBytes32U256DictAccess*);
    tempvar new_storage_data = MappingTupleAddressBytes32U256(
        new MappingTupleAddressBytes32U256Struct(
            dict_ptr_start=storage_tries_data.value.dict_ptr_start,
            dict_ptr=new_storage_data_dict_ptr,
            original_mapping=storage_tries_data.value.original_mapping,
        ),
    );
    tempvar new_storage_tries = TrieTupleAddressBytes32U256(
        new TrieTupleAddressBytes32U256Struct(
            secured=state.value._storage_tries.value.secured,
            default=state.value._storage_tries.value.default,
            _data=new_storage_data,
        ),
    );
    tempvar state = State(
        new StateStruct(
            _main_trie=state.value._main_trie,
            _storage_tries=new_storage_tries,
            _snapshots=state.value._snapshots,
            created_accounts=state.value.created_accounts,
            original_storage_tries=state.value.original_storage_tries,
        ),
    );

    tempvar res = U256(cast(value_ptr, U256Struct*));
    return res;
}

func destroy_account{poseidon_ptr: PoseidonBuiltin*, state: State}(address: Address) {
    destroy_storage(address);
    let none_account = OptionalAccount(cast(0, AccountStruct*));
    set_account(address, none_account);
    return ();
}

func increment_nonce{poseidon_ptr: PoseidonBuiltin*, state: State}(address: Address) {
    alloc_locals;
    let account = get_account(address);
    // This increment is safe since
    // `validate_transaction` will not allow a transaction
    // with a nonce equal to max nonce (u64 as of today)
    let new_nonce = account.value.nonce.value + 1;
    tempvar new_account = OptionalAccount(
        new AccountStruct(Uint(new_nonce), account.value.balance, account.value.code)
    );
    set_account(address, new_account);
    return ();
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
    let storage_trie = state.value._storage_tries;
    trie_set_TrieTupleAddressBytes32U256{poseidon_ptr=poseidon_ptr, trie=storage_trie}(
        address, key, value
    );

    // From EELS <https://github.com/ethereum/execution-specs/blob/master/src/ethereum/cancun/state.py#L318>:
    // if trie._data == {}:
    //     del state._storage_tries[address]
    // TODO: Investigate whether this is needed inside provable code
    // If the storage trie is empty, then write null ptr to the mapping address -> storage trie at address

    // 3. Update state with the updated storage tries
    tempvar state = State(
        new StateStruct(
            _main_trie=state.value._main_trie,
            _storage_tries=storage_trie,
            _snapshots=state.value._snapshots,
            created_accounts=state.value.created_accounts,
            original_storage_tries=state.value.original_storage_tries,
        ),
    );
    return ();
}

func get_storage_original{range_check_ptr, poseidon_ptr: PoseidonBuiltin*, state: State}(
    address: Address, key: Bytes32
) -> U256 {
    alloc_locals;

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let created_accounts_ptr = cast(state.value.created_accounts.value.dict_ptr, DictAccess*);
    let (is_created) = hashdict_read{dict_ptr=created_accounts_ptr}(1, &address.value);
    let new_created_accounts_ptr = cast(created_accounts_ptr, SetAddressDictAccess*);
    tempvar new_created_accounts = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=state.value.created_accounts.value.dict_ptr_start,
            dict_ptr=new_created_accounts_ptr,
        ),
    );
    StateImpl.set_created_accounts(new_created_accounts);

    // In the transaction where an account is created, its preexisting storage
    // is ignored.
    if (is_created != 0) {
        tempvar res = U256(new U256Struct(0, 0));
        return res;
    }

    let new_original_storage_tries = state.value.original_storage_tries;
    let value = trie_get_TrieTupleAddressBytes32U256{trie=new_original_storage_tries}(address, key);

    // Update state
    tempvar state = State(
        new StateStruct(
            _main_trie=state.value._main_trie,
            _storage_tries=state.value._storage_tries,
            _snapshots=state.value._snapshots,
            created_accounts=state.value.created_accounts,
            original_storage_tries=new_original_storage_tries,
        ),
    );

    return value;
}

func destroy_storage{poseidon_ptr: PoseidonBuiltin*, state: State}(address: Address) {
    alloc_locals;

    let storage_tries = state.value._storage_tries;
    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let prefix_len = 1;
    let prefix = &address.value;
    tempvar dict_ptr = cast(storage_tries.value._data.value.dict_ptr, DictAccess*);
    let keys = get_keys_for_address_prefix{dict_ptr=dict_ptr}(prefix_len, prefix);

    _destroy_storage_keys{poseidon_ptr=poseidon_ptr, storage_tries_ptr=dict_ptr}(keys, 0);
    let new_dict_ptr = cast(dict_ptr, TupleAddressBytes32U256DictAccess*);

    tempvar new_storage_tries_data = MappingTupleAddressBytes32U256(
        new MappingTupleAddressBytes32U256Struct(
            dict_ptr_start=storage_tries.value._data.value.dict_ptr_start,
            dict_ptr=new_dict_ptr,
            original_mapping=storage_tries.value._data.value.original_mapping,
        ),
    );

    tempvar new_storage_tries = TrieTupleAddressBytes32U256(
        new TrieTupleAddressBytes32U256Struct(
            storage_tries.value.secured, storage_tries.value.default, new_storage_tries_data
        ),
    );
    tempvar state = State(
        new StateStruct(
            _main_trie=state.value._main_trie,
            _storage_tries=new_storage_tries,
            _snapshots=state.value._snapshots,
            created_accounts=state.value.created_accounts,
            original_storage_tries=state.value.original_storage_tries,
        ),
    );

    return ();
}

func _destroy_storage_keys{poseidon_ptr: PoseidonBuiltin*, storage_tries_ptr: DictAccess*}(
    keys: ListTupleAddressBytes32, index: felt
) {
    if (index == keys.value.len) {
        return ();
    }

    let current_key = keys.value.data[index];
    let key_len = 3;
    let (key) = alloc();
    assert key[0] = current_key.value.address.value;
    assert key[1] = current_key.value.bytes32.value.low;
    assert key[2] = current_key.value.bytes32.value.high;
    hashdict_write{dict_ptr=storage_tries_ptr}(key_len, key, 0);

    return _destroy_storage_keys{poseidon_ptr=poseidon_ptr, storage_tries_ptr=storage_tries_ptr}(
        keys, index + 1
    );
}

func get_transient_storage{poseidon_ptr: PoseidonBuiltin*, transient_storage: TransientStorage}(
    address: Address, key: Bytes32
) -> U256 {
    alloc_locals;
    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let new_transient_storage_tries = transient_storage.value._tries;
    let value = trie_get_TrieTupleAddressBytes32U256{trie=new_transient_storage_tries}(
        address, key
    );

    tempvar transient_storage = TransientStorage(
        new TransientStorageStruct(new_transient_storage_tries, transient_storage.value._snapshots)
    );

    return value;
}

func set_transient_storage{poseidon_ptr: PoseidonBuiltin*, transient_storage: TransientStorage}(
    address: Address, key: Bytes32, value: U256
) {
    alloc_locals;
    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let new_transient_storage_tries = transient_storage.value._tries;
    trie_set_TrieTupleAddressBytes32U256{
        poseidon_ptr=poseidon_ptr, trie=new_transient_storage_tries
    }(address, key, value);

    // Trie is not deleted if empty
    // From EELS https://github.com/ethereum/execution-specs/blob/5c82ed6ac3eb992c7d87320a3e771b5e852a06df/src/ethereum/cancun/state.py#L697:
    // if trie._data == {}:
    //    del transient_storage._tries[address]
    tempvar transient_storage = TransientStorage(
        new TransientStorageStruct(new_transient_storage_tries, transient_storage.value._snapshots)
    );

    return ();
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

func mark_account_created{poseidon_ptr: PoseidonBuiltin*, state: State}(address: Address) {
    alloc_locals;

    let created_accounts = state.value.created_accounts;

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let set_dict_ptr = cast(created_accounts.value.dict_ptr, DictAccess*);
    hashdict_write{poseidon_ptr=poseidon_ptr, dict_ptr=set_dict_ptr}(1, &address.value, 1);

    // Rebind state
    tempvar new_created_account = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=created_accounts.value.dict_ptr_start,
            dict_ptr=cast(set_dict_ptr, SetAddressDictAccess*),
        ),
    );
    tempvar state = State(
        new StateStruct(
            _main_trie=state.value._main_trie,
            _storage_tries=state.value._storage_tries,
            _snapshots=state.value._snapshots,
            created_accounts=new_created_account,
            original_storage_tries=state.value.original_storage_tries,
        ),
    );

    return ();
}

func account_exists_and_is_empty{poseidon_ptr: PoseidonBuiltin*, state: State}(
    address: Address
) -> bool {
    alloc_locals;
    // Get the account at the address
    let account = get_account_optional(address);

    let _empty_account = EMPTY_ACCOUNT();
    let empty_account = OptionalAccount(_empty_account.value);
    let is_empty_account = Account__eq__(account, empty_account);

    return is_empty_account;
}

func is_account_alive{poseidon_ptr: PoseidonBuiltin*, state: State}(address: Address) -> bool {
    alloc_locals;
    let account = get_account_optional(address);
    if (cast(account.value, felt) == 0) {
        tempvar res = bool(0);
        return res;
    }

    let _empty_account = EMPTY_ACCOUNT();
    let empty_account = OptionalAccount(_empty_account.value);
    let is_empty_account = Account__eq__(account, empty_account);

    if (is_empty_account.value == 0) {
        tempvar res = bool(1);
        return res;
    }

    tempvar res = bool(0);
    return res;
}

func begin_transaction{
    range_check_ptr,
    poseidon_ptr: PoseidonBuiltin*,
    state: State,
    transient_storage: TransientStorage,
}() {
    alloc_locals;

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    // Copy the main trie
    let trie = state.value._main_trie;
    let copied_main_trie = copy_TrieAddressOptionalAccount{trie=trie}();

    // Copy the storage tries
    let storage_tries = state.value._storage_tries;
    let copied_storage_tries = copy_TrieTupleAddressBytes32U256{trie=storage_tries}();

    // Store in snapshots the copied main trie and the new storage tries mapping
    tempvar new_snapshot = TupleTrieAddressOptionalAccountTrieTupleAddressBytes32U256(
        new TupleTrieAddressOptionalAccountTrieTupleAddressBytes32U256Struct(
            trie_address_account=copied_main_trie,
            trie_tuple_address_bytes32_u256=copied_storage_tries,
        ),
    );

    // Update the snapshots list
    assert state.value._snapshots.value.data[state.value._snapshots.value.len] = new_snapshot;

    tempvar new_snapshots = ListTupleTrieAddressOptionalAccountTrieTupleAddressBytes32U256(
        new ListTupleTrieAddressOptionalAccountTrieTupleAddressBytes32U256Struct(
            data=state.value._snapshots.value.data, len=state.value._snapshots.value.len + 1
        ),
    );

    // Update state with new snapshots
    tempvar state = State(
        new StateStruct(
            _main_trie=state.value._main_trie,
            _storage_tries=state.value._storage_tries,
            _snapshots=new_snapshots,
            created_accounts=state.value.created_accounts,
            original_storage_tries=state.value.original_storage_tries,
        ),
    );

    // Copy transient storage tries
    let transient_storage_tries = transient_storage.value._tries;
    let copied_transient_storage_tries = copy_TrieTupleAddressBytes32U256{
        trie=transient_storage_tries
    }();

    // Update the snapshots list
    assert transient_storage.value._snapshots.value.data[
        transient_storage.value._snapshots.value.len
    ] = copied_transient_storage_tries;

    tempvar new_transient_snapshots = ListTrieTupleAddressBytes32U256(
        new ListTrieTupleAddressBytes32U256Struct(
            data=transient_storage.value._snapshots.value.data,
            len=transient_storage.value._snapshots.value.len + 1,
        ),
    );

    // Update transient storage with new snapshots
    tempvar transient_storage = TransientStorage(
        new TransientStorageStruct(
            _tries=transient_storage.value._tries, _snapshots=new_transient_snapshots
        ),
    );

    return ();
}

func rollback_transaction{
    range_check_ptr,
    poseidon_ptr: PoseidonBuiltin*,
    state: State,
    transient_storage: TransientStorage,
}() {
    alloc_locals;

    // State //

    // Main Trie
    let main_trie = state.value._main_trie;
    let main_trie_start = main_trie.value._data.value.dict_ptr_start;
    let main_trie_end = main_trie.value._data.value.dict_ptr;
    let parent_main_trie = main_trie.value._data.value.original_mapping;

    with_attr error_message("IndexError") {
        tempvar parent_main_trie_ptr = cast(parent_main_trie, felt);
        if (cast(parent_main_trie_ptr, felt) == 0) {
            assert 0 = 1;
        }
    }
    let parent_trie_start = parent_main_trie.dict_ptr_start;
    let parent_trie_end = parent_main_trie.dict_ptr;

    let (new_parent_trie_start, new_parent_trie_end) = dict_update(
        cast(main_trie_start, DictAccess*),
        cast(main_trie_end, DictAccess*),
        cast(parent_trie_start, DictAccess*),
        cast(parent_trie_end, DictAccess*),
        0,
    );

    tempvar new_main_trie = TrieAddressOptionalAccount(
        new TrieAddressOptionalAccountStruct(
            secured=main_trie.value.secured,
            default=main_trie.value.default,
            _data=MappingAddressAccount(
                new MappingAddressAccountStruct(
                    dict_ptr_start=cast(new_parent_trie_start, AddressAccountDictAccess*),
                    dict_ptr=cast(new_parent_trie_end, AddressAccountDictAccess*),
                    original_mapping=parent_main_trie,
                ),
            ),
        ),
    );

    // Storage Tries
    let storage_tries = state.value._storage_tries;
    let storage_tries_start = storage_tries.value._data.value.dict_ptr_start;
    let storage_tries_end = storage_tries.value._data.value.dict_ptr;
    let parent_storage_tries = storage_tries.value._data.value.original_mapping;
    let parent_storage_tries_start = parent_storage_tries.dict_ptr_start;
    let parent_storage_tries_end = parent_storage_tries.dict_ptr;
    let (parent_storage_tries_dict_start, parent_storage_tries_dict) = dict_update(
        cast(storage_tries_start, DictAccess*),
        cast(storage_tries_end, DictAccess*),
        cast(parent_storage_tries_start, DictAccess*),
        cast(parent_storage_tries_end, DictAccess*),
        0,
    );

    tempvar new_storage_tries = TrieTupleAddressBytes32U256(
        new TrieTupleAddressBytes32U256Struct(
            secured=storage_tries.value.secured,
            default=storage_tries.value.default,
            _data=MappingTupleAddressBytes32U256(
                new MappingTupleAddressBytes32U256Struct(
                    dict_ptr_start=cast(
                        parent_storage_tries_dict_start, TupleAddressBytes32U256DictAccess*
                    ),
                    dict_ptr=cast(parent_storage_tries_dict, TupleAddressBytes32U256DictAccess*),
                    original_mapping=parent_storage_tries,
                ),
            ),
        ),
    );

    // Snapshots
    // TODO: This is only used for serde purposes. To remove, and handle the re-creation of the "snapshot" struct directly in serde?
    let snapshots = state.value._snapshots;
    let new_len = snapshots.value.len - 1;
    let (new_snapshots_inner: TupleTrieAddressOptionalAccountTrieTupleAddressBytes32U256*) = alloc(
        );
    memcpy(new_snapshots_inner, snapshots.value.data, new_len);

    tempvar new_snapshots = ListTupleTrieAddressOptionalAccountTrieTupleAddressBytes32U256(
        new ListTupleTrieAddressOptionalAccountTrieTupleAddressBytes32U256Struct(
            data=new_snapshots_inner, len=new_len
        ),
    );

    if (new_len == 0) {
        // Clear created accounts
        let (new_created_accounts_ptr) = dict_new_empty();
        tempvar new_created_accounts = SetAddress(
            new SetAddressStruct(
                dict_ptr_start=cast(new_created_accounts_ptr, SetAddressDictAccess*),
                dict_ptr=cast(new_created_accounts_ptr, SetAddressDictAccess*),
            ),
        );
    } else {
        tempvar new_created_accounts = state.value.created_accounts;
    }

    tempvar state = State(
        new StateStruct(
            _main_trie=new_main_trie,
            _storage_tries=new_storage_tries,
            _snapshots=new_snapshots,
            created_accounts=new_created_accounts,
            original_storage_tries=state.value.original_storage_tries,
        ),
    );

    // Transient Storage //

    let transient_storage_tries = transient_storage.value._tries;
    let transient_storage_tries_start = transient_storage_tries.value._data.value.dict_ptr_start;
    let transient_storage_tries_end = transient_storage_tries.value._data.value.dict_ptr;
    let parent_transient_storage_tries = transient_storage_tries.value._data.value.original_mapping;
    with_attr error_message("IndexError") {
        tempvar parent_transient_storage_tries_ptr = cast(parent_transient_storage_tries, felt);
        if (cast(parent_transient_storage_tries_ptr, felt) == 0) {
            assert 0 = 1;
        }
    }
    let parent_transient_storage_tries_start = parent_transient_storage_tries.dict_ptr_start;
    let parent_transient_storage_tries_end = parent_transient_storage_tries.dict_ptr;
    let (
        new_parent_transient_storage_tries_start, new_parent_transient_storage_tries_end
    ) = dict_update(
        cast(transient_storage_tries_start, DictAccess*),
        cast(transient_storage_tries_end, DictAccess*),
        cast(parent_transient_storage_tries_start, DictAccess*),
        cast(parent_transient_storage_tries_end, DictAccess*),
        0,
    );

    tempvar new_transient_storage_tries = TrieTupleAddressBytes32U256(
        new TrieTupleAddressBytes32U256Struct(
            secured=transient_storage_tries.value.secured,
            default=transient_storage_tries.value.default,
            _data=MappingTupleAddressBytes32U256(
                new MappingTupleAddressBytes32U256Struct(
                    dict_ptr_start=cast(
                        new_parent_transient_storage_tries_start, TupleAddressBytes32U256DictAccess*
                    ),
                    dict_ptr=cast(
                        new_parent_transient_storage_tries_end, TupleAddressBytes32U256DictAccess*
                    ),
                    original_mapping=parent_transient_storage_tries,
                ),
            ),
        ),
    );

    // Snapshots
    let ts_snapshots = transient_storage.value._snapshots;
    let new_len = ts_snapshots.value.len - 1;
    let (new_ts_snapshots_inner: TrieTupleAddressBytes32U256*) = alloc();
    memcpy(new_ts_snapshots_inner, ts_snapshots.value.data, new_len);

    tempvar new_transient_snapshots = ListTrieTupleAddressBytes32U256(
        new ListTrieTupleAddressBytes32U256Struct(data=new_ts_snapshots_inner, len=new_len)
    );

    tempvar transient_storage = TransientStorage(
        new TransientStorageStruct(
            _tries=new_transient_storage_tries, _snapshots=new_transient_snapshots
        ),
    );

    return ();
}

func copy_storage_tries_recursive{
    range_check_ptr,
    poseidon_ptr: PoseidonBuiltin*,
    new_storage_tries: MappingTupleAddressBytes32U256,
}(dict_start: TupleAddressBytes32U256DictAccess*, dict_end: TupleAddressBytes32U256DictAccess*) {
    alloc_locals;
    // Base case: if start == end, return
    if (dict_start == dict_end) {
        return ();
    }

    // Get the current entry
    let key = [dict_start].key;
    let trie_ptr = [dict_start].new_value;

    // Copy the trie
    tempvar trie_to_copy = TrieAddressOptionalAccount(
        cast(trie_ptr.value, TrieAddressOptionalAccountStruct*)
    );
    let copied_trie = copy_TrieAddressOptionalAccount{trie=trie_to_copy}();

    // Write to new storage tries mapping
    let new_storage_trie_ptr = cast(new_storage_tries.value.dict_ptr, DictAccess*);
    hashdict_write{poseidon_ptr=poseidon_ptr, dict_ptr=new_storage_trie_ptr}(
        1, &key.value, cast(copied_trie.value, felt)
    );

    // Update new_storage_tries with new dict_ptr
    tempvar new_storage_tries = MappingTupleAddressBytes32U256(
        new MappingTupleAddressBytes32U256Struct(
            dict_ptr_start=new_storage_tries.value.dict_ptr_start,
            dict_ptr=cast(new_storage_trie_ptr, TupleAddressBytes32U256DictAccess*),
            original_mapping=new_storage_tries.value.original_mapping,
        ),
    );

    // Recursive call with next entry
    return copy_storage_tries_recursive(
        dict_start + TupleAddressBytes32U256DictAccess.SIZE, dict_end
    );
}

func copy_transient_storage_tries_recursive{
    range_check_ptr,
    poseidon_ptr: PoseidonBuiltin*,
    new_transient_tries: MappingTupleAddressBytes32U256,
}(dict_start: TupleAddressBytes32U256DictAccess*, dict_end: TupleAddressBytes32U256DictAccess*) {
    alloc_locals;

    // Base case: if start == end, return
    if (dict_start == dict_end) {
        return ();
    }

    // Get the current entry
    let key = [dict_start].key;
    let trie_ptr = [dict_start].new_value;

    // Copy the trie
    let trie_to_copy = TrieTupleAddressBytes32U256(
        cast(trie_ptr.value, TrieTupleAddressBytes32U256Struct*)
    );
    let copied_trie = copy_TrieTupleAddressBytes32U256{trie=trie_to_copy}();

    // Write to new transient storage tries mapping
    let new_transient_trie_ptr = cast(new_transient_tries.value.dict_ptr, DictAccess*);
    hashdict_write{poseidon_ptr=poseidon_ptr, dict_ptr=new_transient_trie_ptr}(
        1, &key.value, cast(copied_trie.value, felt)
    );

    // Update new_transient_tries with new dict_ptr
    tempvar new_transient_tries = MappingTupleAddressBytes32U256(
        new MappingTupleAddressBytes32U256Struct(
            dict_ptr_start=new_transient_tries.value.dict_ptr_start,
            dict_ptr=cast(new_transient_trie_ptr, TupleAddressBytes32U256DictAccess*),
            original_mapping=new_transient_tries.value.original_mapping,
        ),
    );

    // Recursive call with next entry
    return copy_transient_storage_tries_recursive(
        dict_start + TupleAddressBytes32U256DictAccess.SIZE, dict_end
    );
}

func set_code{poseidon_ptr: PoseidonBuiltin*, state: State}(address: Address, code: Bytes) {
    // Get the current account
    let account = get_account(address);

    // Create new account with updated code
    tempvar new_account = OptionalAccount(
        new AccountStruct(nonce=account.value.nonce, balance=account.value.balance, code=code)
    );

    // Set the updated account
    set_account(address, new_account);
    return ();
}

func set_account_balance{poseidon_ptr: PoseidonBuiltin*, state: State}(
    address: Address, amount: U256
) {
    let account = get_account(address);

    tempvar new_account = OptionalAccount(
        new AccountStruct(nonce=account.value.nonce, balance=amount, code=account.value.code)
    );

    set_account(address, new_account);
    return ();
}

func touch_account{poseidon_ptr: PoseidonBuiltin*, state: State}(address: Address) {
    let _account_exists = account_exists(address);
    if (_account_exists.value != 0) {
        return ();
    }

    let _empty_account = EMPTY_ACCOUNT();
    let empty_account = OptionalAccount(_empty_account.value);
    set_account(address, empty_account);
    return ();
}

func destroy_touched_empty_accounts{poseidon_ptr: PoseidonBuiltin*, state: State}(
    touched_accounts: SetAddress
) -> () {
    alloc_locals;

    // if current == end, return
    let current = touched_accounts.value.dict_ptr_start;
    let end = touched_accounts.value.dict_ptr;
    if (current == end) {
        return ();
    }

    let address = [current].key;

    // Check if current account exists and is empty, destroy if so
    let is_empty = account_exists_and_is_empty(address);
    if (is_empty.value != 0) {
        destroy_account(address);
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar state = state;
    } else {
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar state = state;
    }

    // Recurse with updated touched_accounts
    return destroy_touched_empty_accounts(
        SetAddress(
            new SetAddressStruct(
                dict_ptr_start=cast(current + DictAccess.SIZE, SetAddressDictAccess*),
                dict_ptr=cast(end, SetAddressDictAccess*),
            ),
        ),
    );
}
