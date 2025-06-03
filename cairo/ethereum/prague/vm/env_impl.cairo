from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

from ethereum.prague.fork_types import (
    SetAddress,
    SetTupleAddressBytes32,
    Address,
    ListHash32__hash__,
    ListHash32,
    TupleVersionedHash,
    TupleAuthorization
)
from ethereum_types.numeric import OptionalUint, U256, U64, Uint
from ethereum_types.bytes import Bytes32, OptionalHash32
from ethereum.prague.state import State, TransientStorage
from cairo_core.bytes_impl import Bytes32__hash__
from ethereum.crypto.hash import Hash32
from starkware.cairo.common.alloc import alloc

from cairo_core.hash.blake2s import blake2s_add_uint256, blake2s, blake2s_add_felt

from mpt.hash_diff import hash_state_account_diff, hash_state_storage_diff

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

func BlockEnv__hash__{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    block_env: BlockEnvironment
) -> Hash32 {
    alloc_locals;
    let (block_env_commitment_inputs) = alloc();
    let start_block_env_commitment = block_env_commitment_inputs;
    blake2s_add_felt{data=block_env_commitment_inputs}(block_env.value.chain_id.value, bigend=0);

    // Commit to the state. Expects the input state to be finalized.
    let state = block_env.value.state;
    let state_account_diff = hash_state_account_diff(state);
    let state_storage_diff = hash_state_storage_diff(state);
    let (state_commitment_inputs) = alloc();
    let start_state_commitment = state_commitment_inputs;
    blake2s_add_felt{data=state_commitment_inputs}(state_account_diff, bigend=0);
    blake2s_add_felt{data=state_commitment_inputs}(state_storage_diff, bigend=0);
    let (state_commitment) = blake2s(data=start_state_commitment, n_bytes=64);

    blake2s_add_uint256{data=block_env_commitment_inputs}(state_commitment);
    blake2s_add_felt{data=block_env_commitment_inputs}(
        block_env.value.block_gas_limit.value, bigend=0
    );

    let block_hashes_commitment = ListHash32__hash__(block_env.value.block_hashes);
    blake2s_add_uint256{data=block_env_commitment_inputs}([block_hashes_commitment.value]);

    blake2s_add_felt{data=block_env_commitment_inputs}(block_env.value.coinbase.value, bigend=0);
    blake2s_add_felt{data=block_env_commitment_inputs}(block_env.value.number.value, bigend=0);
    blake2s_add_felt{data=block_env_commitment_inputs}(
        block_env.value.base_fee_per_gas.value, bigend=0
    );
    blake2s_add_uint256{data=block_env_commitment_inputs}([block_env.value.time.value]);

    let prev_randao_commitment = Bytes32__hash__(block_env.value.prev_randao);
    blake2s_add_uint256{data=block_env_commitment_inputs}([prev_randao_commitment.value]);
    blake2s_add_felt{data=block_env_commitment_inputs}(
        block_env.value.excess_blob_gas.value, bigend=0
    );

    let parent_beacon_block_root_commitment = Bytes32__hash__(
        block_env.value.parent_beacon_block_root
    );
    blake2s_add_uint256{data=block_env_commitment_inputs}([parent_beacon_block_root_commitment.value]);

    let (block_env_commitment) = blake2s(
        data=start_block_env_commitment, n_bytes=BlockEnvironmentStruct.SIZE * 32
    );

    tempvar res = Hash32(new block_env_commitment);
    return res;
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
    authorizations: TupleAuthorization,
    index_in_block: OptionalUint,
    tx_hash: OptionalHash32,
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
                authorizations=tx_env.value.authorizations,
                index_in_block=tx_env.value.index_in_block,
                tx_hash=tx_env.value.tx_hash,
            ),
        );
        return ();
    }

    func set_access_list_addresses{tx_env: TransactionEnvironment}(
        new_access_list_addresses: SetAddress
    ) {
        tempvar tx_env = TransactionEnvironment(
            new TransactionEnvironmentStruct(
                origin=tx_env.value.origin,
                gas_price=tx_env.value.gas_price,
                gas=tx_env.value.gas,
                access_list_addresses=new_access_list_addresses,
                access_list_storage_keys=tx_env.value.access_list_storage_keys,
                transient_storage=tx_env.value.transient_storage,
                blob_versioned_hashes=tx_env.value.blob_versioned_hashes,
                authorizations=tx_env.value.authorizations,
                index_in_block=tx_env.value.index_in_block,
                tx_hash=tx_env.value.tx_hash,
            ),
        );
        return ();
    }
}
