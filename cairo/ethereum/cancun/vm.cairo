from ethereum.cancun.blocks import Log, TupleLog
from ethereum.cancun.fork_types import (
    Address,
    ListHash32,
    SetAddress,
    TupleAddressBytes32,
    SetTupleAddressBytes32,
    TupleVersionedHash,
    VersionedHash,
)
from ethereum.cancun.state import State, TransientStorage
from ethereum.exceptions import EthereumException
from ethereum_types.bytes import Bytes, Bytes0, Bytes32
from ethereum_types.numeric import U64, U256, Uint, bool, SetUint
from ethereum.cancun.transactions import To
from ethereum.cancun.vm.stack import Stack
from ethereum.cancun.vm.memory import Memory

using OptionalEthereumException = EthereumException;
using OptionalEvm = Evm;
using OptionalAddress = Address*;

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

struct Message {
    value: MessageStruct*,
}

struct EvmStruct {
    pc: Uint,
    stack: Stack,
    memory: Memory,
    code: Bytes,
    gas_left: Uint,
    env: Environment,
    valid_jump_destinations: SetUint,
    logs: TupleLog,
    refund_counter: felt,
    running: bool,
    message: Message,
    output: Bytes,
    accounts_to_delete: SetAddress,
    touched_accounts: SetAddress,
    return_data: Bytes,
    error: OptionalEthereumException,
    accessed_addresses: SetAddress,
    accessed_storage_keys: SetTupleAddressBytes32,
}

struct Evm {
    value: EvmStruct*,
}

struct MessageStruct {
    caller: Address,
    target: To,
    current_target: Address,
    gas: Uint,
    value: U256,
    data: Bytes,
    code_address: OptionalAddress,
    code: Bytes,
    depth: Uint,
    should_transfer_value: bool,
    is_static: bool,
    accessed_addresses: SetAddress,
    accessed_storage_keys: SetTupleAddressBytes32,
    parent_evm: OptionalEvm,
}
