from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.dict import DictAccess
from starkware.cairo.common.registers import get_fp_and_pc
from ethereum.cancun.blocks import TupleLog, TupleLogStruct, Receipt, Withdrawal
from ethereum.cancun.fork_types import (
    SetAddress,
    SetAddressStruct,
    SetAddressDictAccess,
    SetTupleAddressBytes32,
    SetTupleAddressBytes32Struct,
    SetTupleAddressBytes32DictAccess,
    Address,
    VersionedHash,
    ListHash32,
)
from ethereum_types.numeric import Uint, bool, SetUint, U256, U64
from ethereum.exceptions import EthereumException
from ethereum_types.bytes import Bytes, OptionalBytes, Bytes0, Bytes32
from ethereum.cancun.vm.stack import Stack
from ethereum.cancun.vm.memory import Memory
from ethereum.cancun.state import State, TransientStorage
from ethereum.cancun.fork_types import OptionalAddress, TupleVersionedHash
from ethereum.cancun.transactions_types import To, LegacyTransaction
from ethereum.cancun.trie import TrieBytesOptionalUnionBytesLegacyTransaction, TrieBytesOptionalUnionBytesReceipt, TrieBytesOptionalUnionBytesWithdrawal
from ethereum.crypto.hash import Hash32



// Define BlockEnvironment
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

// Define TransactionEnvironment
struct TransactionEnvironmentStruct {
    origin: Address,
    gas_price: Uint,
    gas: Uint,
    access_list_addresses: SetAddress,
    access_list_storage_keys: SetTupleAddressBytes32,
    transient_storage: TransientStorage,
    blob_versioned_hashes: TupleVersionedHash,
    index_in_block: Uint,
    tx_hash: Hash32,
}

struct TransactionEnvironment {
    value: TransactionEnvironmentStruct*,
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
    func set_transient_storage{tx_env: TransactionEnvironment}(new_transient_storage: TransientStorage) {
        tempvar tx_env = TransactionEnvironment(
            new TransactionEnvironmentStruct(
                origin=tx_env.value.origin,
                gas_price=tx_env.value.gas_price,
                gas=tx_env.value.gas,
                access_list_addresses=tx_env.value.access_list_addresses,
                access_list_storage_keys=tx_env.value.access_list_storage_keys,
                transient_storage=new_transient_storage,
                blob_versioned_hashes=tx_env.value.blob_versioned_hashes,
                index_in_block=tx_env.value.index_in_block,
                tx_hash=tx_env.value.tx_hash,
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
