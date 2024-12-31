from ethereum.cancun.fork_types import Address, VersionedHash, ListHash32, TupleVersionedHash
from ethereum.cancun.state import State, TransientStorage
from ethereum.crypto.hash import Hash32
from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U64, U256, Uint

struct EnvironmentStruct {
    caller: Address,
    block_hashes: ListHash32,
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
    excess_blob_gas: U64,
    blob_versioned_hashes: TupleVersionedHash,
    transient_storage: TransientStorage,
}

struct Environment {
    value: EnvironmentStruct*,
}
