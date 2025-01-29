from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.math_cmp import is_le, is_not_zero
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.memcpy import memcpy

from ethereum_types.numeric import Bool, U256, Uint, U64
from ethereum_types.bytes import (
    Bytes,
    BytesStruct,
    Bytes32,
    TupleBytes,
    String,
    StringStruct,
    TupleBytes32,
    TupleBytes32Struct,
)
from ethereum.cancun.blocks import Log, TupleLog, Receipt, Withdrawal
from ethereum.cancun.fork_types import Address, Account, Bloom
from ethereum.cancun.transactions import (
    LegacyTransaction,
    To,
    AccessList,
    AccessListStruct,
    TupleAccessList,
    AccessListTransaction,
    FeeMarketTransaction,
    BlobTransaction,
    Transaction,
)
from ethereum.crypto.hash import keccak256, Hash32
from ethereum.utils.numeric import is_zero
from src.utils.array import reverse
from src.utils.bytes import (
    felt_to_bytes,
    felt_to_bytes_little,
    bytes_to_felt,
    uint256_to_bytes32_little,
    felt_to_bytes20_little,
    uint256_to_bytes_little,
    uint256_to_bytes,
    felt_to_bytes16_little,
)

struct SequenceSimple {
    value: SequenceSimpleStruct*,
}

struct SequenceSimpleStruct {
    data: Simple*,
    len: felt,
}

struct Simple {
    value: SimpleEnum*,
}

struct SimpleEnum {
    sequence: SequenceSimple,
    bytes: Bytes,
}

struct SequenceExtended {
    value: SequenceExtendedStruct*,
}

struct SequenceExtendedStruct {
    data: Extended*,
    len: felt,
}

struct Extended {
    value: ExtendedEnum*,
}

struct ExtendedEnum {
    sequence: SequenceExtended,
    bytearray: Bytes,
    bytes: Bytes,
    uint: Uint*,
    fixed_uint: Uint*,
    str: String,
    bool: Bool*,
}

namespace ExtendedImpl {
    func sequence(value: SequenceExtended) -> Extended {
        tempvar extended = Extended(
            new ExtendedEnum(
                sequence=value,
                bytearray=Bytes(cast(0, BytesStruct*)),
                bytes=Bytes(cast(0, BytesStruct*)),
                uint=cast(0, Uint*),
                fixed_uint=cast(0, Uint*),
                str=String(cast(0, StringStruct*)),
                bool=cast(0, Bool*),
            ),
        );
        return extended;
    }

    func bytearray(value: Bytes) -> Extended {
        tempvar extended = Extended(
            new ExtendedEnum(
                sequence=SequenceExtended(cast(0, SequenceExtendedStruct*)),
                bytearray=value,
                bytes=Bytes(cast(0, BytesStruct*)),
                uint=cast(0, Uint*),
                fixed_uint=cast(0, Uint*),
                str=String(cast(0, StringStruct*)),
                bool=cast(0, Bool*),
            ),
        );
        return extended;
    }

    func bytes(value: Bytes) -> Extended {
        tempvar extended = Extended(
            new ExtendedEnum(
                sequence=SequenceExtended(cast(0, SequenceExtendedStruct*)),
                bytearray=Bytes(cast(0, BytesStruct*)),
                bytes=value,
                uint=cast(0, Uint*),
                fixed_uint=cast(0, Uint*),
                str=String(cast(0, StringStruct*)),
                bool=cast(0, Bool*),
            ),
        );
        return extended;
    }

    func uint(value: Uint) -> Extended {
        tempvar extended = Extended(
            new ExtendedEnum(
                sequence=SequenceExtended(cast(0, SequenceExtendedStruct*)),
                bytearray=Bytes(cast(0, BytesStruct*)),
                bytes=Bytes(cast(0, BytesStruct*)),
                uint=value,
                fixed_uint=cast(0, Uint*),
                str=String(cast(0, StringStruct*)),
                bool=cast(0, Bool*),
            ),
        );
        return extended;
    }

    func fixed_uint(value: Uint) -> Extended {
        tempvar extended = Extended(
            new ExtendedEnum(
                sequence=SequenceExtended(cast(0, SequenceExtendedStruct*)),
                bytearray=Bytes(cast(0, BytesStruct*)),
                bytes=Bytes(cast(0, BytesStruct*)),
                uint=cast(0, Uint*),
                fixed_uint=value,
                str=String(cast(0, StringStruct*)),
                bool=cast(0, Bool*),
            ),
        );
        return extended;
    }

    func string(value: String) -> Extended {
        tempvar extended = Extended(
            new ExtendedEnum(
                sequence=SequenceExtended(cast(0, SequenceExtendedStruct*)),
                bytearray=Bytes(cast(0, BytesStruct*)),
                bytes=Bytes(cast(0, BytesStruct*)),
                uint=cast(0, Uint*),
                fixed_uint=cast(0, Uint*),
                str=value,
                bool=cast(0, Bool*),
            ),
        );
        return extended;
    }

    func bool(value: Bool*) -> Extended {
        tempvar extended = Extended(
            new ExtendedEnum(
                sequence=SequenceExtended(cast(0, SequenceExtendedStruct*)),
                bytearray=Bytes(cast(0, BytesStruct*)),
                bytes=Bytes(cast(0, BytesStruct*)),
                uint=cast(0, Uint*),
                fixed_uint=cast(0, Uint*),
                str=String(cast(0, StringStruct*)),
                bool=value,
            ),
        );
        return extended;
    }
}

//
// RLP Encode
//

// @dev The maximum prefix length for the RLP encoding is 9 bytes.
// @dev When possible, we start by offset the allocated buffer by 9 bytes to avoid
// @dev a memcpy in the end just for the prefix.
const PREFIX_LEN_MAX = 9;

func encode{range_check_ptr}(raw_data: Extended) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode(dst, raw_data);
    tempvar value = new BytesStruct(dst, len);
    let encoded_bytes = Bytes(value);
    return encoded_bytes;
}

func encode_uint{range_check_ptr}(raw_uint: Uint) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode_uint(dst, raw_uint.value);
    tempvar value = new BytesStruct(dst, len);
    let encoded_uint = Bytes(value);
    return encoded_uint;
}

func encode_u256{range_check_ptr}(raw_uint: U256) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode_u256(dst, raw_uint);
    tempvar value = new BytesStruct(dst, len);
    let encoded_uint = Bytes(value);
    return encoded_uint;
}

func encode_u256_little{range_check_ptr}(raw_uint: U256) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode_u256_little(dst, raw_uint);
    tempvar value = new BytesStruct(dst, len);
    let encoded_uint = Bytes(value);
    return encoded_uint;
}

func encode_bytes{range_check_ptr}(raw_bytes: Bytes) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode_bytes(dst, raw_bytes);
    tempvar value = new BytesStruct(dst, len);
    let encoded_bytes = Bytes(value);
    return encoded_bytes;
}

func encode_sequence{range_check_ptr}(raw_sequence: SequenceExtended) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode_sequence(dst, raw_sequence);
    tempvar value = new BytesStruct(dst, len);
    let encoded_bytes = Bytes(value);
    return encoded_bytes;
}

func join_encodings{range_check_ptr}(raw_sequence: SequenceExtended) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _get_joined_encodings(dst, raw_sequence.value.data, raw_sequence.value.len);
    tempvar value = new BytesStruct(dst, len);
    let encoded_bytes = Bytes(value);
    return encoded_bytes;
}

func encode_bytes32{range_check_ptr}(raw_bytes32: Bytes32) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode_bytes32(dst, raw_bytes32);
    tempvar value = Bytes(new BytesStruct(dst, len));
    return value;
}

func encode_tuple_bytes32{range_check_ptr}(raw_tuple_bytes32: TupleBytes32) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode_tuple_bytes32(dst, raw_tuple_bytes32);
    tempvar value = Bytes(new BytesStruct(dst, len));
    return value;
}

func encode_to{range_check_ptr}(to: To) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode_to(dst, to);
    tempvar result = Bytes(new BytesStruct(dst, len));
    return result;
}

func encode_address{range_check_ptr}(address: Address) -> Bytes {
    alloc_locals;
    let (dst) = alloc();
    let len = _encode_address(dst, address);
    tempvar result = Bytes(new BytesStruct(dst, len));
    return result;
}

func encode_account{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}(
    raw_account_data: Account, storage_root: Bytes
) -> Bytes {
    alloc_locals;
    let (local dst) = alloc();
    let body_ptr = dst + PREFIX_LEN_MAX;

    let nonce_len = _encode_uint(body_ptr, raw_account_data.value.nonce.value);
    let body_ptr = body_ptr + nonce_len;
    let balance_len = _encode_u256(body_ptr, raw_account_data.value.balance);
    let body_ptr = body_ptr + balance_len;
    let storage_root_len = _encode_bytes(body_ptr, storage_root);
    let body_ptr = body_ptr + storage_root_len;

    // Encoding the code hash is encoding 32 bytes, so we know the prefix is 0x80 + 32
    // code_hash_len is 33 bytes and we can directly copy the bytes into the buffer
    let code_hash = keccak256(raw_account_data.value.code);
    let code_hash_len = 32;
    assert [body_ptr] = 0x80 + code_hash_len;
    uint256_to_bytes32_little(body_ptr + 1, [code_hash.value]);
    let body_ptr = body_ptr + 1 + code_hash_len;

    let body_len = body_ptr - dst - PREFIX_LEN_MAX;
    let body_ptr = dst + PREFIX_LEN_MAX;
    let prefix_len = _encode_prefix_len(body_ptr, body_len);

    tempvar result = Bytes(new BytesStruct(body_ptr - prefix_len, prefix_len + body_len));
    return result;
}

func encode_legacy_transaction{range_check_ptr}(transaction: LegacyTransaction) -> Bytes {
    alloc_locals;
    let (local dst) = alloc();
    let body_ptr = dst + PREFIX_LEN_MAX;

    let nonce_len = _encode_u256(body_ptr, transaction.value.nonce);
    let body_ptr = body_ptr + nonce_len;
    let gas_price_len = _encode_uint(body_ptr, transaction.value.gas_price.value);
    let body_ptr = body_ptr + gas_price_len;
    let gas_len = _encode_uint(body_ptr, transaction.value.gas.value);
    let body_ptr = body_ptr + gas_len;
    let to_len = _encode_to(body_ptr, transaction.value.to);
    let body_ptr = body_ptr + to_len;
    let value_len = _encode_u256(body_ptr, transaction.value.value);
    let body_ptr = body_ptr + value_len;
    let data_len = _encode_bytes(body_ptr, transaction.value.data);
    let body_ptr = body_ptr + data_len;
    let v_len = _encode_u256(body_ptr, transaction.value.v);
    let body_ptr = body_ptr + v_len;
    let r_len = _encode_u256(body_ptr, transaction.value.r);
    let body_ptr = body_ptr + r_len;
    let s_len = _encode_u256(body_ptr, transaction.value.s);
    let body_ptr = body_ptr + s_len;

    let body_len = body_ptr - dst - PREFIX_LEN_MAX;
    let body_ptr = dst + PREFIX_LEN_MAX;
    let prefix_len = _encode_prefix_len(body_ptr, body_len);

    tempvar result = Bytes(new BytesStruct(body_ptr - prefix_len, prefix_len + body_len));
    return result;
}

func encode_log{range_check_ptr}(raw_log: Log) -> Bytes {
    alloc_locals;
    let (local dst) = alloc();
    let body_ptr = dst + PREFIX_LEN_MAX;

    let address_len = _encode_address(body_ptr, raw_log.value.address);
    let body_ptr = body_ptr + address_len;
    let topics_len = _encode_tuple_bytes32(body_ptr, raw_log.value.topics);
    let body_ptr = body_ptr + topics_len;
    let data_len = _encode_bytes(body_ptr, raw_log.value.data);
    let body_ptr = body_ptr + data_len;

    let body_len = body_ptr - dst - PREFIX_LEN_MAX;
    let body_ptr = dst + PREFIX_LEN_MAX;
    let prefix_len = _encode_prefix_len(body_ptr, body_len);

    tempvar result = Bytes(new BytesStruct(body_ptr - prefix_len, prefix_len + body_len));
    return result;
}

func encode_tuple_log{range_check_ptr}(raw_tuple_log: TupleLog) -> Bytes {
    alloc_locals;
    let (local dst) = alloc();
    let len = _encode_tuple_log(dst, raw_tuple_log);
    tempvar result = Bytes(new BytesStruct(dst, len));
    return result;
}

func encode_bloom{range_check_ptr}(raw_bloom: Bloom) -> Bytes {
    alloc_locals;
    let (local dst) = alloc();
    let len = _encode_bloom(dst, raw_bloom);
    tempvar result = Bytes(new BytesStruct(dst, len));
    return result;
}

func encode_receipt{range_check_ptr}(raw_receipt: Receipt) -> Bytes {
    alloc_locals;
    let (local dst) = alloc();
    let body_ptr = dst + PREFIX_LEN_MAX;

    let succeeded_len = _encode_uint(body_ptr, raw_receipt.value.succeeded.value);
    let body_ptr = body_ptr + succeeded_len;
    let cumulative_gas_used_len = _encode_uint(
        body_ptr, raw_receipt.value.cumulative_gas_used.value
    );
    let body_ptr = body_ptr + cumulative_gas_used_len;
    let bloom_len = _encode_bloom(body_ptr, raw_receipt.value.bloom);
    let body_ptr = body_ptr + bloom_len;
    let logs_len = _encode_tuple_log(body_ptr, raw_receipt.value.logs);
    let body_ptr = body_ptr + logs_len;

    let body_len = body_ptr - dst - PREFIX_LEN_MAX;
    let body_ptr = dst + PREFIX_LEN_MAX;
    let prefix_len = _encode_prefix_len(body_ptr, body_len);

    tempvar result = Bytes(new BytesStruct(body_ptr - prefix_len, prefix_len + body_len));
    return result;
}

func encode_withdrawal{range_check_ptr}(raw_withdrawal: Withdrawal) -> Bytes {
    alloc_locals;
    let (local dst) = alloc();
    let body_ptr = dst + PREFIX_LEN_MAX;

    let index_len = _encode_uint(body_ptr, raw_withdrawal.value.index.value);
    let body_ptr = body_ptr + index_len;
    let validator_index_len = _encode_uint(body_ptr, raw_withdrawal.value.validator_index.value);
    let body_ptr = body_ptr + validator_index_len;
    let address_len = _encode_address(body_ptr, raw_withdrawal.value.address);
    let body_ptr = body_ptr + address_len;
    let amount_len = _encode_u256(body_ptr, raw_withdrawal.value.amount);
    let body_ptr = body_ptr + amount_len;

    let body_len = body_ptr - dst - PREFIX_LEN_MAX;
    let body_ptr = dst + PREFIX_LEN_MAX;
    let prefix_len = _encode_prefix_len(body_ptr, body_len);

    tempvar result = Bytes(new BytesStruct(body_ptr - prefix_len, prefix_len + body_len));
    return result;
}

func encode_tuple_access_list{range_check_ptr}(raw_tuple_access_list: TupleAccessList) -> Bytes {
    alloc_locals;
    let (local dst) = alloc();
    let len = _encode_tuple_access_list(dst, raw_tuple_access_list);
    tempvar result = Bytes(new BytesStruct(dst, len));
    return result;
}

func encode_access_list{range_check_ptr}(raw_access_list: AccessList) -> Bytes {
    alloc_locals;
    let (local dst) = alloc();
    let body_ptr = dst + PREFIX_LEN_MAX;

    let address_len = _encode_address(body_ptr, raw_access_list.value.address);
    let body_ptr = body_ptr + address_len;
    let storage_keys_len = _encode_tuple_bytes32(body_ptr, raw_access_list.value.storage_keys);
    let body_ptr = body_ptr + storage_keys_len;

    let body_len = body_ptr - dst - PREFIX_LEN_MAX;
    let body_ptr = dst + PREFIX_LEN_MAX;
    let prefix_len = _encode_prefix_len(body_ptr, body_len);

    tempvar result = Bytes(new BytesStruct(body_ptr - prefix_len, prefix_len + body_len));
    return result;
}

func encode_access_list_transaction{range_check_ptr}(transaction: AccessListTransaction) -> Bytes {
    alloc_locals;
    let (local dst) = alloc();
    let body_ptr = dst + PREFIX_LEN_MAX;  // Leave space for prefix

    // Encode all fields as a sequence
    let chain_id_len = _encode_uint(body_ptr, transaction.value.chain_id.value);
    let body_ptr = body_ptr + chain_id_len;

    let nonce_len = _encode_u256(body_ptr, transaction.value.nonce);
    let body_ptr = body_ptr + nonce_len;

    let gas_price_len = _encode_uint(body_ptr, transaction.value.gas_price.value);
    let body_ptr = body_ptr + gas_price_len;

    let gas_len = _encode_uint(body_ptr, transaction.value.gas.value);
    let body_ptr = body_ptr + gas_len;

    let to_len = _encode_to(body_ptr, transaction.value.to);
    let body_ptr = body_ptr + to_len;

    let value_len = _encode_u256(body_ptr, transaction.value.value);
    let body_ptr = body_ptr + value_len;

    let data_len = _encode_bytes(body_ptr, transaction.value.data);
    let body_ptr = body_ptr + data_len;

    let access_list_len = _encode_tuple_access_list(body_ptr, transaction.value.access_list);
    let body_ptr = body_ptr + access_list_len;

    let y_parity_len = _encode_u256(body_ptr, transaction.value.y_parity);
    let body_ptr = body_ptr + y_parity_len;

    let r_len = _encode_u256(body_ptr, transaction.value.r);
    let body_ptr = body_ptr + r_len;

    let s_len = _encode_u256(body_ptr, transaction.value.s);
    let body_ptr = body_ptr + s_len;

    // Calculate body length and encode prefix
    let body_len = body_ptr - dst - PREFIX_LEN_MAX;
    let body_ptr = dst + PREFIX_LEN_MAX;
    let prefix_len = _encode_prefix_len(body_ptr, body_len);

    // Prepend type byte (0x01)
    assert [body_ptr - prefix_len - 1] = 0x01;

    tempvar result = Bytes(new BytesStruct(body_ptr - prefix_len - 1, prefix_len + body_len + 1));
    return result;
}

func encode_fee_market_transaction{range_check_ptr}(transaction: FeeMarketTransaction) -> Bytes {
    alloc_locals;
    let (local dst) = alloc();
    let body_ptr = dst + PREFIX_LEN_MAX;  // Leave space for prefix

    // Encode all fields as a sequence
    let chain_id_len = _encode_uint(body_ptr, transaction.value.chain_id.value);
    let body_ptr = body_ptr + chain_id_len;

    let nonce_len = _encode_u256(body_ptr, transaction.value.nonce);
    let body_ptr = body_ptr + nonce_len;

    let max_priority_fee_per_gas_len = _encode_uint(
        body_ptr, transaction.value.max_priority_fee_per_gas.value
    );
    let body_ptr = body_ptr + max_priority_fee_per_gas_len;

    let max_fee_per_gas_len = _encode_uint(body_ptr, transaction.value.max_fee_per_gas.value);
    let body_ptr = body_ptr + max_fee_per_gas_len;

    let gas_len = _encode_uint(body_ptr, transaction.value.gas.value);
    let body_ptr = body_ptr + gas_len;

    let to_len = _encode_to(body_ptr, transaction.value.to);
    let body_ptr = body_ptr + to_len;

    let value_len = _encode_u256(body_ptr, transaction.value.value);
    let body_ptr = body_ptr + value_len;

    let data_len = _encode_bytes(body_ptr, transaction.value.data);
    let body_ptr = body_ptr + data_len;

    let access_list_len = _encode_tuple_access_list(body_ptr, transaction.value.access_list);
    let body_ptr = body_ptr + access_list_len;

    let y_parity_len = _encode_u256(body_ptr, transaction.value.y_parity);
    let body_ptr = body_ptr + y_parity_len;

    let r_len = _encode_u256(body_ptr, transaction.value.r);
    let body_ptr = body_ptr + r_len;

    let s_len = _encode_u256(body_ptr, transaction.value.s);
    let body_ptr = body_ptr + s_len;

    // Calculate body length and encode prefix
    let body_len = body_ptr - dst - PREFIX_LEN_MAX;
    let body_ptr = dst + PREFIX_LEN_MAX;
    let prefix_len = _encode_prefix_len(body_ptr, body_len);

    // Prepend type byte (0x02)
    assert [body_ptr - prefix_len - 1] = 0x02;

    tempvar result = Bytes(new BytesStruct(body_ptr - prefix_len - 1, prefix_len + body_len + 1));
    return result;
}

func encode_blob_transaction{range_check_ptr}(transaction: BlobTransaction) -> Bytes {
    alloc_locals;
    let (local dst) = alloc();
    let body_ptr = dst + PREFIX_LEN_MAX;  // Leave space for prefix

    // Encode all fields as a sequence
    let chain_id_len = _encode_uint(body_ptr, transaction.value.chain_id.value);
    let body_ptr = body_ptr + chain_id_len;

    let nonce_len = _encode_u256(body_ptr, transaction.value.nonce);
    let body_ptr = body_ptr + nonce_len;

    let max_priority_fee_per_gas_len = _encode_uint(
        body_ptr, transaction.value.max_priority_fee_per_gas.value
    );
    let body_ptr = body_ptr + max_priority_fee_per_gas_len;

    let max_fee_per_gas_len = _encode_uint(body_ptr, transaction.value.max_fee_per_gas.value);
    let body_ptr = body_ptr + max_fee_per_gas_len;

    let gas_len = _encode_uint(body_ptr, transaction.value.gas.value);
    let body_ptr = body_ptr + gas_len;

    let to_len = _encode_address(body_ptr, transaction.value.to);  // Note: BlobTransaction uses Address not To
    let body_ptr = body_ptr + to_len;

    let value_len = _encode_u256(body_ptr, transaction.value.value);
    let body_ptr = body_ptr + value_len;

    let data_len = _encode_bytes(body_ptr, transaction.value.data);
    let body_ptr = body_ptr + data_len;

    let access_list_len = _encode_tuple_access_list(body_ptr, transaction.value.access_list);
    let body_ptr = body_ptr + access_list_len;

    let max_fee_per_blob_gas_len = _encode_u256(body_ptr, transaction.value.max_fee_per_blob_gas);
    let body_ptr = body_ptr + max_fee_per_blob_gas_len;

    // blob_versioned_hashes is TupleHash32 which is an alias for TupleBytes32
    tempvar _blob_versioned_hashes = TupleBytes32(
        cast(transaction.value.blob_versioned_hashes.value, TupleBytes32Struct*)
    );
    let blob_versioned_hashes_len = _encode_tuple_bytes32(body_ptr, _blob_versioned_hashes);
    let body_ptr = body_ptr + blob_versioned_hashes_len;

    let y_parity_len = _encode_u256(body_ptr, transaction.value.y_parity);
    let body_ptr = body_ptr + y_parity_len;

    let r_len = _encode_u256(body_ptr, transaction.value.r);
    let body_ptr = body_ptr + r_len;

    let s_len = _encode_u256(body_ptr, transaction.value.s);
    let body_ptr = body_ptr + s_len;

    // Calculate body length and encode prefix
    let body_len = body_ptr - dst - PREFIX_LEN_MAX;
    let body_ptr = dst + PREFIX_LEN_MAX;
    let prefix_len = _encode_prefix_len(body_ptr, body_len);

    // Prepend type byte (0x03)
    assert [body_ptr - prefix_len - 1] = 0x03;

    tempvar result = Bytes(new BytesStruct(body_ptr - prefix_len - 1, prefix_len + body_len + 1));
    return result;
}

func encode_eip155_transaction{range_check_ptr}(
    transaction: LegacyTransaction, chain_id: U64
) -> Bytes {
    alloc_locals;
    let (local dst) = alloc();
    let body_ptr = dst + PREFIX_LEN_MAX;  // Leave space for prefix

    // Encode all fields in order
    let nonce_len = _encode_u256(body_ptr, transaction.value.nonce);
    let body_ptr = body_ptr + nonce_len;

    let gas_price_len = _encode_uint(body_ptr, transaction.value.gas_price.value);
    let body_ptr = body_ptr + gas_price_len;

    let gas_len = _encode_uint(body_ptr, transaction.value.gas.value);
    let body_ptr = body_ptr + gas_len;

    let to_len = _encode_to(body_ptr, transaction.value.to);
    let body_ptr = body_ptr + to_len;

    let value_len = _encode_u256(body_ptr, transaction.value.value);
    let body_ptr = body_ptr + value_len;

    let data_len = _encode_bytes(body_ptr, transaction.value.data);
    let body_ptr = body_ptr + data_len;

    // EIP-155 specific fields
    let chain_id_len = _encode_uint(body_ptr, chain_id.value);
    let body_ptr = body_ptr + chain_id_len;

    let zero_len = _encode_uint(body_ptr, 0);
    let body_ptr = body_ptr + zero_len;

    let zero_len = _encode_uint(body_ptr, 0);
    let body_ptr = body_ptr + zero_len;

    // Calculate body length and encode prefix
    let body_len = body_ptr - dst - PREFIX_LEN_MAX;
    let body_ptr = dst + PREFIX_LEN_MAX;
    let prefix_len = _encode_prefix_len(body_ptr, body_len);

    tempvar result = Bytes(new BytesStruct(body_ptr - prefix_len, prefix_len + body_len));
    return result;
}

func encode_transaction{range_check_ptr}(transaction: Transaction) -> Bytes {
    alloc_locals;

    // Check which transaction type is non-null
    if (cast(transaction.value.legacy_transaction.value, felt) != 0) {
        // Legacy transaction - no type byte prefix
        return encode_legacy_transaction(transaction.value.legacy_transaction);
    }

    if (cast(transaction.value.access_list_transaction.value, felt) != 0) {
        // EIP-2930 transaction - type 0x01
        return encode_access_list_transaction(transaction.value.access_list_transaction);
    }

    if (cast(transaction.value.fee_market_transaction.value, felt) != 0) {
        // EIP-1559 transaction - type 0x02
        return encode_fee_market_transaction(transaction.value.fee_market_transaction);
    }

    if (cast(transaction.value.blob_transaction.value, felt) != 0) {
        // EIP-4844 transaction - type 0x03
        return encode_blob_transaction(transaction.value.blob_transaction);
    }

    // Should never happen - one pointer must be non-null
    with_attr error_message("Invalid transaction type - no valid pointer") {
        assert 0 = 1;
        tempvar result = Bytes(cast(0, BytesStruct*));
        return result;
    }
}

//
// RLP Decode
//

func decode{range_check_ptr}(encoded_data: Bytes) -> Simple {
    alloc_locals;
    assert [range_check_ptr] = encoded_data.value.len;
    let range_check_ptr = range_check_ptr + 1;
    assert_not_zero(encoded_data.value.len);

    let cond = is_le(encoded_data.value.data[0], 0xbf);
    if (cond != 0) {
        let decoded_data = decode_to_bytes(encoded_data);
        tempvar value = Simple(
            new SimpleEnum(
                sequence=SequenceSimple(cast(0, SequenceSimpleStruct*)), bytes=decoded_data
            ),
        );
        return value;
    }

    let decoded_sequence = decode_to_sequence(encoded_data);
    tempvar value = Simple(new SimpleEnum(sequence=decoded_sequence, Bytes(cast(0, BytesStruct*))));
    return value;
}

// @dev The reference function doesn't handle the case where encoded_bytes.len == 0
func decode_to_bytes{range_check_ptr}(encoded_bytes: Bytes) -> Bytes {
    alloc_locals;
    assert_not_zero(encoded_bytes.value.len);
    assert [range_check_ptr] = encoded_bytes.value.len;
    let range_check_ptr = range_check_ptr + 1;

    let cond = is_le(encoded_bytes.value.data[0], 0x80 - 1);
    if (encoded_bytes.value.len == 1 and cond != 0) {
        return encoded_bytes;
    }

    let cond = is_le(encoded_bytes.value.data[0], 0xB7);
    if (cond != 0) {
        let len_raw_data = encoded_bytes.value.data[0] - 0x80;
        assert [range_check_ptr] = len_raw_data;
        let range_check_ptr = range_check_ptr + 1;
        assert [range_check_ptr] = encoded_bytes.value.len - len_raw_data;
        let range_check_ptr = range_check_ptr + 1;
        let raw_data = encoded_bytes.value.data + 1;
        if (len_raw_data == 1) {
            assert [range_check_ptr] = raw_data[0] - 0x80;
            tempvar range_check_ptr = range_check_ptr + 1;
        } else {
            tempvar range_check_ptr = range_check_ptr;
        }
        let range_check_ptr = [ap - 1];
        tempvar value = new BytesStruct(raw_data, len_raw_data);
        let decoded_bytes = Bytes(value);
        return decoded_bytes;
    }

    let decoded_data_start_idx = 1 + encoded_bytes.value.data[0] - 0xB7;
    assert [range_check_ptr] = encoded_bytes.value.len - decoded_data_start_idx;
    let range_check_ptr = range_check_ptr + 1;
    assert_not_zero(encoded_bytes.value.data[1]);
    let len_decoded_data = bytes_to_felt(decoded_data_start_idx - 1, encoded_bytes.value.data + 1);
    assert [range_check_ptr] = len_decoded_data - 0x38;
    let range_check_ptr = range_check_ptr + 1;

    let decoded_data_end_idx = decoded_data_start_idx + len_decoded_data;
    assert [range_check_ptr] = encoded_bytes.value.len - decoded_data_end_idx;
    let range_check_ptr = range_check_ptr + 1;

    let raw_data = encoded_bytes.value.data + decoded_data_start_idx;
    tempvar value = new BytesStruct(raw_data, decoded_data_end_idx - decoded_data_start_idx);
    let decoded_bytes = Bytes(value);

    return decoded_bytes;
}

func decode_to_sequence{range_check_ptr}(encoded_sequence: Bytes) -> SequenceSimple {
    alloc_locals;

    let cond = is_le(encoded_sequence.value.data[0], 0xF7);
    if (cond == 1) {
        let len_joined_encodings = encoded_sequence.value.data[0] - 0xC0;
        assert [range_check_ptr] = len_joined_encodings;
        let range_check_ptr = range_check_ptr + 1;
        assert [range_check_ptr] = encoded_sequence.value.len - len_joined_encodings - 1;
        let range_check_ptr = range_check_ptr + 1;

        tempvar value = new BytesStruct(encoded_sequence.value.data + 1, len_joined_encodings);
        let joined_encodings = Bytes(value);
        return decode_joined_encodings(joined_encodings);
    }

    let joined_encodings_start_idx = 1 + encoded_sequence.value.data[0] - 0xF7;
    assert [range_check_ptr] = encoded_sequence.value.len - joined_encodings_start_idx;
    let range_check_ptr = range_check_ptr + 1;
    assert_not_zero(encoded_sequence.value.data[1]);

    let len_joined_encodings = bytes_to_felt(
        joined_encodings_start_idx - 1, encoded_sequence.value.data + 1
    );
    assert [range_check_ptr] = len_joined_encodings - 0x38;
    let range_check_ptr = range_check_ptr + 1;

    let joined_encodings_end_idx = joined_encodings_start_idx + len_joined_encodings;
    assert [range_check_ptr] = encoded_sequence.value.len - joined_encodings_end_idx;
    let range_check_ptr = range_check_ptr + 1;

    tempvar value = new BytesStruct(
        encoded_sequence.value.data + joined_encodings_start_idx,
        joined_encodings_end_idx - joined_encodings_start_idx,
    );
    let joined_encodings = Bytes(value);
    return decode_joined_encodings(joined_encodings);
}

func decode_joined_encodings{range_check_ptr}(joined_encodings: Bytes) -> SequenceSimple {
    alloc_locals;

    let (dst: Simple*) = alloc();
    let len = _decode_joined_encodings(dst, joined_encodings);
    tempvar decoded_sequence = SequenceSimple(new SequenceSimpleStruct(dst, len));
    return decoded_sequence;
}

func decode_item_length{range_check_ptr}(encoded_data: Bytes) -> felt {
    alloc_locals;
    assert [range_check_ptr] = encoded_data.value.len;
    let range_check_ptr = range_check_ptr + 1;

    let first_rlp_byte = encoded_data.value.data[0];

    let cond = is_le(first_rlp_byte, 0x80 - 1);
    if (cond != 0) {
        return 1;
    }

    let cond = is_le(first_rlp_byte, 0xB7);
    if (cond != 0) {
        let decoded_data_length = first_rlp_byte - 0x80;
        return 1 + decoded_data_length;
    }

    let cond = is_le(first_rlp_byte, 0xBF);
    if (cond != 0) {
        let length_length = first_rlp_byte - 0xB7;
        assert [range_check_ptr] = encoded_data.value.len - length_length - 1;
        let range_check_ptr = range_check_ptr + 1;
        assert_not_zero(encoded_data.value.data[1]);
        let decoded_data_length = bytes_to_felt(length_length, encoded_data.value.data + 1);
        return 1 + length_length + decoded_data_length;
    }

    let cond = is_le(first_rlp_byte, 0xF7);
    if (cond != 0) {
        let decoded_data_length = first_rlp_byte - 0xC0;
        return 1 + decoded_data_length;
    }

    let length_length = first_rlp_byte - 0xF7;
    assert [range_check_ptr] = encoded_data.value.len - length_length - 1;
    let range_check_ptr = range_check_ptr + 1;
    assert_not_zero(encoded_data.value.data[1]);
    let decoded_data_length = bytes_to_felt(length_length, encoded_data.value.data + 1);
    return 1 + length_length + decoded_data_length;
}

//
// RLP Encode Helper Functions
//

func _encode{range_check_ptr}(dst: felt*, raw_data: Extended) -> felt {
    alloc_locals;

    if (cast(raw_data.value.sequence.value, felt) != 0) {
        return _encode_sequence(dst, raw_data.value.sequence);
    }

    if (cast(raw_data.value.bytearray.value, felt) != 0) {
        return _encode_bytes(dst, raw_data.value.bytearray);
    }

    if (cast(raw_data.value.bytes.value, felt) != 0) {
        return _encode_bytes(dst, raw_data.value.bytes);
    }

    if (cast(raw_data.value.uint, felt) != 0) {
        return _encode_uint(dst, raw_data.value.uint.value);
    }

    if (cast(raw_data.value.fixed_uint, felt) != 0) {
        return _encode_uint(dst, raw_data.value.fixed_uint.value);
    }

    if (cast(raw_data.value.str.value, felt) != 0) {
        return _encode_string(dst, raw_data.value.str);
    }

    if (cast(raw_data.value.bool, felt) != 0) {
        return _encode_uint(dst, raw_data.value.bool.value);
    }

    with_attr error_message("RLP Encoding type is not supported") {
        assert 0 = 1;
        return 0;
    }
}

func _encode_uint{range_check_ptr}(dst: felt*, raw_uint: felt) -> felt {
    alloc_locals;
    if (raw_uint == 0) {
        assert [dst] = 0x80;
        return 1;
    }
    let (raw_uint_as_bytes_be) = alloc();
    let raw_uint_as_bytes_be_len = felt_to_bytes(raw_uint_as_bytes_be, raw_uint);
    tempvar raw_uint_as_bytes = Bytes(
        new BytesStruct(raw_uint_as_bytes_be, raw_uint_as_bytes_be_len)
    );
    return _encode_bytes(dst, raw_uint_as_bytes);
}

func _encode_u256{range_check_ptr}(dst: felt*, raw_uint: U256) -> felt {
    alloc_locals;
    if (raw_uint.value.high == 0 and raw_uint.value.low == 0) {
        assert [dst] = 0x80;
        return 1;
    }
    let (raw_uint_as_bytes_be) = alloc();
    let raw_uint_as_bytes_be_len = uint256_to_bytes(raw_uint_as_bytes_be, [raw_uint.value]);
    tempvar raw_uint_as_bytes = Bytes(
        new BytesStruct(raw_uint_as_bytes_be, raw_uint_as_bytes_be_len)
    );
    return _encode_bytes(dst, raw_uint_as_bytes);
}

func _encode_u256_little{range_check_ptr}(dst: felt*, raw_uint: U256) -> felt {
    alloc_locals;
    if (raw_uint.value.high == 0 and raw_uint.value.low == 0) {
        assert [dst] = 0x80;
        return 1;
    }
    let (raw_uint_as_bytes_le) = alloc();
    let raw_uint_as_bytes_le_len = uint256_to_bytes_little(raw_uint_as_bytes_le, [raw_uint.value]);
    tempvar raw_uint_as_bytes = Bytes(
        new BytesStruct(raw_uint_as_bytes_le, raw_uint_as_bytes_le_len)
    );
    return _encode_bytes(dst, raw_uint_as_bytes);
}

func _encode_string{range_check_ptr}(dst: felt*, raw_string: String) -> felt {
    return _encode_bytes(dst, Bytes(cast(raw_string.value, BytesStruct*)));
}

func _encode_bytes{range_check_ptr}(dst: felt*, raw_bytes: Bytes) -> felt {
    alloc_locals;

    let len_raw_data = raw_bytes.value.len;

    if (len_raw_data == 0) {
        assert [dst] = 0x80;
        tempvar value = new BytesStruct(dst, 1);
        return 1;
    }

    let cond_1 = is_le(raw_bytes.value.data[0], 0x80 - 1);
    let cond_2 = is_zero(len_raw_data - 1);
    if (cond_1 * cond_2 != 0) {
        memcpy(dst, raw_bytes.value.data, raw_bytes.value.len);
        return raw_bytes.value.len;
    }

    let cond = is_le(len_raw_data, 0x38 - 1);
    if (cond != 0) {
        assert [dst] = 0x80 + len_raw_data;
        memcpy(dst + 1, raw_bytes.value.data, len_raw_data);
        tempvar value = new BytesStruct(dst, len_raw_data + 1);
        return len_raw_data + 1;
    }

    let len_raw_data_as_be = felt_to_bytes(dst + 1, len_raw_data);
    assert [dst] = 0xB7 + len_raw_data_as_be;

    memcpy(dst + 1 + len_raw_data_as_be, raw_bytes.value.data, raw_bytes.value.len);
    return 1 + len_raw_data_as_be + raw_bytes.value.len;
}

func _get_joined_encodings{range_check_ptr}(dst: felt*, raw_bytes: Extended*, len: felt) -> felt {
    alloc_locals;

    if (len == 0) {
        return 0;
    }

    let current_len = _encode(dst, raw_bytes[0]);
    let len = _get_joined_encodings(dst + current_len, raw_bytes + 1, len - 1);

    return current_len + len;
}

func _encode_sequence{range_check_ptr}(dst: felt*, raw_sequence: SequenceExtended) -> felt {
    alloc_locals;
    let (tmp_dst_start: felt*) = alloc();
    let body_ptr = tmp_dst_start + PREFIX_LEN_MAX;
    let body_len = _get_joined_encodings(body_ptr, raw_sequence.value.data, raw_sequence.value.len);
    let prefix_len = _encode_prefix_len(body_ptr, body_len);
    memcpy(dst, body_ptr - prefix_len, prefix_len + body_len);
    return prefix_len + body_len;
}

func _encode_address{range_check_ptr}(dst: felt*, address: Address) -> felt {
    assert [dst] = 0x80 + 20;
    felt_to_bytes20_little(dst + 1, address.value);
    return 21;
}

func _encode_to{range_check_ptr}(dst: felt*, to: To) -> felt {
    if (cast(to.value.address, felt) != 0) {
        return _encode_address(dst, [to.value.address]);
    }

    assert [dst] = 0x80;
    return 1;
}

func _encode_bytes32{range_check_ptr}(dst: felt*, raw_bytes32: Bytes32) -> felt {
    assert [dst] = 0x80 + 32;
    uint256_to_bytes32_little(dst + 1, [raw_bytes32.value]);
    return 33;
}

func _encode_tuple_bytes32{range_check_ptr}(dst: felt*, raw_tuple_bytes32: TupleBytes32) -> felt {
    alloc_locals;

    if (raw_tuple_bytes32.value.len == 0) {
        assert [dst] = 0xc0;
        return 1;
    }

    if (raw_tuple_bytes32.value.len == 1) {
        assert [dst] = 0xc0 + 33;
        assert [dst + 1] = 0x80 + 32;
        uint256_to_bytes32_little(dst + 2, [raw_tuple_bytes32.value.data[0].value]);
        return 34;
    }

    let joined_encodings_len = raw_tuple_bytes32.value.len * 33;
    let (len_joined_encodings: felt*) = alloc();
    let len_joined_encodings_len = felt_to_bytes(len_joined_encodings, joined_encodings_len);
    assert [dst] = 0xF7 + len_joined_encodings_len;
    memcpy(dst + 1, len_joined_encodings, len_joined_encodings_len);
    let dst = dst + 1 + len_joined_encodings_len;

    _encode_tuple_bytes32_inner(dst, raw_tuple_bytes32.value.len, raw_tuple_bytes32.value.data);

    return 1 + len_joined_encodings_len + joined_encodings_len;
}

func _encode_tuple_bytes32_inner{range_check_ptr}(
    dst: felt*, len: felt, raw_tuple_bytes32: Bytes32*
) {
    if (len == 0) {
        return ();
    }

    _encode_bytes32(dst, [raw_tuple_bytes32]);
    _encode_tuple_bytes32_inner(dst + 33, len - 1, raw_tuple_bytes32 + 1);

    return ();
}

func _encode_tuple_log{range_check_ptr}(dst: felt*, raw_tuple_log: TupleLog) -> felt {
    alloc_locals;
    if (raw_tuple_log.value.len == 0) {
        assert [dst] = 0xc0;
        return 1;
    }

    let (local tmp) = alloc();
    let body_ptr = tmp + PREFIX_LEN_MAX;
    let body_len = _encode_tuple_log_inner(
        body_ptr, raw_tuple_log.value.len, raw_tuple_log.value.data
    );
    let prefix_len = _encode_prefix_len(body_ptr, body_len);

    memcpy(dst, body_ptr - prefix_len, prefix_len + body_len);

    return prefix_len + body_len;
}

func _encode_tuple_log_inner{range_check_ptr}(dst: felt*, len: felt, raw_tuple_log: Log*) -> felt {
    alloc_locals;
    if (len == 0) {
        return 0;
    }

    let log_encoded = encode_log(raw_tuple_log[0]);
    memcpy(dst, log_encoded.value.data, log_encoded.value.len);

    let remaining_len = _encode_tuple_log_inner(
        dst + log_encoded.value.len, len - 1, raw_tuple_log + 1
    );

    return log_encoded.value.len + remaining_len;
}

func _encode_tuple_access_list_inner{range_check_ptr}(
    dst: felt*, len: felt, raw_tuple_access_list: AccessList*
) -> felt {
    alloc_locals;
    if (len == 0) {
        return 0;
    }

    // Encode current item
    let access_list_encoded = encode_access_list(raw_tuple_access_list[0]);
    memcpy(dst, access_list_encoded.value.data, access_list_encoded.value.len);

    // Recursively encode remaining items
    let remaining_len = _encode_tuple_access_list_inner(
        dst + access_list_encoded.value.len, len - 1, raw_tuple_access_list + 1
    );

    return access_list_encoded.value.len + remaining_len;
}

func _encode_tuple_access_list{range_check_ptr}(
    dst: felt*, tuple_access_list: TupleAccessList
) -> felt {
    alloc_locals;
    if (tuple_access_list.value.len == 0) {
        assert [dst] = 0xc0;
        return 1;
    }

    let (local tmp) = alloc();
    let body_ptr = tmp + PREFIX_LEN_MAX;
    let body_len = _encode_tuple_access_list_inner(
        body_ptr, tuple_access_list.value.len, tuple_access_list.value.data
    );
    let prefix_len = _encode_prefix_len(body_ptr, body_len);

    memcpy(dst, body_ptr - prefix_len, prefix_len + body_len);

    return prefix_len + body_len;
}

func _encode_bloom{range_check_ptr}(dst: felt*, raw_bloom: Bloom) -> felt {
    alloc_locals;
    // Bloom is 256 bytes, so the prefix is [0xb7 + 2, 0x01, 0x00]
    // ie. a bytes of length 0x0100
    assert [dst] = 0xb7 + 2;
    assert [dst + 1] = 1;
    assert [dst + 2] = 0;
    let dst = dst + 3;

    // Bloom is 256 bytes encoded as 16 u128 little endian
    felt_to_bytes16_little(dst, raw_bloom.value[0].value);
    felt_to_bytes16_little(dst + 16, raw_bloom.value[1].value);
    felt_to_bytes16_little(dst + 32, raw_bloom.value[2].value);
    felt_to_bytes16_little(dst + 48, raw_bloom.value[3].value);
    felt_to_bytes16_little(dst + 64, raw_bloom.value[4].value);
    felt_to_bytes16_little(dst + 80, raw_bloom.value[5].value);
    felt_to_bytes16_little(dst + 96, raw_bloom.value[6].value);
    felt_to_bytes16_little(dst + 112, raw_bloom.value[7].value);
    felt_to_bytes16_little(dst + 128, raw_bloom.value[8].value);
    felt_to_bytes16_little(dst + 144, raw_bloom.value[9].value);
    felt_to_bytes16_little(dst + 160, raw_bloom.value[10].value);
    felt_to_bytes16_little(dst + 176, raw_bloom.value[11].value);
    felt_to_bytes16_little(dst + 192, raw_bloom.value[12].value);
    felt_to_bytes16_little(dst + 208, raw_bloom.value[13].value);
    felt_to_bytes16_little(dst + 224, raw_bloom.value[14].value);
    felt_to_bytes16_little(dst + 240, raw_bloom.value[15].value);

    return 3 + 256;
}

// @notice Prepend the encoded length to the encoded data.
// @dev The encoded length is prepended, meaning that [dst - i] is written into.
// @dev The big endian encoded length cannot be greater than 8 (0xff - 0xf7),
// @dev meaning that 9 bytes upfront (1 + 8) at maximum are enough.
// @return The final offset to apply to dst.
func _encode_prefix_len{range_check_ptr}(dst: felt*, len: felt) -> felt {
    alloc_locals;

    let cond = is_le(len, 0x38 - 1);
    if (cond != 0) {
        assert [dst - 1] = 0xC0 + len;
        return 1;
    }

    let (len_be: felt*) = alloc();
    let len_be_len = felt_to_bytes(len_be, len);
    assert [dst - 1 - len_be_len] = 0xF7 + len_be_len;
    memcpy(dst - len_be_len, len_be, len_be_len);
    return 1 + len_be_len;
}

//
// RLP Decode Helper Functions
//

func _decode_joined_encodings{range_check_ptr}(dst: Simple*, joined_encodings: Bytes) -> felt {
    alloc_locals;

    if (joined_encodings.value.len == 0) {
        return 0;
    }

    let encoded_item_length = decode_item_length(joined_encodings);
    assert [range_check_ptr] = joined_encodings.value.len - encoded_item_length;
    let range_check_ptr = range_check_ptr + 1;

    tempvar encoded_item = Bytes(new BytesStruct(joined_encodings.value.data, encoded_item_length));
    let decoded_item = decode(encoded_item);
    assert [dst] = decoded_item;

    tempvar joined_encodings = Bytes(
        new BytesStruct(
            joined_encodings.value.data + encoded_item_length,
            joined_encodings.value.len - encoded_item_length,
        ),
    );

    let len = _decode_joined_encodings(dst + 1, joined_encodings);
    return 1 + len;
}
