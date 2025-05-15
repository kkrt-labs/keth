from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.alloc import alloc

from ethereum_types.bytes import Bytes, Bytes0, TupleBytes32, BytesStruct
from ethereum_types.numeric import U256, U64, Uint
from ethereum.cancun.fork_types import Address, TupleVersionedHash
from ethereum.crypto.hash import Hash32
from ethereum.utils.numeric import U256__hash__, Uint__hash__
from cairo_core.control_flow import raise
from cairo_core.bytes_impl import Bytes__hash__, Bytes20__hash__
from cairo_core.hash.blake2s import blake2s_add_uint256, blake2s

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

func To__hash__{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(self: To) -> Hash32 {
    if (cast(self.value.bytes0, felt) != 0) {
        // hash of empty bytes
        // TODO: return a constant here instead
        tempvar bytes_input = Bytes(new BytesStruct(data=cast(0, felt*), len=0));
        let res = Bytes__hash__(bytes_input);
        return res;
    }

    return Bytes20__hash__([self.value.address]);
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

func LegacyTransaction__hash__{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    self: LegacyTransaction
) -> Hash32 {
    alloc_locals;
    let nonce_hash = U256__hash__(self.value.nonce);
    let gas_price_hash = Uint__hash__(self.value.gas_price);
    let gas_hash = Uint__hash__(self.value.gas);
    let to_hash = To__hash__(self.value.to);
    let value_hash = U256__hash__(self.value.value);
    let data_hash = Bytes__hash__(self.value.data);
    let v_hash = U256__hash__(self.value.v);
    let r_hash = U256__hash__(self.value.r);
    let s_hash = U256__hash__(self.value.s);

    let (local buffer) = alloc();
    let buffer_start = buffer;
    blake2s_add_uint256{data=buffer}([nonce_hash.value]);
    blake2s_add_uint256{data=buffer}([gas_price_hash.value]);
    blake2s_add_uint256{data=buffer}([gas_hash.value]);
    blake2s_add_uint256{data=buffer}([to_hash.value]);
    blake2s_add_uint256{data=buffer}([value_hash.value]);
    blake2s_add_uint256{data=buffer}([data_hash.value]);
    blake2s_add_uint256{data=buffer}([v_hash.value]);
    blake2s_add_uint256{data=buffer}([r_hash.value]);
    blake2s_add_uint256{data=buffer}([s_hash.value]);
    let n_bytes = 32 * LegacyTransactionStruct.SIZE;

    let (res_u256) = blake2s(data=buffer_start, n_bytes=n_bytes);
    tempvar hash = Hash32(value=new res_u256);
    return hash;
}

struct AccessStruct {
    account: Address,
    slots: TupleBytes32,
}

struct Access {
    value: AccessStruct*,
}

struct TupleAccessStruct {
    data: Access*,
    len: felt,
}

struct TupleAccess {
    value: TupleAccessStruct*,
}

struct AccessListTransactionStruct {
    chain_id: U64,
    nonce: U256,
    gas_price: Uint,
    gas: Uint,
    to: To,
    value: U256,
    data: Bytes,
    access_list: TupleAccess,
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
    access_list: TupleAccess,
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
    access_list: TupleAccess,
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

namespace TransactionType {
    const LEGACY = 0;
    const ACCESS_LIST = 1;
    const FEE_MARKET = 2;
    const BLOB = 3;
}

func get_transaction_type(tx: Transaction) -> felt {
    if (cast(tx.value.legacy_transaction.value, felt) != 0) {
        return TransactionType.LEGACY;
    }
    if (cast(tx.value.access_list_transaction.value, felt) != 0) {
        return TransactionType.ACCESS_LIST;
    }
    if (cast(tx.value.fee_market_transaction.value, felt) != 0) {
        return TransactionType.FEE_MARKET;
    }
    if (cast(tx.value.blob_transaction.value, felt) != 0) {
        return TransactionType.BLOB;
    }
    with_attr error_message("InvalidTransaction") {
        jmp raise.raise_label;
    }
}

func get_gas(tx: Transaction) -> Uint {
    let tx_type = get_transaction_type(tx);
    if (tx_type == TransactionType.LEGACY) {
        return tx.value.legacy_transaction.value.gas;
    }
    if (tx_type == TransactionType.ACCESS_LIST) {
        return tx.value.access_list_transaction.value.gas;
    }
    if (tx_type == TransactionType.FEE_MARKET) {
        return tx.value.fee_market_transaction.value.gas;
    }
    if (tx_type == TransactionType.BLOB) {
        return tx.value.blob_transaction.value.gas;
    }
    with_attr error_message("InvalidTransaction") {
        jmp raise.raise_label;
    }
}

func get_r(tx: Transaction) -> U256 {
    let tx_type = get_transaction_type(tx);
    if (tx_type == TransactionType.LEGACY) {
        return tx.value.legacy_transaction.value.r;
    }
    if (tx_type == TransactionType.ACCESS_LIST) {
        return tx.value.access_list_transaction.value.r;
    }
    if (tx_type == TransactionType.FEE_MARKET) {
        return tx.value.fee_market_transaction.value.r;
    }
    if (tx_type == TransactionType.BLOB) {
        return tx.value.blob_transaction.value.r;
    }
    with_attr error_message("InvalidTransaction") {
        jmp raise.raise_label;
    }
}

func get_s(tx: Transaction) -> U256 {
    let tx_type = get_transaction_type(tx);
    if (tx_type == TransactionType.LEGACY) {
        return tx.value.legacy_transaction.value.s;
    }
    if (tx_type == TransactionType.ACCESS_LIST) {
        return tx.value.access_list_transaction.value.s;
    }
    if (tx_type == TransactionType.FEE_MARKET) {
        return tx.value.fee_market_transaction.value.s;
    }
    if (tx_type == TransactionType.BLOB) {
        return tx.value.blob_transaction.value.s;
    }
    with_attr error_message("InvalidTransaction") {
        jmp raise.raise_label;
    }
}

func get_to(tx: Transaction) -> To {
    let tx_type = get_transaction_type(tx);
    if (tx_type == TransactionType.LEGACY) {
        return tx.value.legacy_transaction.value.to;
    }
    if (tx_type == TransactionType.ACCESS_LIST) {
        return tx.value.access_list_transaction.value.to;
    }
    if (tx_type == TransactionType.FEE_MARKET) {
        return tx.value.fee_market_transaction.value.to;
    }
    if (tx_type == TransactionType.BLOB) {
        let bytes20_value = tx.value.blob_transaction.value.to;
        tempvar to = To(value=new ToStruct(bytes0=cast(0, Bytes0*), address=new bytes20_value));
        return to;
    }
    with_attr error_message("InvalidTransaction") {
        jmp raise.raise_label;
    }
}

func get_data(tx: Transaction) -> Bytes {
    let tx_type = get_transaction_type(tx);
    if (tx_type == TransactionType.LEGACY) {
        return tx.value.legacy_transaction.value.data;
    }
    if (tx_type == TransactionType.ACCESS_LIST) {
        return tx.value.access_list_transaction.value.data;
    }
    if (tx_type == TransactionType.FEE_MARKET) {
        return tx.value.fee_market_transaction.value.data;
    }
    if (tx_type == TransactionType.BLOB) {
        return tx.value.blob_transaction.value.data;
    }
    with_attr error_message("InvalidTransaction") {
        jmp raise.raise_label;
    }
}

func get_max_fee_per_gas(tx: Transaction) -> Uint {
    let tx_type = get_transaction_type(tx);
    if (tx_type == TransactionType.FEE_MARKET) {
        return tx.value.fee_market_transaction.value.max_fee_per_gas;
    }
    if (tx_type == TransactionType.BLOB) {
        return tx.value.blob_transaction.value.max_fee_per_gas;
    }
    with_attr error_message("InvalidTransaction") {
        jmp raise.raise_label;
    }
}

func get_max_priority_fee_per_gas(tx: Transaction) -> Uint {
    let tx_type = get_transaction_type(tx);
    if (tx_type == TransactionType.FEE_MARKET) {
        return tx.value.fee_market_transaction.value.max_priority_fee_per_gas;
    }
    if (tx_type == TransactionType.BLOB) {
        return tx.value.blob_transaction.value.max_priority_fee_per_gas;
    }
    with_attr error_message("InvalidTransaction") {
        jmp raise.raise_label;
    }
}

func get_gas_price(tx: Transaction) -> Uint {
    let tx_type = get_transaction_type(tx);
    if (tx_type == TransactionType.LEGACY) {
        return tx.value.legacy_transaction.value.gas_price;
    }
    if (tx_type == TransactionType.ACCESS_LIST) {
        return tx.value.access_list_transaction.value.gas_price;
    }
    with_attr error_message("InvalidTransaction") {
        jmp raise.raise_label;
    }
}

func get_nonce(tx: Transaction) -> U256 {
    let tx_type = get_transaction_type(tx);
    if (tx_type == TransactionType.LEGACY) {
        return tx.value.legacy_transaction.value.nonce;
    }
    if (tx_type == TransactionType.ACCESS_LIST) {
        return tx.value.access_list_transaction.value.nonce;
    }
    if (tx_type == TransactionType.FEE_MARKET) {
        return tx.value.fee_market_transaction.value.nonce;
    }
    if (tx_type == TransactionType.BLOB) {
        return tx.value.blob_transaction.value.nonce;
    }
    with_attr error_message("InvalidTransaction") {
        jmp raise.raise_label;
    }
}

func get_value(tx: Transaction) -> U256 {
    let tx_type = get_transaction_type(tx);
    if (tx_type == TransactionType.LEGACY) {
        return tx.value.legacy_transaction.value.value;
    }
    if (tx_type == TransactionType.ACCESS_LIST) {
        return tx.value.access_list_transaction.value.value;
    }
    if (tx_type == TransactionType.FEE_MARKET) {
        return tx.value.fee_market_transaction.value.value;
    }
    if (tx_type == TransactionType.BLOB) {
        return tx.value.blob_transaction.value.value;
    }
    with_attr error_message("InvalidTransaction") {
        jmp raise.raise_label;
    }
}
