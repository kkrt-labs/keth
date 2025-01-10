from starkware.cairo.common.cairo_builtins import PoseidonBuiltin

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
    AccountStruct,
)
from ethereum_types.bytes import Bytes
from ethereum_types.numeric import U256

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
