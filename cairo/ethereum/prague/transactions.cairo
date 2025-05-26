from starkware.cairo.common.math_cmp import is_le_felt, is_not_zero
from starkware.cairo.common.bool import FALSE
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, ModBuiltin, PoseidonBuiltin
from ethereum.crypto.elliptic_curve import secp256k1_recover, public_key_point_to_eth_address
from ethereum.utils.numeric import U256_le, U256__eq__, max
from ethereum_types.bytes import Bytes, BytesStruct
from ethereum_types.numeric import Uint, bool, U256, U256Struct, U64
from ethereum.prague.fork_types import Address
from ethereum.prague.vm.gas import init_code_cost
from ethereum.prague.transactions_types import (
    Transaction,
    TransactionType,
    TransactionStruct,
    LegacyTransaction,
    LegacyTransactionStruct,
    AccessListTransaction,
    AccessListTransactionStruct,
    FeeMarketTransaction,
    FeeMarketTransactionStruct,
    BlobTransaction,
    BlobTransactionStruct,
    SetCodeTransaction,
    SetCodeTransactionStruct,
    To,
    TupleAccessStruct,
    TX_BASE_COST,
    TX_CREATE_COST,
    TX_ACCESS_LIST_ADDRESS_COST,
    TX_ACCESS_LIST_STORAGE_KEY_COST,
    get_r,
    get_s,
    get_to,
)
from ethereum.crypto.hash import keccak256, Hash32
from ethereum_rlp.rlp import (
    encode_legacy_transaction_for_signing,
    encode_eip155_transaction_for_signing,
    encode_access_list_transaction_for_signing,
    encode_fee_market_transaction_for_signing,
    encode_blob_transaction_for_signing,
    encode_eip7702_transaction_for_signing,
    decode_to_access_list_transaction,
    decode_to_fee_market_transaction,
    decode_to_blob_transaction,
    encode_legacy_transaction,
)
from ethereum.prague.blocks import UnionBytesLegacyTransaction
from ethereum.prague.utils.constants import MAX_CODE_SIZE
from ethereum.prague.vm.eoa_delegation import PER_EMPTY_ACCOUNT_COST_LOW
from cairo_core.control_flow import raise
from cairo_ec.curve.secp256k1 import secp256k1
from legacy.utils.array import count_not_zero

const FLOOR_CALLDATA_COST = 10;
const STANDARD_CALLDATA_TOKEN_COST = 4;

func calculate_intrinsic_cost{range_check_ptr}(tx: Transaction) -> (Uint, Uint) {
    alloc_locals;

    let tokens_in_calldata = _calculate_tokens_in_calldata(tx.value.legacy_transaction.value.data);
    let calldata_floor_gas_cost = Uint(tokens_in_calldata * FLOOR_CALLDATA_COST + TX_BASE_COST);

    if (tx.value.legacy_transaction.value != 0) {
        let to = get_to(tx);
        let legacy_tx = tx.value.legacy_transaction;
        let cost_data_and_create = _calculate_data_and_create_cost(
            legacy_tx.value.data, to, tokens_in_calldata
        );
        let cost = Uint(TX_BASE_COST + cost_data_and_create);
        return (cost, calldata_floor_gas_cost);
    }

    if (tx.value.access_list_transaction.value != 0) {
        let to = get_to(tx);
        let access_list_tx = tx.value.access_list_transaction;
        let cost_data_and_create = _calculate_data_and_create_cost(
            access_list_tx.value.data, to, tokens_in_calldata
        );
        let cost_access_list = _calculate_access_list_cost(
            [access_list_tx.value.access_list.value]
        );
        let cost = Uint(TX_BASE_COST + cost_data_and_create + cost_access_list);
        return (cost, calldata_floor_gas_cost);
    }

    if (tx.value.fee_market_transaction.value != 0) {
        let to = get_to(tx);
        let fee_market_tx = tx.value.fee_market_transaction;
        let cost_data_and_create = _calculate_data_and_create_cost(
            fee_market_tx.value.data, to, tokens_in_calldata
        );
        let cost_access_list = _calculate_access_list_cost([fee_market_tx.value.access_list.value]);
        let cost = Uint(TX_BASE_COST + cost_data_and_create + cost_access_list);
        return (cost, calldata_floor_gas_cost);
    }

    if (tx.value.blob_transaction.value != 0) {
        let to = get_to(tx);
        let blob_tx = tx.value.blob_transaction;
        let cost_data_and_create = _calculate_data_and_create_cost(
            blob_tx.value.data, to, tokens_in_calldata
        );
        let cost_access_list = _calculate_access_list_cost([blob_tx.value.access_list.value]);
        let cost = Uint(TX_BASE_COST + cost_data_and_create + cost_access_list);
        return (cost, calldata_floor_gas_cost);
    }

    if (tx.value.set_code_transaction.value != 0) {
        let to = get_to(tx);
        let set_code_tx = tx.value.set_code_transaction;
        let cost_data = _calculate_data_and_create_cost(
            set_code_tx.value.data, to, tokens_in_calldata
        );
        let cost_access_list = _calculate_access_list_cost([set_code_tx.value.access_list.value]);
        let authorizations = set_code_tx.value.authorizations;
        let cost_auth = PER_EMPTY_ACCOUNT_COST_LOW * authorizations.value.len;
        let cost = Uint(TX_BASE_COST + cost_data + cost_access_list + cost_auth);
        return (cost, calldata_floor_gas_cost);
    }

    with_attr error_message("InvalidTransaction") {
        jmp raise.raise_label;
    }
}

func _calculate_tokens_in_calldata{range_check_ptr}(data: Bytes) -> felt {
    alloc_locals;
    let count = count_not_zero(data.value.len, data.value.data);
    let zeroes = data.value.len - count;
    let tokens_in_calldata = zeroes + (data.value.len - zeroes) * 4;
    return tokens_in_calldata;
}

func _calculate_data_and_create_cost{range_check_ptr}(
    data: Bytes, to: To, tokens_in_calldata: felt
) -> felt {
    alloc_locals;

    let data_cost = tokens_in_calldata * STANDARD_CALLDATA_TOKEN_COST;
    if (cast(to.value, felt) != 0 and cast(to.value.address, felt) != 0) {
        return data_cost;
    }

    let cost = init_code_cost(Uint(data.value.len));
    return data_cost + TX_CREATE_COST + cost.value;
}

func _calculate_access_list_cost{range_check_ptr}(access_list: TupleAccessStruct) -> felt {
    alloc_locals;
    if (access_list.len == 0) {
        return 0;
    }

    let current_list = access_list.data[access_list.len - 1];
    let current_cost = TX_ACCESS_LIST_ADDRESS_COST + current_list.value.slots.value.len *
        TX_ACCESS_LIST_STORAGE_KEY_COST;
    let access_list = TupleAccessStruct(data=access_list.data, len=access_list.len - 1);
    let cum_gas_cost = _calculate_access_list_cost(access_list);
    let cost = current_cost + cum_gas_cost;
    return cost;
}

func validate_transaction{range_check_ptr}(tx: Transaction) -> (Uint, Uint) {
    alloc_locals;

    local tx_gas: Uint;
    local tx_nonce: U256;
    local tx_data: Bytes;
    local tx_to_ptr: Address*;

    if (tx.value.legacy_transaction.value != 0) {
        assert tx_gas = tx.value.legacy_transaction.value.gas;
        assert tx_nonce = tx.value.legacy_transaction.value.nonce;
        assert tx_data = tx.value.legacy_transaction.value.data;
        assert tx_to_ptr = tx.value.legacy_transaction.value.to.value.address;
    }

    if (tx.value.access_list_transaction.value != 0) {
        assert tx_gas = tx.value.access_list_transaction.value.gas;
        assert tx_nonce = tx.value.access_list_transaction.value.nonce;
        assert tx_data = tx.value.access_list_transaction.value.data;
        assert tx_to_ptr = tx.value.access_list_transaction.value.to.value.address;
    }

    if (tx.value.fee_market_transaction.value != 0) {
        assert tx_gas = tx.value.fee_market_transaction.value.gas;
        assert tx_nonce = tx.value.fee_market_transaction.value.nonce;
        assert tx_data = tx.value.fee_market_transaction.value.data;
        assert tx_to_ptr = tx.value.fee_market_transaction.value.to.value.address;
    }

    if (tx.value.blob_transaction.value != 0) {
        assert tx_gas = tx.value.blob_transaction.value.gas;
        assert tx_nonce = tx.value.blob_transaction.value.nonce;
        assert tx_data = tx.value.blob_transaction.value.data;
        assert tx_to_ptr = &tx.value.blob_transaction.value.to;
    }

    if (tx.value.set_code_transaction.value != 0) {
        assert tx_gas = tx.value.set_code_transaction.value.gas;
        tempvar nonce_u256 = U256(
            new U256Struct(tx.value.set_code_transaction.value.nonce.value, 0)
        );
        assert tx_nonce = nonce_u256;
        assert tx_data = tx.value.set_code_transaction.value.data;
        assert tx_to_ptr = &tx.value.set_code_transaction.value.to;
    }

    let (intrinsic_cost, calldata_floor_gas_cost) = calculate_intrinsic_cost(tx);
    let max_cost = max(intrinsic_cost.value, calldata_floor_gas_cost.value);
    let is_gas_insufficient = is_le_felt(tx_gas.value, max_cost - 1);
    if (is_gas_insufficient != FALSE) {
        raise('InvalidTransaction');
    }

    let is_nonce_out_of_range = is_le_felt(2 ** 64 - 1, tx_nonce.value.low);
    if (is_nonce_out_of_range + tx_nonce.value.high != FALSE) {
        raise('InvalidTransaction');
    }

    let is_data_not_zero = is_not_zero(tx_data.value.len);
    let is_data_too_large = is_le_felt(2 * MAX_CODE_SIZE, tx_data.value.len - 1);
    if (tx_to_ptr == 0 and is_data_not_zero != FALSE and is_data_too_large != FALSE) {
        raise('InvalidTransaction');
    }

    return (intrinsic_cost, calldata_floor_gas_cost);
}

func signing_hash_pre155{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: felt*}(
    tx: LegacyTransaction
) -> Hash32 {
    let encoded_tx = encode_legacy_transaction_for_signing(tx);
    let hash = keccak256(encoded_tx);
    return hash;
}

func signing_hash_155{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: felt*}(
    tx: LegacyTransaction, chain_id: U64
) -> Hash32 {
    let encoded_tx = encode_eip155_transaction_for_signing(tx, chain_id);
    let hash = keccak256(encoded_tx);
    return hash;
}

func signing_hash_2930{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: felt*}(
    tx: AccessListTransaction
) -> Hash32 {
    let encoded_tx = encode_access_list_transaction_for_signing(tx);
    let hash = keccak256(encoded_tx);
    return hash;
}

func signing_hash_1559{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: felt*}(
    tx: FeeMarketTransaction
) -> Hash32 {
    let encoded_tx = encode_fee_market_transaction_for_signing(tx);
    let hash = keccak256(encoded_tx);
    return hash;
}

func signing_hash_4844{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: felt*}(
    tx: BlobTransaction
) -> Hash32 {
    let encoded_tx = encode_blob_transaction_for_signing(tx);
    let hash = keccak256(encoded_tx);
    return hash;
}

func signing_hash_7702{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: felt*}(
    tx: SetCodeTransaction
) -> Hash32 {
    let encoded_tx = encode_eip7702_transaction_for_signing(tx);
    let hash = keccak256(encoded_tx);
    return hash;
}

func recover_sender{
    range_check_ptr,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
}(chain_id: U64, tx: Transaction) -> Address {
    alloc_locals;
    tempvar SECP256K1N = U256(new U256Struct(low=secp256k1.N_LOW_128, high=secp256k1.N_HIGH_128));
    tempvar SECP256K1N_DIVIDED_BY_2 = U256(
        new U256Struct(low=secp256k1.N_DIVIDED_BY_2_LOW_128, high=secp256k1.N_DIVIDED_BY_2_HIGH_128)
    );
    tempvar zero = U256(new U256Struct(low=0, high=0));

    let r = get_r(tx);
    let s = get_s(tx);

    let r_is_zero = U256__eq__(r, zero);
    let r_is_out_of_range = U256_le(SECP256K1N, r);

    let s_is_zero = U256__eq__(s, zero);
    let s_is_within_range = U256_le(s, SECP256K1N_DIVIDED_BY_2);

    let is_error = r_is_zero.value + r_is_out_of_range.value + s_is_zero.value + (
        1 - s_is_within_range.value
    );
    with_attr error_message("InvalidSignatureError") {
        assert is_error = 0;
    }

    if (cast(tx.value.legacy_transaction.value, felt) != 0) {
        let v_u256 = tx.value.legacy_transaction.value.v;
        with_attr error_message("InvalidSignatureError") {
            assert v_u256.value.high = 0;
        }
        let v = v_u256.value.low;
        let tx_is_not_pre155 = (v - 27) * (v - 28);
        if (tx_is_not_pre155 == FALSE) {
            let y_parity_felt = v - 27;
            tempvar y_parity = U256(new U256Struct(low=y_parity_felt, high=0));
            let hash = signing_hash_pre155(tx.value.legacy_transaction);
            let (public_key_x, public_key_y, error) = secp256k1_recover(r, s, y_parity, hash);
            if (cast(error, felt) != 0) {
                raise('InvalidSignatureError');
            }
            let sender = public_key_point_to_eth_address(public_key_x, public_key_y);
            return sender;
        } else {
            let bad_v = (v - 35 - chain_id.value * 2) * (v - 36 - chain_id.value * 2);
            with_attr error_message("InvalidSignatureError") {
                assert bad_v = 0;
            }
            let hash = signing_hash_155(tx.value.legacy_transaction, chain_id);
            let y_parity_felt = v - 35 - chain_id.value * 2;
            tempvar y_parity = U256(new U256Struct(low=y_parity_felt, high=0));
            let (public_key_x, public_key_y, error) = secp256k1_recover(r, s, y_parity, hash);
            if (cast(error, felt) != 0) {
                raise('InvalidSignatureError');
            }
            let sender = public_key_point_to_eth_address(public_key_x, public_key_y);
            return sender;
        }
    }

    if (cast(tx.value.access_list_transaction.value, felt) != 0) {
        let y_parity = tx.value.access_list_transaction.value.y_parity;
        let y_parity_is_zero = U256__eq__(y_parity, zero);
        let y_parity_is_one = U256__eq__(y_parity, U256(new U256Struct(low=1, high=0)));
        with_attr error_message("InvalidSignatureError") {
            assert (1 - y_parity_is_zero.value) * (1 - y_parity_is_one.value) = 0;
        }
        let hash = signing_hash_2930(tx.value.access_list_transaction);
        let (public_key_x, public_key_y, error) = secp256k1_recover(r, s, y_parity, hash);
        if (cast(error, felt) != 0) {
            raise('InvalidSignatureError');
        }
        let sender = public_key_point_to_eth_address(public_key_x, public_key_y);
        return sender;
    }

    if (cast(tx.value.fee_market_transaction.value, felt) != 0) {
        let y_parity = tx.value.fee_market_transaction.value.y_parity;
        let y_parity_is_zero = U256__eq__(y_parity, zero);
        let y_parity_is_one = U256__eq__(y_parity, U256(new U256Struct(low=1, high=0)));
        with_attr error_message("InvalidSignatureError") {
            assert (1 - y_parity_is_zero.value) * (1 - y_parity_is_one.value) = 0;
        }

        let hash = signing_hash_1559(tx.value.fee_market_transaction);
        let (public_key_x, public_key_y, error) = secp256k1_recover(r, s, y_parity, hash);
        if (cast(error, felt) != 0) {
            raise('InvalidSignatureError');
        }
        let sender = public_key_point_to_eth_address(public_key_x, public_key_y);
        return sender;
    }

    if (cast(tx.value.blob_transaction.value, felt) != 0) {
        let y_parity = tx.value.blob_transaction.value.y_parity;
        let y_parity_is_zero = U256__eq__(y_parity, zero);
        let y_parity_is_one = U256__eq__(y_parity, U256(new U256Struct(low=1, high=0)));
        with_attr error_message("InvalidSignatureError") {
            assert (1 - y_parity_is_zero.value) * (1 - y_parity_is_one.value) = 0;
        }
        let hash = signing_hash_4844(tx.value.blob_transaction);
        let (public_key_x, public_key_y, error) = secp256k1_recover(r, s, y_parity, hash);
        if (cast(error, felt) != 0) {
            raise('InvalidSignatureError');
        }
        let sender = public_key_point_to_eth_address(public_key_x, public_key_y);
        return sender;
    }

    if (cast(tx.value.set_code_transaction.value, felt) != 0) {
        let y_parity = tx.value.set_code_transaction.value.y_parity;
        let y_parity_is_zero = U256__eq__(y_parity, zero);
        let y_parity_is_one = U256__eq__(y_parity, U256(new U256Struct(low=1, high=0)));
        with_attr error_message("InvalidSignatureError") {
            assert (1 - y_parity_is_zero.value) * (1 - y_parity_is_one.value) = 0;
        }
        let hash = signing_hash_7702(tx.value.set_code_transaction);
        let (public_key_x, public_key_y, error) = secp256k1_recover(r, s, y_parity, hash);
        if (cast(error, felt) != 0) {
            raise('InvalidSignatureError');
        }
        let sender = public_key_point_to_eth_address(public_key_x, public_key_y);
        return sender;
    }

    // Invariant: at least one of the transaction types is non-zero.
    with_attr error_message("InvalidTransaction") {
        jmp raise.raise_label;
    }
}

func decode_transaction{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    tx: UnionBytesLegacyTransaction
) -> Transaction {
    if (cast(tx.value.bytes.value, felt) != 0) {
        let bytes = tx.value.bytes.value;
        let bytes_len = bytes.len;
        with_attr error_message("TransactionTypeError") {
            assert_not_zero(bytes_len);
        }
        let transaction_type = bytes.data[0];
        if (transaction_type == TransactionType.ACCESS_LIST) {
            tempvar new_bytes = Bytes(new BytesStruct(data=bytes.data + 1, len=bytes_len - 1));
            let access_list_transaction = decode_to_access_list_transaction(new_bytes);
            tempvar res = Transaction(
                new TransactionStruct(
                    legacy_transaction=LegacyTransaction(cast(0, LegacyTransactionStruct*)),
                    access_list_transaction=access_list_transaction,
                    fee_market_transaction=FeeMarketTransaction(
                        cast(0, FeeMarketTransactionStruct*)
                    ),
                    blob_transaction=BlobTransaction(cast(0, BlobTransactionStruct*)),
                    set_code_transaction=SetCodeTransaction(cast(0, SetCodeTransactionStruct*)),
                ),
            );
            return res;
        }
        if (transaction_type == TransactionType.FEE_MARKET) {
            tempvar new_bytes = Bytes(new BytesStruct(data=bytes.data + 1, len=bytes_len - 1));
            let fee_market_transaction = decode_to_fee_market_transaction(new_bytes);
            tempvar res = Transaction(
                new TransactionStruct(
                    legacy_transaction=LegacyTransaction(cast(0, LegacyTransactionStruct*)),
                    access_list_transaction=AccessListTransaction(
                        cast(0, AccessListTransactionStruct*)
                    ),
                    fee_market_transaction=fee_market_transaction,
                    blob_transaction=BlobTransaction(cast(0, BlobTransactionStruct*)),
                    set_code_transaction=SetCodeTransaction(cast(0, SetCodeTransactionStruct*)),
                ),
            );
            return res;
        }
        if (transaction_type == TransactionType.BLOB) {
            tempvar new_bytes = Bytes(new BytesStruct(data=bytes.data + 1, len=bytes_len - 1));
            let blob_transaction = decode_to_blob_transaction(new_bytes);
            tempvar res = Transaction(
                new TransactionStruct(
                    legacy_transaction=LegacyTransaction(cast(0, LegacyTransactionStruct*)),
                    access_list_transaction=AccessListTransaction(
                        cast(0, AccessListTransactionStruct*)
                    ),
                    fee_market_transaction=FeeMarketTransaction(
                        cast(0, FeeMarketTransactionStruct*)
                    ),
                    blob_transaction=blob_transaction,
                    set_code_transaction=SetCodeTransaction(cast(0, SetCodeTransactionStruct*)),
                ),
            );
            return res;
        }
    }
    if (cast(tx.value.legacy_transaction.value, felt) != 0) {
        tempvar res = Transaction(
            new TransactionStruct(
                legacy_transaction=tx.value.legacy_transaction,
                access_list_transaction=AccessListTransaction(
                    cast(0, AccessListTransactionStruct*)
                ),
                fee_market_transaction=FeeMarketTransaction(cast(0, FeeMarketTransactionStruct*)),
                blob_transaction=BlobTransaction(cast(0, BlobTransactionStruct*)),
                set_code_transaction=SetCodeTransaction(cast(0, SetCodeTransactionStruct*)),
            ),
        );
        return res;
    }
    with_attr error_message("TransactionTypeError") {
        jmp raise.raise_label;
    }
}

func get_transaction_hash{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: felt*}(
    tx_encoded: UnionBytesLegacyTransaction
) -> Hash32 {
    alloc_locals;

    if (cast(tx_encoded.value.bytes.value, felt) != 0) {
        // This is a typed transaction, already RLP encoded with its type prefix
        let hash = keccak256(tx_encoded.value.bytes);
        return hash;
    }

    if (cast(tx_encoded.value.legacy_transaction.value, felt) != 0) {
        // This is a legacy transaction, RLP encode it without chain ID for hashing
        let encoded_legacy_tx = encode_legacy_transaction(tx_encoded.value.legacy_transaction);
        let hash = keccak256(encoded_legacy_tx);
        return hash;
    }

    with_attr error_message("get_transaction_hash: Invalid input type") {
        jmp raise.raise_label;
    }
}
