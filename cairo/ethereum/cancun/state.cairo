from ethereum.cancun.fork_types import Address, Account, MappingAddressAccount, SetAddress
from ethereum.cancun.trie import TrieBytesU256, TrieAddressAccount
from ethereum_types.bytes import Bytes
from ethereum_types.numeric import U256

struct AddressTrieBytesU256DictAccess {
    key: Address,
    prev_value: TrieBytesU256,
    new_value: TrieBytesU256,
}

struct MappingAddressTrieBytesU256Struct {
    dict_ptr_start: AddressTrieBytesU256DictAccess*,
    dict_ptr: AddressTrieBytesU256DictAccess*,
}

struct MappingAddressTrieBytesU256 {
    value: MappingAddressTrieBytesU256Struct*,
}

struct TupleTrieAddressAccountMappingAddressTrieBytesU256Struct {
    trie_address_account: TrieAddressAccount,
    mapping_address_trie: MappingAddressTrieBytesU256,
}

struct TupleTrieAddressAccountMappingAddressTrieBytesU256 {
    value: TupleTrieAddressAccountMappingAddressTrieBytesU256Struct*,
}

struct ListTupleTrieAddressAccountMappingAddressTrieBytesU256Struct {
    data: TupleTrieAddressAccountMappingAddressTrieBytesU256*,
    len: felt,
}

struct ListTupleTrieAddressAccountMappingAddressTrieBytesU256 {
    value: ListTupleTrieAddressAccountMappingAddressTrieBytesU256Struct*,
}

struct TransientStorageSnapshotsStruct {
    data: MappingAddressTrieBytesU256*,
    len: felt,
}

struct TransientStorageSnapshots {
    value: TransientStorageSnapshotsStruct*,
}

struct TransientStorageStruct {
    _tries: MappingAddressTrieBytesU256,
    _snapshots: TransientStorageSnapshots,
}

struct TransientStorage {
    value: TransientStorageStruct*,
}

struct StateStruct {
    _main_trie: TrieAddressAccount,
    _storage_tries: MappingAddressTrieBytesU256,
    _snapshots: ListTupleTrieAddressAccountMappingAddressTrieBytesU256,
    created_accounts: SetAddress,
}

struct State {
    value: StateStruct*,
}
