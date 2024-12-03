from ethereum.base_types import BytesStruct, Bytes, Bytes0, Uint, U256, TupleBytes32, U64
from ethereum.cancun.fork_types import Address, TupleVersionedHash
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math_cmp import is_le
from ethereum.rlp import _encode_uint, _encode_bytes, _encode_uint256

from src.utils.bytes import felt_to_bytes_little, felt_to_bytes20_little
from starkware.cairo.common.memcpy import memcpy
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

func encode_legacy_transaction{range_check_ptr}(transaction: LegacyTransaction) -> Bytes {
    alloc_locals;
    let (local dst_start) = alloc();
    // Leave space for the length encoding
    let dst = dst_start + 10;
    let nonce_len = _encode_uint256(dst, transaction.value.nonce);
    let dst = dst + nonce_len;
    let gas_price_len = _encode_uint(dst, transaction.value.gas_price.value);
    let dst = dst + gas_price_len;
    let gas_len = _encode_uint(dst, transaction.value.gas.value);
    let dst = dst + gas_len;
    let to_len = _encode_to(dst, transaction.value.to);
    let dst = dst + to_len;
    let value_len = _encode_uint256(dst, transaction.value.value);
    let dst = dst + value_len;
    let data_len = _encode_bytes(dst, transaction.value.data);
    let dst = dst + data_len;
    let v_len = _encode_uint256(dst, transaction.value.v);
    let dst = dst + v_len;
    let r_len = _encode_uint256(dst, transaction.value.r);
    let dst = dst + r_len;
    let s_len = _encode_uint256(dst, transaction.value.s);
    let dst = dst + s_len;

    let len = dst - dst_start - 10;
    let cond = is_le(len, 0x38 - 1);
    let dst = dst_start + 9;
    if (cond != 0) {
        assert [dst] = 0xC0 + len;
        tempvar result = Bytes(new BytesStruct(dst, 1 + len));
        return result;
    }

    let (len_joined_encodings_as_le: felt*) = alloc();
    let len_joined_encodings_as_le_len = felt_to_bytes_little(len_joined_encodings_as_le, len);

    // Write the length encoding
    // Length encoding is 1 byte for the prefix and then the length in little endian
    let dst = dst - len_joined_encodings_as_le_len;
    assert [dst] = 0xF7 + len_joined_encodings_as_le_len;
    // Copy the length encoding
    memcpy(dst + 1, len_joined_encodings_as_le, len_joined_encodings_as_le_len);

    tempvar result = Bytes(new BytesStruct(dst, 1 + len_joined_encodings_as_le_len + len));
    return result;
}

func encode_to{range_check_ptr}(to: To) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode_to(dst, to);
    tempvar result = Bytes(new BytesStruct(dst, len));
    return result;
}

func _encode_to{range_check_ptr}(dst: felt*, to: To) -> felt {
    if (cast(to.value.address, felt) != 0) {
        // Encoding a 20 bytes address is encoding 20 bytes, so we know the prefix is 0x80
        assert [dst] = 0x80 + 20;
        felt_to_bytes20_little(dst + 1, to.value.address.value);
        return 21;
    }

    assert [dst] = 0x80;
    return 1;
}
