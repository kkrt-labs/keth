from ethereum.base_types import U256, Bytes, Uint, modify
from ethereum.cancun.blocks import Withdrawal
from ethereum.cancun.fork_types import EMPTY_ACCOUNT, Account, Address, Root
from ethereum.cancun.trie import EMPTY_TRIE_ROOT, Trie, copy_trie, root, trie_get, trie_set

struct State {
    _main_trie: Trie[Address, Account],
    _storage_tries: Dict[Address, Trie[Bytes, U256]],
    _snapshots: Tuple[Trie[Address, Account], Dict[Address, Trie[Bytes, U256]]],
    created_accounts: Address,
}

struct TransientStorage {
    _tries: Dict[Address, Trie[Bytes, U256]],
    _snapshots: Dict[Address, Trie[Bytes, U256]],
}


func close_state(state: State) {
    // Implementation:
    // del state._main_trie
    // del state._storage_tries
    // del state._snapshots
    // del state.created_accounts
}

func begin_transaction(state: State, transient_storage: TransientStorage) {
    // Implementation:
    // state._snapshots.append((copy_trie(state._main_trie), {k: copy_trie(t) for (k, t) in state._storage_tries.items()}))
    // transient_storage._snapshots.append({k: copy_trie(t) for (k, t) in transient_storage._tries.items()})
}

func commit_transaction(state: State, transient_storage: TransientStorage) {
    // Implementation:
    // state._snapshots.pop()
    // if not state._snapshots:
    // state.created_accounts.clear()
        // state.created_accounts.clear()
    // transient_storage._snapshots.pop()
}

func rollback_transaction(state: State, transient_storage: TransientStorage) {
    // Implementation:
    // (state._main_trie, state._storage_tries) = state._snapshots.pop()
    // if not state._snapshots:
    // state.created_accounts.clear()
        // state.created_accounts.clear()
    // transient_storage._tries = transient_storage._snapshots.pop()
}

func get_account(state: State, address: Address) -> Account {
    // Implementation:
    // account = get_account_optional(state, address)
    // if isinstance(account, Account):
    // return account
    // else:
    // return EMPTY_ACCOUNT
        // return account
    // else:
        // return EMPTY_ACCOUNT
}

func get_account_optional(state: State, address: Address) -> Account {
    // Implementation:
    // account = trie_get(state._main_trie, address)
    // return account
}

func set_account(state: State, address: Address, account: Account) {
    // Implementation:
    // trie_set(state._main_trie, address, account)
}

func destroy_account(state: State, address: Address) {
    // Implementation:
    // destroy_storage(state, address)
    // set_account(state, address, None)
}

func destroy_storage(state: State, address: Address) {
    // Implementation:
    // if address in state._storage_tries:
    // del state._storage_tries[address]
        // del state._storage_tries[address]
}

func mark_account_created(state: State, address: Address) {
    // Implementation:
    // state.created_accounts.add(address)
}

func get_storage(state: State, address: Address, key: Bytes) -> U256 {
    // Implementation:
    // trie = state._storage_tries.get(address)
    // if trie is None:
    // return U256(0)
        // return U256(0)
    // value = trie_get(trie, key)
    // assert isinstance(value, U256)
    // return value
}

func set_storage(state: State, address: Address, key: Bytes, value: U256) {
    // Implementation:
    // assert trie_get(state._main_trie, address) is not None
    // trie = state._storage_tries.get(address)
    // if trie is None:
    // trie = Trie(secured=True, default=U256(0))
    // state._storage_tries[address] = trie
        // trie = Trie(secured=True, default=U256(0))
        // state._storage_tries[address] = trie
    // trie_set(trie, key, value)
    // if trie._data == {}:
    // del state._storage_tries[address]
        // del state._storage_tries[address]
}

func storage_root(state: State, address: Address) -> Root {
    // Implementation:
    // assert not state._snapshots
    // if address in state._storage_tries:
    // return root(state._storage_tries[address])
    // else:
    // return EMPTY_TRIE_ROOT
        // return root(state._storage_tries[address])
    // else:
        // return EMPTY_TRIE_ROOT
}

func state_root(state: State) -> Root {
    // Implementation:
    // assert not state._snapshots
    // def get_storage_root(address: Address) -> Root:
    // return storage_root(state, address)
    // return root(state._main_trie, get_storage_root=get_storage_root)
}

func account_exists(state: State, address: Address) -> bool {
    // Implementation:
    // return get_account_optional(state, address) is not None
}

func account_has_code_or_nonce(state: State, address: Address) -> bool {
    // Implementation:
    // account = get_account(state, address)
    // return account.nonce != Uint(0) or account.code != b''
}

func is_account_empty(state: State, address: Address) -> bool {
    // Implementation:
    // account = get_account(state, address)
    // return account.nonce == Uint(0) and account.code == b'' and (account.balance == 0)
}

func account_exists_and_is_empty(state: State, address: Address) -> bool {
    // Implementation:
    // account = get_account_optional(state, address)
    // return account is not None and account.nonce == Uint(0) and (account.code == b'') and (account.balance == 0)
}

func is_account_alive(state: State, address: Address) -> bool {
    // Implementation:
    // account = get_account_optional(state, address)
    // if account is None:
    // return False
    // else:
    // return not (account.nonce == Uint(0) and account.code == b'' and (account.balance == 0))
        // return False
    // else:
        // return not (account.nonce == Uint(0) and account.code == b'' and (account.balance == 0))
}

func modify_state(state: State, address: Address, f: Callable[List(elts=[Name(id='Account', ctx=Load())], ctx=Load()), None]) {
    // Implementation:
    // set_account(state, address, modify(get_account(state, address), f))
}

func move_ether(state: State, sender_address: Address, recipient_address: Address, amount: U256) {
    // Implementation:
    // def reduce_sender_balance(sender: Account) -> None:
    // if sender.balance < amount:
    // raise AssertionError
    // sender.balance -= amount
    // def increase_recipient_balance(recipient: Account) -> None:
    // recipient.balance += amount
    // modify_state(state, sender_address, reduce_sender_balance)
    // modify_state(state, recipient_address, increase_recipient_balance)
}

func process_withdrawal(state: State, wd: Withdrawal) {
    // Implementation:
    // def increase_recipient_balance(recipient: Account) -> None:
    // recipient.balance += wd.amount * 10 ** 9
    // modify_state(state, wd.address, increase_recipient_balance)
}

func set_account_balance(state: State, address: Address, amount: U256) {
    // Implementation:
    // def set_balance(account: Account) -> None:
    // account.balance = amount
    // modify_state(state, address, set_balance)
}

func touch_account(state: State, address: Address) {
    // Implementation:
    // if not account_exists(state, address):
    // set_account(state, address, EMPTY_ACCOUNT)
        // set_account(state, address, EMPTY_ACCOUNT)
}

func increment_nonce(state: State, address: Address) {
    // Implementation:
    // def increase_nonce(sender: Account) -> None:
    // sender.nonce += 1
    // modify_state(state, address, increase_nonce)
}

func set_code(state: State, address: Address, code: Bytes) {
    // Implementation:
    // def write_code(sender: Account) -> None:
    // sender.code = code
    // modify_state(state, address, write_code)
}

func get_storage_original(state: State, address: Address, key: Bytes) -> U256 {
    // Implementation:
    // if address in state.created_accounts:
    // return U256(0)
        // return U256(0)
    // (_, original_trie) = state._snapshots[0]
    // original_account_trie = original_trie.get(address)
    // if original_account_trie is None:
    // original_value = U256(0)
    // else:
    // original_value = trie_get(original_account_trie, key)
        // original_value = U256(0)
    // else:
        // original_value = trie_get(original_account_trie, key)
    // assert isinstance(original_value, U256)
    // return original_value
}

func get_transient_storage(transient_storage: TransientStorage, address: Address, key: Bytes) -> U256 {
    // Implementation:
    // trie = transient_storage._tries.get(address)
    // if trie is None:
    // return U256(0)
        // return U256(0)
    // value = trie_get(trie, key)
    // assert isinstance(value, U256)
    // return value
}

func set_transient_storage(transient_storage: TransientStorage, address: Address, key: Bytes, value: U256) {
    // Implementation:
    // trie = transient_storage._tries.get(address)
    // if trie is None:
    // trie = Trie(secured=True, default=U256(0))
    // transient_storage._tries[address] = trie
        // trie = Trie(secured=True, default=U256(0))
        // transient_storage._tries[address] = trie
    // trie_set(trie, key, value)
    // if trie._data == {}:
    // del transient_storage._tries[address]
        // del transient_storage._tries[address]
}

func destroy_touched_empty_accounts(state: State, touched_accounts: Address) {
    // Implementation:
    // for address in touched_accounts:
    // if account_exists_and_is_empty(state, address):
    // destroy_account(state, address)
        // if account_exists_and_is_empty(state, address):
        // destroy_account(state, address)
            // destroy_account(state, address)
}
