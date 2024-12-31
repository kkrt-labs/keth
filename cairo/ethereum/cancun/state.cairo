from ethereum.cancun.fork_types import Address
from ethereum.cancun.trie import TrieBytesU256
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
