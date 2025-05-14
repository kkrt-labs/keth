from starkware.cairo.common.cairo_builtins import PoseidonBuiltin, BitwiseBuiltin
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.default_dict import default_dict_new
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.alloc import alloc
from ethereum.cancun.fork_types import (
    Address,
    Account,
    OptionalAccount,
    MappingAddressAccount,
    MappingAddressAccountStruct,
    AddressAccountDictAccess,
    MappingAddressBytes32,
    OptionalMappingAddressBytes32,
    MappingAddressBytes32Struct,
    AddressBytes32DictAccess,
    SetAddress,
    SetAddressStruct,
    SetAddressDictAccess,
    EMPTY_ACCOUNT,
    MappingTupleAddressBytes32U256,
    MappingTupleAddressBytes32U256Struct,
    account_eq_without_storage_root,
    TupleAddressBytes32U256DictAccess,
    TupleAddressBytes32,
    ListTupleAddressBytes32,
    ListTupleAddressBytes32Struct,
)
from ethereum.crypto.hash import keccak256, EMPTY_HASH_KECCAK
from ethereum.cancun.trie import (
    get_tuple_address_bytes32_preimage_for_key,
    root,
    EthereumTries,
    EthereumTriesEnum,
    TrieTupleAddressBytes32U256,
    TrieTupleAddressBytes32U256Struct,
    TrieAddressOptionalAccount,
    TrieAddressOptionalAccountStruct,
    TrieBytesOptionalUnionBytesLegacyTransaction,
    TrieBytesOptionalUnionBytesLegacyTransactionStruct,
    TrieBytesOptionalUnionBytesReceipt,
    TrieBytesOptionalUnionBytesReceiptStruct,
    TrieBytesOptionalUnionBytesWithdrawal,
    TrieBytesOptionalUnionBytesWithdrawalStruct,
    TrieBytes32U256,
    TrieBytes32U256Struct,
    Bytes32U256DictAccess,
    MappingBytes32U256,
    MappingBytes32U256Struct,
    trie_set_TrieBytes32U256,
    trie_get_TrieAddressOptionalAccount,
    trie_set_TrieAddressOptionalAccount,
    trie_get_TrieTupleAddressBytes32U256,
    trie_set_TrieTupleAddressBytes32U256,
    AccountStruct,
    copy_TrieAddressOptionalAccount,
    copy_TrieTupleAddressBytes32U256,
)
from ethereum.cancun.blocks import Withdrawal
from ethereum_types.bytes import Bytes, Bytes32, Bytes32Struct, BytesStruct, OptionalBytes
from ethereum.crypto.hash import EMPTY_ROOT_KECCAK, EMPTY_ROOT_BLAKE2S
from ethereum_types.numeric import U256, U256Struct, Uint, bool
from ethereum.utils.numeric import U256_le, U256_sub, U256_add, U256_mul
from ethereum.cancun.utils.constants import U256_ZERO
from cairo_core.comparison import is_zero
from cairo_core.control_flow import raise

from legacy.utils.dict import (
    dict_read,
    dict_write,
    hashdict_write,
    dict_update,
    dict_copy,
    default_dict_finalize,
    dict_squash,
)
from ethereum.utils.hash_dicts import set_address_contains

struct AddressTrieBytes32U256DictAccess {
    key: Address,
    prev_value: TrieBytes32U256,
    new_value: TrieBytes32U256,
}

struct MappingAddressTrieBytes32U256Struct {
    dict_ptr_start: AddressTrieBytes32U256DictAccess*,
    dict_ptr: AddressTrieBytes32U256DictAccess*,
    // Unused
    parent_dict: MappingAddressTrieBytes32U256Struct*,
}

struct MappingAddressTrieBytes32U256 {
    value: MappingAddressTrieBytes32U256Struct*,
}

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
}

struct TransientStorage {
    value: TransientStorageStruct*,
}

struct StateStruct {
    _main_trie: TrieAddressOptionalAccount,
    _storage_tries: TrieTupleAddressBytes32U256,
    created_accounts: SetAddress,
    original_storage_tries: TrieTupleAddressBytes32U256,
}

struct State {
    value: StateStruct*,
}

struct StateDiff {
    value: StateDiffStruct*,
}

struct StateDiffStruct {
    _main_trie_start: AddressAccountDictAccess*,
    _main_trie_end: AddressAccountDictAccess*,
    _storage_tries_start: TupleAddressBytes32U256DictAccess*,
    _storage_tries_end: TupleAddressBytes32U256DictAccess*,
}

namespace StateImpl {
    func set_created_accounts{state: State}(new_created_accounts: SetAddress) {
        tempvar state = State(
            new StateStruct(
                _main_trie=state.value._main_trie,
                _storage_tries=state.value._storage_tries,
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
                created_accounts=state.value.created_accounts,
                original_storage_tries=new_original_storage_tries,
            ),
        );
        return ();
    }
}

func get_account_optional{range_check_ptr, state: State}(
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
            created_accounts=state.value.created_accounts,
            original_storage_tries=state.value.original_storage_tries,
        ),
    );

    return account;
}

// @notice Returns the code for the given account.
// If the code is not cached, it is loaded from the program input. The program
// input must contain a Dict[Tuple[Low, High], Bytes] where the key is the codehash
// (in its cairo representation) and the value is the code.
// @dev: Accesses to the `code` field __MUST__ be done using `get_account_code`.
func get_account_code{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    state: State,
}(address: Address, account: Account) -> Bytes {
    alloc_locals;

    // Account code is already cached - return it
    if (cast(account.value.code.value, felt) != 0) {
        let res = Bytes(account.value.code.value);
        return res;
    }

    // Account code is not cached - load it and ensure hash(code) == code_hash
    let (code_) = alloc();
    tempvar code = code_;
    tempvar code_len: felt;
    %{ get_code_from_hash %}
    tempvar account_code = Bytes(new BytesStruct(data=code, len=code_len));

    // Soundness checks: ensure that hash(account_code) == account.value.code_hash
    let code_hash = keccak256(account_code);
    with_attr error_message("AssertionError") {
        assert code_hash.value.low = account.value.code_hash.value.low;
        assert code_hash.value.high = account.value.code_hash.value.high;
    }

    // Store it in the state for later retrievals
    tempvar account_with_code = OptionalAccount(
        new AccountStruct(
            nonce=account.value.nonce,
            balance=account.value.balance,
            code_hash=account.value.code_hash,
            storage_root=account.value.storage_root,
            code=OptionalBytes(account_code.value),
        ),
    );

    set_account(address, account_with_code);

    return account_code;
}

// @notice Returns the account for the given address.
// If the account does not exist, returns the empty account.
// @dev: The account returned by this function contains the right `codehash`, but the `code` field is lazily loaded.
// Accesses to the `code` field __MUST__ be done using `get_account_code`.
func get_account{range_check_ptr, state: State}(address: Address) -> Account {
    let account = get_account_optional{state=state}(address);

    if (cast(account.value, felt) == 0) {
        let empty_account = EMPTY_ACCOUNT();
        return empty_account;
    }

    tempvar res = Account(account.value);
    return res;
}

func set_account{range_check_ptr, state: State}(
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
    with_attr error_message("AssertionError") {
        assert is_sender_balance_sufficient.value = 1;
    }

    let new_sender_account_balance = U256_sub(sender_balance, amount);
    set_account_balance(sender_address, new_sender_account_balance);

    let recipient_account = get_account(recipient_address);
    let new_recipient_account_balance = U256_add(recipient_account.value.balance, amount);
    set_account_balance(recipient_address, new_recipient_account_balance);

    // If recipient account is now empty, destroy it.
    let is_recipient_empty = account_exists_and_is_empty(recipient_address);
    if (is_recipient_empty.value != 0) {
        destroy_account(recipient_address);
        return();
    }
    return ();
}

func process_withdrawal{range_check_ptr, poseidon_ptr: PoseidonBuiltin*, state: State}(
    withdrawal: Withdrawal
) {
    alloc_locals;

    let address = withdrawal.value.address;
    let amount = U256_mul(withdrawal.value.amount, U256(new U256Struct(10 ** 9, 0)));
    let account = get_account(address);
    let balance = account.value.balance;

    let new_balance = U256_add(balance, amount);
    set_account_balance(address, new_balance);
    return ();
}

func get_storage{range_check_ptr, state: State}(
    address: Address, key: Bytes32
) -> U256 {
    alloc_locals;
    let storage_tries = state.value._storage_tries;
    let value = trie_get_TrieTupleAddressBytes32U256{trie=storage_tries}(address, key);
    tempvar state = State(
        new StateStruct(
            _main_trie=state.value._main_trie,
            _storage_tries=storage_tries,
            created_accounts=state.value.created_accounts,
            original_storage_tries=state.value.original_storage_tries,
        ),
    );

    return value;
}
from mpt.types import EMPTY_TRIE_HASH_LOW, EMPTY_TRIE_HASH_HIGH

// @notice Destroys an account
// @dev This function should only be called to destroy accounts whose storage has not been mutated in the current transaction.
//      We rely on checks on the pre-block storage root to check whether we need to do the expensive operation of iterating over all storage keys to delete them.
func destroy_account{range_check_ptr, state: State}(
    address: Address
) {
    alloc_locals;
    let account = get_account(address);
    let none_account = OptionalAccount(cast(0, AccountStruct*));
    set_account(address, none_account);
    let storage_root = account.value.storage_root;
    if (storage_root.value.low == EMPTY_TRIE_HASH_LOW and
        storage_root.value.high == EMPTY_TRIE_HASH_HIGH) {
        return ();
    }
    // If the account had storage prior to this block, we need to destroy it
    // see eip-158, eip-161.
    destroy_storage(address);
    return ();
}

func increment_nonce{range_check_ptr, state: State}(address: Address) {
    alloc_locals;
    let account = get_account(address);
    // This increment is safe since
    // `validate_transaction` will not allow a transaction
    // with a nonce equal to max nonce (u64 as of today)
    let new_nonce = account.value.nonce.value + 1;
    tempvar new_account = OptionalAccount(
        new AccountStruct(
            nonce=Uint(new_nonce),
            balance=account.value.balance,
            code_hash=account.value.code_hash,
            storage_root=account.value.storage_root,
            code=account.value.code,
        ),
    );
    set_account(address, new_account);
    return ();
}
func set_storage{range_check_ptr, state: State}(
    address: Address, key: Bytes32, value: U256
) {
    alloc_locals;

    let storage_tries = state.value._storage_tries;
    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    // Assert that the account exists
    let account = get_account_optional(address);
    if (cast(account.value, felt) == 0) {
        raise('AssertionError');
    }
    let storage_trie = state.value._storage_tries;
    trie_set_TrieTupleAddressBytes32U256{trie=storage_trie}(address, key, value);

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

    let created_accounts = state.value.created_accounts;
    let is_created = set_address_contains{set=created_accounts}(address);
    StateImpl.set_created_accounts(created_accounts);

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
            created_accounts=state.value.created_accounts,
            original_storage_tries=new_original_storage_tries,
        ),
    );

    return value;
}

// @notice Destroys the storage of the given address.
// @dev The implementation of this function requires iterating over all storage keys present in the state,
// which is quite inefficient. This function should not be called outside of the unlikely case explained in
// `process_create_message`.
func destroy_storage{range_check_ptr, state: State}(
    address: Address
) {
    alloc_locals;

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    // Squash the storage tries for more efficient iteration
    let storage_tries = state.value._storage_tries;
    let storage_tries_start = cast(storage_tries.value._data.value.dict_ptr_start, DictAccess*);
    let storage_tries_end = cast(storage_tries.value._data.value.dict_ptr, DictAccess*);
    let (squashed_storage_tries_start, squashed_storage_tries_end) = dict_squash(
        storage_tries_start, storage_tries_end
    );
    tempvar squashed_storage_tries = TrieTupleAddressBytes32U256(
        new TrieTupleAddressBytes32U256Struct(
            secured=storage_tries.value.secured,
            default=storage_tries.value.default,
            _data=MappingTupleAddressBytes32U256(
                new MappingTupleAddressBytes32U256Struct(
                    dict_ptr_start=cast(
                        squashed_storage_tries_start, TupleAddressBytes32U256DictAccess*
                    ),
                    dict_ptr=cast(squashed_storage_tries_end, TupleAddressBytes32U256DictAccess*),
                    parent_dict=storage_tries.value._data.value.parent_dict,
                ),
            ),
        ),
    );

    // Gather the list of all storage keys belonging to this account and destroy them
    let dict_ptr_start = cast(squashed_storage_tries.value._data.value.dict_ptr_start, DictAccess*);
    let dict_ptr = cast(squashed_storage_tries.value._data.value.dict_ptr, DictAccess*);

    let (storage_keys_buffer: TupleAddressBytes32*) = alloc();
    tempvar slots = ListTupleAddressBytes32(
        new ListTupleAddressBytes32Struct(storage_keys_buffer, 0)
    );
    _get_storage_keys_for_address{
        dict_ptr_start=dict_ptr_start, dict_ptr=dict_ptr, slots=slots
    }(address);

    _destroy_storage_keys{storage_tries_ptr=dict_ptr}(slots, 0);
    let new_dict_ptr = cast(dict_ptr, TupleAddressBytes32U256DictAccess*);

    tempvar new_storage_tries_data = MappingTupleAddressBytes32U256(
        new MappingTupleAddressBytes32U256Struct(
            dict_ptr_start=squashed_storage_tries.value._data.value.dict_ptr_start,
            dict_ptr=new_dict_ptr,
            parent_dict=squashed_storage_tries.value._data.value.parent_dict,
        ),
    );

    tempvar new_storage_tries = TrieTupleAddressBytes32U256(
        new TrieTupleAddressBytes32U256Struct(
            squashed_storage_tries.value.secured,
            squashed_storage_tries.value.default,
            new_storage_tries_data,
        ),
    );
    tempvar state = State(
        new StateStruct(
            _main_trie=state.value._main_trie,
            _storage_tries=new_storage_tries,
            created_accounts=state.value.created_accounts,
            original_storage_tries=state.value.original_storage_tries,
        ),
    );

    return ();
}

// @notice Gathers all storage keys belonging to the given address.
// @dev This is expensive as it requires iterating over all storage keys present in the state.
//      However, this is only called when an empty account has storage, which is an unlikely event
//      see eip-158, eip-161.
func _get_storage_keys_for_address{
    range_check_ptr,
    dict_ptr_start: DictAccess*,
    dict_ptr: DictAccess*,
    slots: ListTupleAddressBytes32,
}(address: Address) {
    alloc_locals;

    let current = dict_ptr_start;
    let end = dict_ptr;

    if (current == end) {
        return ();
    }

    let key = [dict_ptr_start].key;
    let preimage = get_tuple_address_bytes32_preimage_for_key(key, end);

    if (preimage.value.address.value == address.value) {
        assert slots.value.data[slots.value.len] = preimage;
        tempvar slots = ListTupleAddressBytes32(
            new ListTupleAddressBytes32Struct(slots.value.data, slots.value.len + 1)
        );
    } else {
        tempvar slots = slots;
    }

    let next = current + DictAccess.SIZE;
    return _get_storage_keys_for_address{
        dict_ptr_start=next, dict_ptr=end, slots=slots
    }(address);
}

func _destroy_storage_keys{range_check_ptr, storage_tries_ptr: DictAccess*}(
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

    return _destroy_storage_keys{storage_tries_ptr=storage_tries_ptr}(keys, index + 1);
}

func get_transient_storage{range_check_ptr, transient_storage: TransientStorage}(
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
        new TransientStorageStruct(new_transient_storage_tries)
    );

    return value;
}

func set_transient_storage{range_check_ptr, transient_storage: TransientStorage}(
    address: Address, key: Bytes32, value: U256
) {
    alloc_locals;
    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let new_transient_storage_tries = transient_storage.value._tries;
    trie_set_TrieTupleAddressBytes32U256{trie=new_transient_storage_tries}(address, key, value);

    // Trie is not deleted if empty
    // From EELS https://github.com/ethereum/execution-specs/blob/5c82ed6ac3eb992c7d87320a3e771b5e852a06df/src/ethereum/cancun/state.py#L697:
    // if trie._data == {}:
    //    del transient_storage._tries[address]
    tempvar transient_storage = TransientStorage(
        new TransientStorageStruct(new_transient_storage_tries)
    );

    return ();
}

func account_exists{range_check_ptr, state: State}(address: Address) -> bool {
    let account = get_account_optional(address);

    if (cast(account.value, felt) == 0) {
        tempvar result = bool(0);
        return result;
    }
    tempvar result = bool(1);
    return result;
}

func account_has_code_or_nonce{range_check_ptr, state: State}(address: Address) -> bool {
    alloc_locals;

    let account = get_account(address);
    let (empty_hash_ptr) = get_label_location(EMPTY_HASH_KECCAK);
    tempvar empty_hash = Bytes32(cast(empty_hash_ptr, Bytes32Struct*));

    if (account.value.nonce.value != 0) {
        tempvar res = bool(1);
        return res;
    }

    // Return 0 if codehash is hash(b"")
    if (account.value.code_hash.value.low == empty_hash.value.low and
        account.value.code_hash.value.high == empty_hash.value.high) {
        tempvar res = bool(0);
        return res;
    }

    let res = bool(1);
    return res;
}

// @notice Returns all (address, key) pairs for a given address.
// This is a temporary fix specifically made for the `account_has_storage` function.
// We need to make a deeper refactor once we have a sound way to handle storage keys.
func get_storage_keys_for_address{dict_ptr: DictAccess*}(
    prefix_len: felt, prefix: felt*
) -> ListTupleAddressBytes32 {
    alloc_locals;

    local keys_len: felt;
    local keys: TupleAddressBytes32*;
    %{ get_storage_keys_for_address %}

    // warning: this is unsound as the prover can return any list of keys.
    tempvar res = ListTupleAddressBytes32(new ListTupleAddressBytes32Struct(keys, keys_len));
    return res;
}

func account_has_storage{range_check_ptr, state: State}(address: Address) -> bool {
    alloc_locals;

    let (empty_root_ptr_) = get_label_location(EMPTY_ROOT_KECCAK);
    let empty_root_ptr = cast(empty_root_ptr_, Bytes32Struct*);
    let account = get_account(address);
    if (empty_root_ptr.low == account.value.storage_root.value.low and
        empty_root_ptr.high == account.value.storage_root.value.high) {
        tempvar res = bool(0);
        return res;
    }
    tempvar res = bool(1);
    return res;
}

func is_account_empty{range_check_ptr, state: State}(address: Address) -> bool {
    // Get the account at the address
    let account = get_account(address);
    let (empty_hash_ptr) = get_label_location(EMPTY_HASH_KECCAK);
    tempvar empty_hash = Bytes32(cast(empty_hash_ptr, Bytes32Struct*));

    // Check if nonce is 0, code is empty, and balance is 0
    if (account.value.nonce.value != 0) {
        tempvar res = bool(0);
        return res;
    }

    // Check if codehash == hash(b"")
    if (account.value.code_hash.value.low != empty_hash.value.low) {
        tempvar res = bool(0);
        return res;
    }
    if (account.value.code_hash.value.high != empty_hash.value.high) {
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

func mark_account_created{range_check_ptr, state: State}(address: Address) {
    alloc_locals;

    let created_accounts = state.value.created_accounts;

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let set_dict_ptr = cast(created_accounts.value.dict_ptr, DictAccess*);
    hashdict_write{dict_ptr=set_dict_ptr}(1, &address.value, 1);

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
            created_accounts=new_created_account,
            original_storage_tries=state.value.original_storage_tries,
        ),
    );

    return ();
}

// @notice Returns whether the account exists and is empty.
// @dev Emptiness is defined by balance(acct) == 0, code(acct) == "" and nonce(acct) == 0;
//      emptiness of storage does not matter here. See eip-158.
func account_exists_and_is_empty{range_check_ptr, state: State}(
    address: Address
) -> bool {
    alloc_locals;
    // Get the account at the address
    let account = get_account_optional(address);

    let _empty_account = EMPTY_ACCOUNT();
    let empty_account = OptionalAccount(_empty_account.value);
    let is_empty_account = account_eq_without_storage_root(account, empty_account);

    return is_empty_account;
}

// @notice Returns whether the account is alive.
// @dev Emptiness is defined by balance(acct) == 0, code(acct) == "" and nonce(acct) == 0;
//      emptiness of storage does not matter here. See eip-158.
func is_account_alive{range_check_ptr, state: State}(address: Address) -> bool {
    alloc_locals;
    let account = get_account_optional(address);
    if (cast(account.value, felt) == 0) {
        tempvar res = bool(0);
        return res;
    }

    let _empty_account = EMPTY_ACCOUNT();
    let empty_account = OptionalAccount(_empty_account.value);
    let is_empty_account = account_eq_without_storage_root(account, empty_account);

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

    // Set original storage tries if in root transaction - indicated by a main trie with no parent
    // dict
    if (cast(state.value._main_trie.value._data.value.parent_dict, felt) == 0) {
        let storage_tries = state.value._storage_tries;
        let (new_dict_ptr_start, new_dict_ptr_end) = dict_copy(
            cast(storage_tries.value._data.value.dict_ptr_start, DictAccess*),
            cast(storage_tries.value._data.value.dict_ptr, DictAccess*),
        );
        tempvar original_storage_tries_data = MappingTupleAddressBytes32U256(
            new MappingTupleAddressBytes32U256Struct(
                dict_ptr_start=cast(new_dict_ptr_start, TupleAddressBytes32U256DictAccess*),
                dict_ptr=cast(new_dict_ptr_end, TupleAddressBytes32U256DictAccess*),
                parent_dict=cast(0, MappingTupleAddressBytes32U256Struct*),
            ),
        );
        tempvar original_storage_tries = TrieTupleAddressBytes32U256(
            new TrieTupleAddressBytes32U256Struct(
                secured=storage_tries.value.secured,
                default=storage_tries.value.default,
                _data=original_storage_tries_data,
            ),
        );
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar original_storage_tries = state.value.original_storage_tries;
        tempvar range_check_ptr = range_check_ptr;
    }

    // Copy the main trie
    let trie = state.value._main_trie;
    let copied_main_trie = copy_TrieAddressOptionalAccount{trie=trie}();

    // Copy the storage tries
    let storage_tries = state.value._storage_tries;
    let copied_storage_tries = copy_TrieTupleAddressBytes32U256{trie=storage_tries}();

    tempvar state = State(
        new StateStruct(
            _main_trie=copied_main_trie,
            _storage_tries=copied_storage_tries,
            created_accounts=state.value.created_accounts,
            original_storage_tries=original_storage_tries,
        ),
    );

    // Copy transient storage tries
    let transient_storage_tries = transient_storage.value._tries;
    let copied_transient_storage_tries = copy_TrieTupleAddressBytes32U256{
        trie=transient_storage_tries
    }();

    tempvar transient_storage = TransientStorage(
        new TransientStorageStruct(_tries=copied_transient_storage_tries)
    );

    return ();
}

func rollback_transaction{
    range_check_ptr,
    poseidon_ptr: PoseidonBuiltin*,
    state: State,
    transient_storage: TransientStorage,
}() {
    return close_transaction(drop=1);
}

func commit_transaction{
    range_check_ptr,
    poseidon_ptr: PoseidonBuiltin*,
    state: State,
    transient_storage: TransientStorage,
}() {
    return close_transaction(drop=0);
}

func close_transaction{
    range_check_ptr,
    poseidon_ptr: PoseidonBuiltin*,
    state: State,
    transient_storage: TransientStorage,
}(drop: felt) {
    alloc_locals;
    // State //

    // Main Trie
    let main_trie = state.value._main_trie;
    let main_trie_start = main_trie.value._data.value.dict_ptr_start;
    let main_trie_end = main_trie.value._data.value.dict_ptr;
    let parent_main_trie = main_trie.value._data.value.parent_dict;

    tempvar parent_main_trie_ptr = cast(parent_main_trie, felt);
    if (cast(parent_main_trie_ptr, felt) == 0) {
        raise('IndexError');
    }

    let parent_trie_start = parent_main_trie.dict_ptr_start;
    let parent_trie_end = parent_main_trie.dict_ptr;

    let (new_parent_trie_start, new_parent_trie_end) = dict_update(
        cast(main_trie_start, DictAccess*),
        cast(main_trie_end, DictAccess*),
        cast(parent_trie_start, DictAccess*),
        cast(parent_trie_end, DictAccess*),
        drop,
    );

    tempvar new_main_trie = TrieAddressOptionalAccount(
        new TrieAddressOptionalAccountStruct(
            secured=main_trie.value.secured,
            default=main_trie.value.default,
            _data=MappingAddressAccount(
                new MappingAddressAccountStruct(
                    dict_ptr_start=cast(new_parent_trie_start, AddressAccountDictAccess*),
                    dict_ptr=cast(new_parent_trie_end, AddressAccountDictAccess*),
                    parent_dict=parent_main_trie.parent_dict,
                ),
            ),
        ),
    );

    // Storage Tries
    let storage_tries = state.value._storage_tries;
    let storage_tries_start = storage_tries.value._data.value.dict_ptr_start;
    let storage_tries_end = storage_tries.value._data.value.dict_ptr;
    let parent_storage_tries = storage_tries.value._data.value.parent_dict;
    let parent_storage_tries_start = parent_storage_tries.dict_ptr_start;
    let parent_storage_tries_end = parent_storage_tries.dict_ptr;

    let (new_parent_storage_tries_dict_start, new_parent_storage_tries_dict) = dict_update(
        cast(storage_tries_start, DictAccess*),
        cast(storage_tries_end, DictAccess*),
        cast(parent_storage_tries_start, DictAccess*),
        cast(parent_storage_tries_end, DictAccess*),
        drop,
    );

    tempvar new_storage_tries = TrieTupleAddressBytes32U256(
        new TrieTupleAddressBytes32U256Struct(
            secured=storage_tries.value.secured,
            default=storage_tries.value.default,
            _data=MappingTupleAddressBytes32U256(
                new MappingTupleAddressBytes32U256Struct(
                    dict_ptr_start=cast(
                        new_parent_storage_tries_dict_start, TupleAddressBytes32U256DictAccess*
                    ),
                    dict_ptr=cast(
                        new_parent_storage_tries_dict, TupleAddressBytes32U256DictAccess*
                    ),
                    parent_dict=parent_storage_tries.parent_dict,
                ),
            ),
        ),
    );

    // If we're in the root state, we need to clear the created accounts
    let is_root_state = is_zero(cast(new_main_trie.value._data.value.parent_dict, felt));
    if (is_root_state != 0) {
        // Clear created accounts. Don't forget to squash the existing ones!
        default_dict_finalize(
            cast(state.value.created_accounts.value.dict_ptr_start, DictAccess*),
            cast(state.value.created_accounts.value.dict_ptr, DictAccess*),
            0,
        );
        let (new_created_accounts_ptr) = default_dict_new(0);
        tempvar new_created_accounts = SetAddress(
            new SetAddressStruct(
                dict_ptr_start=cast(new_created_accounts_ptr, SetAddressDictAccess*),
                dict_ptr=cast(new_created_accounts_ptr, SetAddressDictAccess*),
            ),
        );
        [ap] = range_check_ptr, ap++;
        [ap] = new_created_accounts.value, ap++;
    } else {
        [ap] = range_check_ptr, ap++;
        [ap] = state.value.created_accounts.value, ap++;
    }

    let range_check_ptr = [ap - 2];
    let new_created_accounts = SetAddress(cast([ap - 1], SetAddressStruct*));

    tempvar state = State(
        new StateStruct(
            _main_trie=new_main_trie,
            _storage_tries=new_storage_tries,
            created_accounts=new_created_accounts,
            original_storage_tries=state.value.original_storage_tries,
        ),
    );

    // Transient Storage //

    let transient_storage_tries = transient_storage.value._tries;
    let transient_storage_tries_start = transient_storage_tries.value._data.value.dict_ptr_start;
    let transient_storage_tries_end = transient_storage_tries.value._data.value.dict_ptr;
    let parent_transient_storage_tries = transient_storage_tries.value._data.value.parent_dict;

    tempvar parent_transient_storage_tries_ptr = cast(parent_transient_storage_tries, felt);
    if (cast(parent_transient_storage_tries_ptr, felt) == 0) {
        raise('IndexError');
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
        drop,
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
                    parent_dict=parent_transient_storage_tries.parent_dict,
                ),
            ),
        ),
    );

    tempvar transient_storage = TransientStorage(
        new TransientStorageStruct(_tries=new_transient_storage_tries)
    );

    return ();
}

func set_code{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    state: State,
}(address: Address, code: Bytes) {
    alloc_locals;

    let account = get_account(address);
    let code_hash = keccak256(code);

    // Create new account with updated code
    tempvar new_account = OptionalAccount(
        new AccountStruct(
            nonce=account.value.nonce,
            balance=account.value.balance,
            code_hash=code_hash,
            storage_root=account.value.storage_root,
            code=OptionalBytes(code.value),
        ),
    );

    // Set the updated account
    set_account(address, new_account);
    return ();
}

func set_account_balance{range_check_ptr, state: State}(
    address: Address, amount: U256
) {
    alloc_locals;
    let account = get_account(address);

    tempvar new_account = OptionalAccount(
        new AccountStruct(
            nonce=account.value.nonce,
            balance=amount,
            code_hash=account.value.code_hash,
            storage_root=account.value.storage_root,
            code=account.value.code,
        ),
    );

    // Inlining logic of modify_state: an empty account should be destroyed
    let _empty_account = EMPTY_ACCOUNT();
    let empty_account = OptionalAccount(_empty_account.value);
    let is_empty_account = account_eq_without_storage_root(new_account, empty_account);
    if (is_empty_account.value != 0) {
        destroy_account(address);
        return();
    }
    set_account(address, new_account);

    return ();
}


func empty_transient_storage{range_check_ptr}() -> TransientStorage {
    let (default_value) = get_label_location(U256_ZERO);
    let (dict_ptr) = default_dict_new(cast(default_value, felt));
    let dict_start = cast(dict_ptr, TupleAddressBytes32U256DictAccess*);

    tempvar mapping = MappingTupleAddressBytes32U256(
        new MappingTupleAddressBytes32U256Struct(
            dict_ptr_start=dict_start,
            dict_ptr=dict_start,
            parent_dict=cast(0, MappingTupleAddressBytes32U256Struct*),
        ),
    );

    tempvar tries = TrieTupleAddressBytes32U256(
        new TrieTupleAddressBytes32U256Struct(
            secured=bool(1), default=U256(cast(default_value, U256Struct*)), _data=mapping
        ),
    );

    tempvar transient_storage = TransientStorage(new TransientStorageStruct(_tries=tries));

    return transient_storage;
}

// @notice Computes the storage roots of all the addresses in the state
// @dev The input state must've been squashed for unique keys.
func storage_roots{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: felt*, poseidon_ptr: PoseidonBuiltin*
}(state: State, hash_function_name: felt) -> MappingAddressBytes32 {
    alloc_locals;

    if (cast(state.value._main_trie.value._data.value.parent_dict, felt) != 0) {
        raise('AssertionError');
    }

    // Create a Mapping[Address, Trie[Bytes32, U256]] that will contain the "flat" tries, where we
    // will get the storage trie of each address
    let (map_addr_storage_start) = default_dict_new(0);
    tempvar map_addr_storage = MappingAddressTrieBytes32U256(
        new MappingAddressTrieBytes32U256Struct(
            dict_ptr_start=cast(map_addr_storage_start, AddressTrieBytes32U256DictAccess*),
            dict_ptr=cast(map_addr_storage_start, AddressTrieBytes32U256DictAccess*),
            parent_dict=cast(0, MappingAddressTrieBytes32U256Struct*),
        ),
    );

    let squashed_storage_tries_start = cast(
        state.value._storage_tries.value._data.value.dict_ptr_start, DictAccess*
    );
    let squashed_storage_tries_end = cast(
        state.value._storage_tries.value._data.value.dict_ptr, DictAccess*
    );
    build_map_addr_storage_trie{
        map_addr_storage=map_addr_storage, storage_tries_ptr_end=squashed_storage_tries_end
    }(squashed_storage_tries_start);

    // Squash the Mapping[address, trie[bytes32, u256]] to iterate over each address
    let (squashed_map_addr_storage_start, squashed_map_addr_storage_end) = default_dict_finalize(
        cast(map_addr_storage.value.dict_ptr_start, DictAccess*),
        cast(map_addr_storage.value.dict_ptr, DictAccess*),
        0,
    );

    tempvar map_addr_storage = MappingAddressTrieBytes32U256(
        new MappingAddressTrieBytes32U256Struct(
            dict_ptr_start=cast(squashed_map_addr_storage_start, AddressTrieBytes32U256DictAccess*),
            dict_ptr=cast(squashed_map_addr_storage_end, AddressTrieBytes32U256DictAccess*),
            parent_dict=cast(0, MappingAddressTrieBytes32U256Struct*),
        ),
    );

    // Create a Mapping[Address, Bytes32] that will contain the storage root of each address's
    // storage trie
    // TODO: the EMPTY_ROOT should be relative to the hash function used!
    local empty_root_ptr: felt*;
    if (hash_function_name == 'keccak256') {
        let (ptr) = get_label_location(EMPTY_ROOT_KECCAK);
        assert empty_root_ptr = ptr;
    } else {
        // TODO: extend this if-else if we add other hash functions
        let (ptr) = get_label_location(EMPTY_ROOT_BLAKE2S);
        assert empty_root_ptr = ptr;
    }
    let (map_addr_storage_root_start) = default_dict_new(cast(empty_root_ptr, felt));
    tempvar map_addr_storage_root = MappingAddressBytes32(
        new MappingAddressBytes32Struct(
            dict_ptr_start=cast(map_addr_storage_root_start, AddressBytes32DictAccess*),
            dict_ptr=cast(map_addr_storage_root_start, AddressBytes32DictAccess*),
            parent_dict=cast(0, MappingAddressBytes32Struct*),
        ),
    );

    // Iterate over each address, and get the root of its storage trie
    let map_addr_storage_ptr = cast(
        squashed_map_addr_storage_start, AddressTrieBytes32U256DictAccess*
    );
    let map_addr_storage_ptr_end = cast(
        squashed_map_addr_storage_end, AddressTrieBytes32U256DictAccess*
    );
    build_map_addr_storage_root{
        map_addr_storage_root=map_addr_storage_root,
        map_addr_storage_ptr_end=map_addr_storage_ptr_end,
    }(map_addr_storage_ptr, hash_function_name);

    return map_addr_storage_root;
}

// @notice Builds a Mapping[Address, Bytes32] that contains the storage root of each address's
// storage trie
// @param map_addr_storage_root The mapping to write to
// @param map_addr_storage_ptr The pointer to the current address in the Mapping[Address, Trie[Bytes32, U256]]
// @param map_addr_storage_ptr_end The end of the Mapping[Address, Trie[Bytes32, U256]]
func build_map_addr_storage_root{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    map_addr_storage_root: MappingAddressBytes32,
    map_addr_storage_ptr_end: AddressTrieBytes32U256DictAccess*,
}(map_addr_storage_ptr: AddressTrieBytes32U256DictAccess*, hash_function_name: felt) {
    alloc_locals;

    if (map_addr_storage_ptr == map_addr_storage_ptr_end) {
        return ();
    }

    let address = map_addr_storage_ptr.key;
    let storage_trie = map_addr_storage_ptr.new_value;

    tempvar union_trie = EthereumTries(
        new EthereumTriesEnum(
            account=TrieAddressOptionalAccount(cast(0, TrieAddressOptionalAccountStruct*)),
            storage=storage_trie,
            transaction=TrieBytesOptionalUnionBytesLegacyTransaction(
                cast(0, TrieBytesOptionalUnionBytesLegacyTransactionStruct*)
            ),
            receipt=TrieBytesOptionalUnionBytesReceipt(
                cast(0, TrieBytesOptionalUnionBytesReceiptStruct*)
            ),
            withdrawal=TrieBytesOptionalUnionBytesWithdrawal(
                cast(0, TrieBytesOptionalUnionBytesWithdrawalStruct*)
            ),
        ),
    );

    let storage_root = root(
        union_trie,
        OptionalMappingAddressBytes32(cast(0, MappingAddressBytes32Struct*)),
        hash_function_name,
    );

    mapping_address_bytes32_write{mapping=map_addr_storage_root}(address, storage_root);

    // Squash the Trie[Bytes32, U256] - it won't ever be used again.
    let trie_ptr_start = storage_trie.value._data.value.dict_ptr_start;
    let trie_ptr_end = storage_trie.value._data.value.dict_ptr;
    default_dict_finalize(
        cast(trie_ptr_start, DictAccess*),
        cast(trie_ptr_end, DictAccess*),
        cast(storage_trie.value.default.value, felt),
    );

    return build_map_addr_storage_root(map_addr_storage_ptr + DictAccess.SIZE, hash_function_name);
}

// @notice Builds a Mapping[Address, Trie[Bytes32, U256]] that contains the storage trie of each
// address
// @param map_addr_storage The mapping to write to
// @param storage_tries_ptr The pointer to the current entry in the Trie[Tuple[Address, Bytes32], U256]
// @param storage_tries_ptr_end The end of the Trie[Tuple[Address, Bytes32], U256]
func build_map_addr_storage_trie{
    range_check_ptr,
    poseidon_ptr: PoseidonBuiltin*,
    map_addr_storage: MappingAddressTrieBytes32U256,
    storage_tries_ptr_end: DictAccess*,
}(storage_tries_ptr: DictAccess*) {
    alloc_locals;

    if (storage_tries_ptr == storage_tries_ptr_end) {
        return ();
    }

    // Skip all None values, which are deleted trie entries. We don't need them to compute
    // the storage roots.
    if (cast(storage_tries_ptr.new_value, felt) == 0) {
        return build_map_addr_storage_trie(storage_tries_ptr + DictAccess.SIZE);
    }

    let tup_address_b32 = get_tuple_address_bytes32_preimage_for_key(
        storage_tries_ptr.key, storage_tries_ptr_end
    );
    build_storage_trie_for_address(
        tup_address_b32.value.address,
        tup_address_b32.value.bytes32,
        U256(cast(storage_tries_ptr.new_value, U256Struct*)),
    );

    return build_map_addr_storage_trie(storage_tries_ptr + DictAccess.SIZE);
}

// @notice Modifies a Trie[Bytes32, U256], the storage trie of an address, and adds it to the
// Mapping[Address, Trie[Bytes32, U256]]
// @param address The address to build the storage trie for
// @param key The key to add to the storage trie
// @param value The value to add to the storage trie
func build_storage_trie_for_address{
    range_check_ptr, poseidon_ptr: PoseidonBuiltin*, map_addr_storage: MappingAddressTrieBytes32U256
}(address: Address, key: Bytes32, value: U256) {
    alloc_locals;

    let dict_ptr = cast(map_addr_storage.value.dict_ptr, DictAccess*);

    // Get storage trie for address
    let trie = mapping_address_trie_bytes32_u256_read{mapping=map_addr_storage}(address);

    // Modify storage trie for address
    trie_set_TrieBytes32U256{trie=trie}(key, value);

    // Update the mapping address -> trie
    mapping_address_trie_bytes32_u256_write{mapping=map_addr_storage}(address, trie);

    return ();
}

// @notice Computes the state root of the state
// @dev Squashes the main trie for unique keys, and updates the state with the new, squashed segment.
func state_root{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: felt*, poseidon_ptr: PoseidonBuiltin*
}(state: State, hash_function_name: felt) -> Bytes32 {
    alloc_locals;

    if (cast(state.value._main_trie.value._data.value.parent_dict, felt) != 0) {
        raise('AssertionError');
    }

    let storage_roots_ = storage_roots(state, hash_function_name);

    tempvar trie_union = EthereumTries(
        new EthereumTriesEnum(
            account=state.value._main_trie,
            storage=TrieBytes32U256(cast(0, TrieBytes32U256Struct*)),
            transaction=TrieBytesOptionalUnionBytesLegacyTransaction(
                cast(0, TrieBytesOptionalUnionBytesLegacyTransactionStruct*)
            ),
            receipt=TrieBytesOptionalUnionBytesReceipt(
                cast(0, TrieBytesOptionalUnionBytesReceiptStruct*)
            ),
            withdrawal=TrieBytesOptionalUnionBytesWithdrawal(
                cast(0, TrieBytesOptionalUnionBytesWithdrawalStruct*)
            ),
        ),
    );

    let state_root = root(
        trie_union, OptionalMappingAddressBytes32(storage_roots_.value), hash_function_name
    );
    return state_root;
}

// Utils function, porting this to a module would incur a lot of refactoring due to circular imports
func mapping_address_trie_bytes32_u256_read{
    range_check_ptr, mapping: MappingAddressTrieBytes32U256
}(key: Address) -> TrieBytes32U256 {
    alloc_locals;
    let dict_ptr = cast(mapping.value.dict_ptr, DictAccess*);
    let (value_ptr) = dict_read{dict_ptr=dict_ptr}(key.value);

    if (cast(value_ptr, felt) == 0) {
        tempvar default = new U256Struct(0, 0);
        let (segment_start) = default_dict_new(cast(default, felt));
        tempvar trie_ptr = new TrieBytes32U256Struct(
            secured=bool(1),
            default=U256(default),
            _data=MappingBytes32U256(
                new MappingBytes32U256Struct(
                    dict_ptr_start=cast(segment_start, Bytes32U256DictAccess*),
                    dict_ptr=cast(segment_start, Bytes32U256DictAccess*),
                    parent_dict=cast(0, MappingBytes32U256Struct*),
                ),
            ),
        );
    } else {
        tempvar trie_ptr = cast(value_ptr, TrieBytes32U256Struct*);
    }

    tempvar mapping = MappingAddressTrieBytes32U256(
        new MappingAddressTrieBytes32U256Struct(
            dict_ptr_start=mapping.value.dict_ptr_start,
            dict_ptr=cast(dict_ptr, AddressTrieBytes32U256DictAccess*),
            parent_dict=mapping.value.parent_dict,
        ),
    );
    let trie = TrieBytes32U256(trie_ptr);
    return trie;
}

// Utils function, porting this to a module would incur a lot of refactoring due to circular imports
func mapping_address_trie_bytes32_u256_write{
    range_check_ptr, mapping: MappingAddressTrieBytes32U256
}(key: Address, value: TrieBytes32U256) {
    alloc_locals;
    let dict_ptr = cast(mapping.value.dict_ptr, DictAccess*);
    let value_felt = cast(value.value, felt);
    dict_write{dict_ptr=dict_ptr}(key.value, value_felt);

    tempvar mapping = MappingAddressTrieBytes32U256(
        new MappingAddressTrieBytes32U256Struct(
            dict_ptr_start=mapping.value.dict_ptr_start,
            dict_ptr=cast(dict_ptr, AddressTrieBytes32U256DictAccess*),
            parent_dict=mapping.value.parent_dict,
        ),
    );
    return ();
}

// Utils function, porting this to a module would incur a lot of refactoring due to circular imports
func mapping_address_bytes32_write{range_check_ptr, mapping: MappingAddressBytes32}(
    key: Address, value: Bytes32
) {
    alloc_locals;
    let dict_ptr = cast(mapping.value.dict_ptr, DictAccess*);
    let value_felt = cast(value.value, felt);
    dict_write{dict_ptr=dict_ptr}(key.value, value_felt);
    tempvar mapping = MappingAddressBytes32(
        new MappingAddressBytes32Struct(
            dict_ptr_start=mapping.value.dict_ptr_start,
            dict_ptr=cast(dict_ptr, AddressBytes32DictAccess*),
            parent_dict=mapping.value.parent_dict,
        ),
    );
    return ();
}

// @notice Finalizes a `State` struct by squashing all of its field.
// @dev Squashing the main_trie and storage_tries not only de-duplicates the keys, but also
//      sorts them in ascending order of tuple (key, prev_value, new_value), which is important
//      in the logic of producing state diffs.
func finalize_state{range_check_ptr, state: State}() {
    alloc_locals;
    // Squash the main trie for unique keys
    let main_trie = state.value._main_trie;
    let main_trie_start = cast(main_trie.value._data.value.dict_ptr_start, DictAccess*);
    let main_trie_end = cast(main_trie.value._data.value.dict_ptr, DictAccess*);

    let (squashed_main_trie_start, squashed_main_trie_end) = dict_squash(
        main_trie_start, main_trie_end
    );

    tempvar squashed_main_trie = TrieAddressOptionalAccount(
        new TrieAddressOptionalAccountStruct(
            secured=state.value._main_trie.value.secured,
            default=state.value._main_trie.value.default,
            _data=MappingAddressAccount(
                new MappingAddressAccountStruct(
                    dict_ptr_start=cast(squashed_main_trie_start, AddressAccountDictAccess*),
                    dict_ptr=cast(squashed_main_trie_end, AddressAccountDictAccess*),
                    parent_dict=cast(0, MappingAddressAccountStruct*),
                ),
            ),
        ),
    );

    // Get the Trie[Tuple[Address, Bytes32], U256] storage tries, and squash them for unique keys
    let storage_tries = state.value._storage_tries;
    let storage_tries_start = cast(storage_tries.value._data.value.dict_ptr_start, DictAccess*);
    let storage_tries_end = cast(storage_tries.value._data.value.dict_ptr, DictAccess*);

    let (squashed_storage_tries_start, squashed_storage_tries_end) = dict_squash(
        storage_tries_start, storage_tries_end
    );

    // Update the state by rebinding the squashed storage tries
    tempvar squashed_storage_tries = TrieTupleAddressBytes32U256(
        new TrieTupleAddressBytes32U256Struct(
            secured=storage_tries.value.secured,
            default=storage_tries.value.default,
            _data=MappingTupleAddressBytes32U256(
                new MappingTupleAddressBytes32U256Struct(
                    dict_ptr_start=cast(
                        squashed_storage_tries_start, TupleAddressBytes32U256DictAccess*
                    ),
                    dict_ptr=cast(squashed_storage_tries_end, TupleAddressBytes32U256DictAccess*),
                    parent_dict=cast(0, MappingTupleAddressBytes32U256Struct*),
                ),
            ),
        ),
    );

    // Squash the created_accounts mapping for soundness
    let created_accounts = state.value.created_accounts;
    let created_accounts_start = cast(created_accounts.value.dict_ptr_start, DictAccess*);
    let created_accounts_end = cast(created_accounts.value.dict_ptr, DictAccess*);

    let (squashed_created_accounts_start, squashed_created_accounts_end) = dict_squash(
        created_accounts_start, created_accounts_end
    );

    tempvar squashed_created_accounts = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=cast(squashed_created_accounts_start, SetAddressDictAccess*),
            dict_ptr=cast(squashed_created_accounts_end, SetAddressDictAccess*),
        ),
    );

    // Squash the original_storage_tries mapping for soundness - if that mapping is defined.
    let original_storage_tries = state.value.original_storage_tries;
    let original_storage_tries_start = cast(
        original_storage_tries.value._data.value.dict_ptr_start, DictAccess*
    );
    let original_storage_tries_end = cast(
        original_storage_tries.value._data.value.dict_ptr, DictAccess*
    );

    let (squashed_original_storage_tries_start, squashed_original_storage_tries_end) = dict_squash(
        original_storage_tries_start, original_storage_tries_end
    );

    tempvar squashed_original_storage_tries = TrieTupleAddressBytes32U256(
        new TrieTupleAddressBytes32U256Struct(
            secured=original_storage_tries.value.secured,
            default=original_storage_tries.value.default,
            _data=MappingTupleAddressBytes32U256(
                new MappingTupleAddressBytes32U256Struct(
                    dict_ptr_start=cast(
                        squashed_original_storage_tries_start, TupleAddressBytes32U256DictAccess*
                    ),
                    dict_ptr=cast(
                        squashed_original_storage_tries_end, TupleAddressBytes32U256DictAccess*
                    ),
                    parent_dict=cast(0, MappingTupleAddressBytes32U256Struct*),
                ),
            ),
        ),
    );
    // Re-bind the state with the squashed dicts
    tempvar state = State(
        new StateStruct(
            _main_trie=squashed_main_trie,
            _storage_tries=squashed_storage_tries,
            created_accounts=squashed_created_accounts,
            original_storage_tries=squashed_original_storage_tries,
        ),
    );

    return ();
}

// @notice Finalizes a `TransientStorage` struct by squashing all of its field.
func finalize_transient_storage{range_check_ptr, transient_storage: TransientStorage}() {
    alloc_locals;

    let transient_storage_tries = transient_storage.value._tries;
    let transient_storage_tries_start = cast(
        transient_storage_tries.value._data.value.dict_ptr_start, DictAccess*
    );
    let transient_storage_tries_end = cast(
        transient_storage_tries.value._data.value.dict_ptr, DictAccess*
    );

    let (
        squashed_transient_storage_tries_start, squashed_transient_storage_tries_end
    ) = dict_squash(transient_storage_tries_start, transient_storage_tries_end);

    tempvar squashed_transient_storage_tries = TrieTupleAddressBytes32U256(
        new TrieTupleAddressBytes32U256Struct(
            secured=transient_storage_tries.value.secured,
            default=transient_storage_tries.value.default,
            _data=MappingTupleAddressBytes32U256(
                new MappingTupleAddressBytes32U256Struct(
                    dict_ptr_start=cast(
                        squashed_transient_storage_tries_start, TupleAddressBytes32U256DictAccess*
                    ),
                    dict_ptr=cast(
                        squashed_transient_storage_tries_end, TupleAddressBytes32U256DictAccess*
                    ),
                    parent_dict=cast(0, MappingTupleAddressBytes32U256Struct*),
                ),
            ),
        ),
    );

    tempvar transient_storage = TransientStorage(
        new TransientStorageStruct(_tries=squashed_transient_storage_tries)
    );

    return ();
}
