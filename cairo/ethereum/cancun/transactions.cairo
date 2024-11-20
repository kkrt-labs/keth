from ethereum.base_types import Bytes, Bytes0, Uint, U256, TupleBytes32, U64
from ethereum.cancun.fork_types import Address, TupleVersionedHash

const TX_BASE_COST = 21000;
const TX_DATA_COST_PER_NON_ZERO = 16;
const TX_DATA_COST_PER_ZERO = 4;
const TX_CREATE_COST = 32000;
const TX_ACCESS_LIST_ADDRESS_COST = 2400;
const TX_ACCESS_LIST_STORAGE_KEY_COST = 1900;

struct ToStruct {
    bytes0: Bytes0*,
    address: Address*,
}

struct To {
    value: ToStruct*,
}

struct LegacyTransactionStruct {
    nonce: U256,
    gas_price: Uint,
    gas: Uint,
    to: To,
    value: U256,
    data: Bytes,
    v: U256,
    r: U256,
    s: U256,
}

struct LegacyTransaction {
    value: LegacyTransactionStruct*,
}

struct AccessListStruct {
    address: Address,
    storage_keys: TupleBytes32,
}

struct AccessList {
    value: AccessListStruct*,
}

struct TupleAccessListStruct {
    value: AccessList*,
    len: felt,
}

struct TupleAccessList {
    value: TupleAccessListStruct*,
}

struct AccessListTransactionStruct {
    chain_id: U64,
    nonce: U256,
    gas_price: Uint,
    gas: Uint,
    to: To,
    value: U256,
    data: Bytes,
    access_list: TupleAccessList,
    y_parity: U256,
    r: U256,
    s: U256,
}

struct AccessListTransaction {
    value: AccessListTransactionStruct*,
}

struct FeeMarketTransactionStruct {
    chain_id: U64,
    nonce: U256,
    max_priority_fee_per_gas: Uint,
    max_fee_per_gas: Uint,
    gas: Uint,
    to: To,
    value: U256,
    data: Bytes,
    access_list: TupleAccessList,
    y_parity: U256,
    r: U256,
    s: U256,
}

struct FeeMarketTransaction {
    value: FeeMarketTransactionStruct*,
}

struct BlobTransactionStruct {
    chain_id: U64,
    nonce: U256,
    max_priority_fee_per_gas: Uint,
    max_fee_per_gas: Uint,
    gas: Uint,
    to: Address,
    value: U256,
    data: Bytes,
    access_list: TupleAccessList,
    max_fee_per_blob_gas: U256,
    blob_versioned_hashes: TupleVersionedHash,
    y_parity: U256,
    r: U256,
    s: U256,
}

struct BlobTransaction {
    value: BlobTransactionStruct*,
}

struct TransactionStruct {
    legacy_transaction: LegacyTransaction,
    access_list_transaction: AccessListTransaction,
    fee_market_transaction: FeeMarketTransaction,
    blob_transaction: BlobTransaction,
}

struct Transaction {
    value: TransactionStruct*,
}
