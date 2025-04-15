from ethereum.cancun.state import (
    State,
    TransientStorage,
    finalize_state,
    finalize_transient_storage,
)
from ethereum.cancun.fork_types import Address, ListHash32, TupleVersionedHash
from ethereum_types.numeric import Uint, U256, U64
from ethereum_types.bytes import Bytes32

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

// In a specific file to avoid circular imports
namespace EnvImpl {
    func set_state{env: Environment}(new_state: State) {
        tempvar env = Environment(
            new EnvironmentStruct(
                caller=env.value.caller,
                block_hashes=env.value.block_hashes,
                origin=env.value.origin,
                coinbase=env.value.coinbase,
                number=env.value.number,
                base_fee_per_gas=env.value.base_fee_per_gas,
                gas_limit=env.value.gas_limit,
                gas_price=env.value.gas_price,
                time=env.value.time,
                prev_randao=env.value.prev_randao,
                state=new_state,
                chain_id=env.value.chain_id,
                excess_blob_gas=env.value.excess_blob_gas,
                blob_versioned_hashes=env.value.blob_versioned_hashes,
                transient_storage=env.value.transient_storage,
            ),
        );
        return ();
    }

    func set_transient_storage{env: Environment}(new_transient_storage: TransientStorage) {
        tempvar env = Environment(
            new EnvironmentStruct(
                caller=env.value.caller,
                block_hashes=env.value.block_hashes,
                origin=env.value.origin,
                coinbase=env.value.coinbase,
                number=env.value.number,
                base_fee_per_gas=env.value.base_fee_per_gas,
                gas_limit=env.value.gas_limit,
                gas_price=env.value.gas_price,
                time=env.value.time,
                prev_randao=env.value.prev_randao,
                state=env.value.state,
                chain_id=env.value.chain_id,
                excess_blob_gas=env.value.excess_blob_gas,
                blob_versioned_hashes=env.value.blob_versioned_hashes,
                transient_storage=new_transient_storage,
            ),
        );
        return ();
    }
}
