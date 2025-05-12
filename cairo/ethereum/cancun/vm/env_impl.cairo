from ethereum_types.bytes import Bytes32, TupleBytes
from ethereum_types.numeric import Uint, U256, U64, bool
from ethereum.cancun.blocks import TupleLog
from ethereum.cancun.fork_types import (
    Address,
    ListHash32,
    TupleVersionedHash,
    SetAddress,
    SetTupleAddressBytes32,
)
from ethereum.cancun.state import State, TransientStorage
from ethereum.crypto.hash import Hash32
from ethereum.cancun.trie import (
    TrieBytesOptionalUnionBytesLegacyTransaction,
    TrieBytesOptionalUnionBytesReceipt,
    TrieBytesOptionalUnionBytesWithdrawal,
)

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

struct BlockOutputStruct {
    block_gas_used: Uint,
    transactions_trie: TrieBytesOptionalUnionBytesLegacyTransaction,
    receipts_trie: TrieBytesOptionalUnionBytesReceipt,
    receipt_keys: TupleBytes,
    block_logs: TupleLog,
    withdrawals_trie: TrieBytesOptionalUnionBytesWithdrawal,
    blob_gas_used: U64,
}

struct BlockOutput {
    value: BlockOutputStruct*,
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

struct TransactionEnvironment {
    value: TransactionEnvironmentStruct*,
}
