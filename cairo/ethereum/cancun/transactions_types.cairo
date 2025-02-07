from ethereum_types.bytes import Bytes, Bytes0, TupleBytes32
from ethereum_types.numeric import Uint, U256, U64, bool, U256Struct
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
    data: AccessList*,
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
        assert 0 = 1;
        return 0;
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
        assert 0 = 1;
        let res = Uint(0);
        return res;
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
        assert 0 = 1;
        tempvar res = U256(new U256Struct(0, 0));
        return res;
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
        assert 0 = 1;
        tempvar res = U256(new U256Struct(0, 0));
        return res;
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
        assert 0 = 1;
        let res = Uint(0);
        return res;
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
        assert 0 = 1;
        let res = Uint(0);
        return res;
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
        assert 0 = 1;
        let res = Uint(0);
        return res;
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
        assert 0 = 1;
        tempvar res = U256(new U256Struct(0, 0));
        return res;
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
        assert 0 = 1;
        tempvar res = U256(new U256Struct(0, 0));
        return res;
namespace TransactionImpl {
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
            assert 0 = 1;
            ret;
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
            assert 0 = 1;
            ret;
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
            assert 0 = 1;
            ret;
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
            assert 0 = 1;
            ret;
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
            assert 0 = 1;
            ret;
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
            assert 0 = 1;
            ret;
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
            assert 0 = 1;
            ret;
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
            assert 0 = 1;
            ret;
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
            assert 0 = 1;
            ret;
        }
    }
}
