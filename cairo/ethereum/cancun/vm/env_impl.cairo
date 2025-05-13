from ethereum.cancun.fork_types import SetAddress, SetTupleAddressBytes32, Address, ListHash32
from ethereum_types.numeric import U256, U64, Uint, bool
from ethereum_types.bytes import Bytes32
from ethereum.cancun.state import State, TransientStorage
from ethereum.cancun.fork_types import TupleVersionedHash
from ethereum.crypto.hash import Hash32

struct BlockEnvironmentStruct {
    chain_id: U64,
    state: State,
    block_gas_limit: Uint,
    block_hashes: ListHash32,
    coinbase: Address,
    number: Uint,
    base_fee_per_gas: Uint,
    time: U256,
    prev_randao: Bytes32,
    excess_blob_gas: U64,
    parent_beacon_block_root: Hash32,
}

struct BlockEnvironment {
    value: BlockEnvironmentStruct*,
}

struct TransactionEnvironment {
    value: TransactionEnvironmentStruct*,
}

struct TransactionEnvironmentStruct {
    origin: Address,
    gas_price: Uint,
    gas: Uint,
    access_list_addresses: SetAddress,
    access_list_storage_keys: SetTupleAddressBytes32,
    transient_storage: TransientStorage,
    blob_versioned_hashes: TupleVersionedHash,
    has_index_in_block: bool,
    index_in_block: Uint,
    has_tx_hash: bool,
    tx_hash: Hash32,
}

namespace BlockEnvImpl {
    func set_state{block_env: BlockEnvironment}(new_state: State) {
        tempvar block_env = BlockEnvironment(
            new BlockEnvironmentStruct(
                chain_id=block_env.value.chain_id,
                state=new_state,
                block_gas_limit=block_env.value.block_gas_limit,
                block_hashes=block_env.value.block_hashes,
                coinbase=block_env.value.coinbase,
                number=block_env.value.number,
                base_fee_per_gas=block_env.value.base_fee_per_gas,
                time=block_env.value.time,
                prev_randao=block_env.value.prev_randao,
                excess_blob_gas=block_env.value.excess_blob_gas,
                parent_beacon_block_root=block_env.value.parent_beacon_block_root,
            ),
        );
        return ();
    }
}

namespace TransactionEnvImpl {
    func set_transient_storage{tx_env: TransactionEnvironment}(
        new_transient_storage: TransientStorage
    ) {
        tempvar tx_env = TransactionEnvironment(
            new TransactionEnvironmentStruct(
                origin=tx_env.value.origin,
                gas_price=tx_env.value.gas_price,
                gas=tx_env.value.gas,
                access_list_addresses=tx_env.value.access_list_addresses,
                access_list_storage_keys=tx_env.value.access_list_storage_keys,
                transient_storage=new_transient_storage,
                blob_versioned_hashes=tx_env.value.blob_versioned_hashes,
                has_index_in_block=tx_env.value.has_index_in_block,
                index_in_block=tx_env.value.index_in_block,
                has_tx_hash=tx_env.value.has_tx_hash,
                tx_hash=tx_env.value.tx_hash,
            ),
        );
        return ();
    }
}
