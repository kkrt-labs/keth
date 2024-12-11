from ethereum_types.numeric import U64, U256, Uint, bool
from ethereum_types.bytes import Bytes, Bytes8, Bytes32, TupleBytes, TupleBytes32
from ethereum.cancun.fork_types import Address, Bloom, Root
from ethereum.crypto.hash import Hash32

struct WithdrawalStruct {
    index: U64,
    validator_index: U64,
    address: Address,
    amount: U256,
}

struct Withdrawal {
    value: WithdrawalStruct*,
}

struct TupleWithdrawalStruct {
    data: Withdrawal*,
    len: felt,
}

struct TupleWithdrawal {
    value: TupleWithdrawalStruct*,
}

struct HeaderStruct {
    parent_hash: Hash32,
    ommers_hash: Hash32,
    coinbase: Address,
    state_root: Root,
    transactions_root: Root,
    receipt_root: Root,
    bloom: Bloom,
    difficulty: Uint,
    number: Uint,
    gas_limit: Uint,
    gas_used: Uint,
    timestamp: U256,
    extra_data: Bytes,
    prev_randao: Bytes32,
    nonce: Bytes8,
    base_fee_per_gas: Uint,
    withdrawals_root: Root,
    blob_gas_used: U64,
    excess_blob_gas: U64,
    parent_beacon_block_root: Root,
}

struct Header {
    value: HeaderStruct*,
}

struct TupleHeaderStruct {
    data: Header*,
    len: felt,
}

struct TupleHeader {
    value: TupleHeaderStruct*,
}

struct LogStruct {
    address: Address,
    topics: TupleBytes32,
    data: Bytes,
}

struct Log {
    value: LogStruct*,
}

struct TupleLogStruct {
    data: Log*,
    len: felt,
}

struct TupleLog {
    value: TupleLogStruct*,
}

struct ReceiptStruct {
    succeeded: bool,
    cumulative_gas_used: Uint,
    bloom: Bloom,
    logs: TupleLog,
}

struct Receipt {
    value: ReceiptStruct*,
}
