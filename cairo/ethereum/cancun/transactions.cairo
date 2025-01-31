from starkware.cairo.common.math_cmp import is_le_felt, is_not_zero
from starkware.cairo.common.bool import FALSE, TRUE
from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    KeccakBuiltin,
    ModBuiltin,
    PoseidonBuiltin,
)
from cairo_ec.curve.secp256k1 import secp256k1
from ethereum.crypto.elliptic_curve import secp256k1_recover_uint256_bigends

from ethereum.crypto.elliptic_curve import public_key_point_to_eth_address
from ethereum.utils.numeric import U256_le, U256__eq__
from ethereum_types.bytes import Bytes, Bytes0
from ethereum_types.numeric import Uint, bool, U256, U256Struct, U64
from ethereum.cancun.fork_types import Address
from ethereum.cancun.vm.gas import init_code_cost
from ethereum.cancun.transactions_types import (
    Transaction,
    LegacyTransaction,
    AccessListTransaction,
    FeeMarketTransaction,
    BlobTransaction,
    To,
    ToStruct,
    TupleAccessListStruct,
    TX_BASE_COST,
    TX_DATA_COST_PER_NON_ZERO,
    TX_DATA_COST_PER_ZERO,
    TX_CREATE_COST,
    TX_ACCESS_LIST_ADDRESS_COST,
    TX_ACCESS_LIST_STORAGE_KEY_COST,
)

from ethereum.crypto.hash import keccak256, Hash32
from ethereum_rlp.rlp import (
    encode_legacy_transaction_for_signing,
    encode_eip155_transaction_for_signing,
    encode_access_list_transaction_for_signing,
    encode_fee_market_transaction_for_signing,
    encode_blob_transaction_for_signing,
)

from ethereum.cancun.utils.constants import MAX_CODE_SIZE
from src.utils.array import count_not_zero

func calculate_intrinsic_cost{range_check_ptr}(tx: Transaction) -> Uint {
    alloc_locals;

    if (tx.value.legacy_transaction.value != 0) {
        let legacy_tx = tx.value.legacy_transaction;
        let cost_data_and_create = _calculate_data_and_create_cost(
            legacy_tx.value.data, legacy_tx.value.to
        );
        let cost = Uint(TX_BASE_COST + cost_data_and_create);
        return cost;
    }

    if (tx.value.access_list_transaction.value != 0) {
        let access_list_tx = tx.value.access_list_transaction;
        let cost_data_and_create = _calculate_data_and_create_cost(
            access_list_tx.value.data, access_list_tx.value.to
        );
        let cost_access_list = _calculate_access_list_cost(
            [access_list_tx.value.access_list.value]
        );
        let cost = Uint(TX_BASE_COST + cost_data_and_create + cost_access_list);
        return cost;
    }

    if (tx.value.fee_market_transaction.value != 0) {
        let fee_market_tx = tx.value.fee_market_transaction;
        let cost_data_and_create = _calculate_data_and_create_cost(
            fee_market_tx.value.data, fee_market_tx.value.to
        );
        let cost_access_list = _calculate_access_list_cost([fee_market_tx.value.access_list.value]);
        let cost = Uint(TX_BASE_COST + cost_data_and_create + cost_access_list);
        return cost;
    }

    if (tx.value.blob_transaction.value != 0) {
        let blob_tx = tx.value.blob_transaction;
        tempvar to = new ToStruct(bytes0=cast(0, Bytes0*), address=&blob_tx.value.to);
        let cost_data_and_create = _calculate_data_and_create_cost(blob_tx.value.data, To(to));
        let cost_access_list = _calculate_access_list_cost([blob_tx.value.access_list.value]);
        let cost = Uint(TX_BASE_COST + cost_data_and_create + cost_access_list);
        return cost;
    }

    with_attr error_message("InvalidTransaction") {
        assert 0 = 1;
    }

    let cost = Uint(0);
    return cost;
}

func _calculate_data_and_create_cost{range_check_ptr}(data: Bytes, to: To) -> felt {
    alloc_locals;
    let count = count_not_zero(data.value.len, data.value.data);
    let zeroes = data.value.len - count;
    let data_cost = zeroes * TX_DATA_COST_PER_ZERO + count * TX_DATA_COST_PER_NON_ZERO;

    if (cast(to.value.address, felt) != 0) {
        return data_cost;
    }

    let cost = init_code_cost(Uint(data.value.len));
    return data_cost + TX_CREATE_COST + cost.value;
}

func _calculate_access_list_cost{range_check_ptr}(access_list: TupleAccessListStruct) -> felt {
    alloc_locals;
    if (access_list.len == 0) {
        return 0;
    }

    let current_list = access_list.data[access_list.len - 1];
    let current_cost = TX_ACCESS_LIST_ADDRESS_COST + current_list.value.storage_keys.value.len *
        TX_ACCESS_LIST_STORAGE_KEY_COST;
    let access_list = TupleAccessListStruct(data=access_list.data, len=access_list.len - 1);
    let cum_gas_cost = _calculate_access_list_cost(access_list);
    let cost = current_cost + cum_gas_cost;
    return cost;
}

func validate_transaction{range_check_ptr}(tx: Transaction) -> bool {
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

    let intrinsic_cost = calculate_intrinsic_cost(tx);
    let is_gas_insufficient = is_le_felt(tx_gas.value, intrinsic_cost.value - 1);
    if (is_gas_insufficient != FALSE) {
        tempvar res = bool(FALSE);
        return res;
    }

    let is_nonce_out_of_range = is_le_felt(2 ** 64 - 1, tx_nonce.value.low);
    if (is_nonce_out_of_range + tx_nonce.value.high != FALSE) {
        tempvar res = bool(FALSE);
        return res;
    }

    let is_data_not_zero = is_not_zero(tx_data.value.len);
    let is_data_too_large = is_le_felt(2 * MAX_CODE_SIZE, tx_data.value.len - 1);
    if (tx_to_ptr == 0 and is_data_not_zero != FALSE and is_data_too_large != FALSE) {
        tempvar res = bool(FALSE);
        return res;
    }

    tempvar res = bool(TRUE);
    return res;
}

func signing_hash_pre155{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}(
    tx: LegacyTransaction
) -> Hash32 {
    let encoded_tx = encode_legacy_transaction_for_signing(tx);
    let hash = keccak256(encoded_tx);
    return hash;
}

func signing_hash_155{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}(
    tx: LegacyTransaction, chain_id: U64
) -> Hash32 {
    let encoded_tx = encode_eip155_transaction_for_signing(tx, chain_id);
    let hash = keccak256(encoded_tx);
    return hash;
}

func signing_hash_2930{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}(
    tx: AccessListTransaction
) -> Hash32 {
    let encoded_tx = encode_access_list_transaction_for_signing(tx);
    let hash = keccak256(encoded_tx);
    return hash;
}

func signing_hash_1559{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}(
    tx: FeeMarketTransaction
) -> Hash32 {
    let encoded_tx = encode_fee_market_transaction_for_signing(tx);
    let hash = keccak256(encoded_tx);
    return hash;
}

func signing_hash_4844{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}(
    tx: BlobTransaction
) -> Hash32 {
    let encoded_tx = encode_blob_transaction_for_signing(tx);
    let hash = keccak256(encoded_tx);
    return hash;
}

func recover_sender{
    range_check_ptr,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(chain_id: U64, tx: Transaction) -> Address {
    alloc_locals;
    tempvar SECP256K1N = U256(new U256Struct(low=secp256k1.N_LOW_128, high=secp256k1.N_HIGH_128));
    tempvar SECP256K1N_DIVIDED_BY_2 = U256(
        new U256Struct(low=secp256k1.N_DIVIDED_BY_2_LOW_128, high=secp256k1.N_DIVIDED_BY_2_HIGH_128)
    );
    tempvar zero = U256(new U256Struct(low=0, high=0));

    if (cast(tx.value.legacy_transaction.value, felt) != 0) {
        let r = tx.value.legacy_transaction.value.r;
        let s = tx.value.legacy_transaction.value.s;

        let r_is_zero = U256__eq__(r, zero);
        let r_is_out_of_range = U256_le(SECP256K1N, r);

        let s_is_zero = U256__eq__(s, zero);
        let s_is_within_range = U256_le(s, SECP256K1N_DIVIDED_BY_2);

        let error = r_is_zero.value + r_is_out_of_range.value + s_is_zero.value + (
            1 - s_is_within_range.value
        );
        with_attr error_message("InvalidSignatureError") {
            assert error = 0;
        }

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
            let (x, y) = secp256k1_recover_uint256_bigends(r, s, y_parity, hash);
            let sender = public_key_point_to_eth_address(x, y);
            return sender;
        } else {
            let bad_v = (v - 35 - chain_id.value * 2) * (v - 36 - chain_id.value * 2);
            with_attr error_message("InvalidSignatureError") {
                assert bad_v = 0;
            }
            let hash = signing_hash_155(tx.value.legacy_transaction, chain_id);
            let y_parity_felt = v - 35 - chain_id.value * 2;
            tempvar y_parity = U256(new U256Struct(low=y_parity_felt, high=0));
            let (x, y) = secp256k1_recover_uint256_bigends(r, s, y_parity, hash);
            let sender = public_key_point_to_eth_address(x, y);
            return sender;
        }
    }

    if (cast(tx.value.access_list_transaction.value, felt) != 0) {
        let r = tx.value.access_list_transaction.value.r;
        let s = tx.value.access_list_transaction.value.s;

        let r_is_zero = U256__eq__(r, zero);
        let r_is_out_of_range = U256_le(SECP256K1N, r);

        let s_is_zero = U256__eq__(s, zero);
        let s_is_within_range = U256_le(s, SECP256K1N_DIVIDED_BY_2);

        let error = r_is_zero.value + r_is_out_of_range.value + s_is_zero.value + (
            1 - s_is_within_range.value
        );
        with_attr error_message("InvalidSignatureError") {
            assert error = 0;
        }

        let y_parity = tx.value.access_list_transaction.value.y_parity;
        let y_parity_is_zero = U256__eq__(y_parity, zero);
        let y_parity_is_one = U256__eq__(y_parity, U256(new U256Struct(low=1, high=0)));
        with_attr error_message("ValueError") {
            assert (1 - y_parity_is_zero.value) * (1 - y_parity_is_one.value) = 0;
        }
        let hash = signing_hash_2930(tx.value.access_list_transaction);
        let (x, y) = secp256k1_recover_uint256_bigends(r, s, y_parity, hash);
        let sender = public_key_point_to_eth_address(x, y);
        return sender;
    }

    if (cast(tx.value.fee_market_transaction.value, felt) != 0) {
        let r = tx.value.fee_market_transaction.value.r;
        let s = tx.value.fee_market_transaction.value.s;

        let r_is_zero = U256__eq__(r, zero);
        let r_is_out_of_range = U256_le(SECP256K1N, r);

        let s_is_zero = U256__eq__(s, zero);
        let s_is_within_range = U256_le(s, SECP256K1N_DIVIDED_BY_2);

        let error = r_is_zero.value + r_is_out_of_range.value + s_is_zero.value + (
            1 - s_is_within_range.value
        );
        with_attr error_message("InvalidSignatureError") {
            assert error = 0;
        }
        let y_parity = tx.value.fee_market_transaction.value.y_parity;
        let y_parity_is_zero = U256__eq__(y_parity, zero);
        let y_parity_is_one = U256__eq__(y_parity, U256(new U256Struct(low=1, high=0)));
        with_attr error_message("ValueError") {
            assert (1 - y_parity_is_zero.value) * (1 - y_parity_is_one.value) = 0;
        }

        let hash = signing_hash_1559(tx.value.fee_market_transaction);
        let (x, y) = secp256k1_recover_uint256_bigends(r, s, y_parity, hash);
        let sender = public_key_point_to_eth_address(x, y);
        return sender;
    }

    if (cast(tx.value.blob_transaction.value, felt) != 0) {
        let r = tx.value.blob_transaction.value.r;
        let s = tx.value.blob_transaction.value.s;

        let r_is_zero = U256__eq__(r, zero);
        let r_is_out_of_range = U256_le(SECP256K1N, r);

        let s_is_zero = U256__eq__(s, zero);
        let s_is_within_range = U256_le(s, SECP256K1N_DIVIDED_BY_2);

        let error = r_is_zero.value + r_is_out_of_range.value + s_is_zero.value + (
            1 - s_is_within_range.value
        );
        with_attr error_message("InvalidSignatureError") {
            assert error = 0;
        }
        let y_parity = tx.value.blob_transaction.value.y_parity;
        let y_parity_is_zero = U256__eq__(y_parity, zero);
        let y_parity_is_one = U256__eq__(y_parity, U256(new U256Struct(low=1, high=0)));
        with_attr error_message("ValueError") {
            assert (1 - y_parity_is_zero.value) * (1 - y_parity_is_one.value) = 0;
        }
        let hash = signing_hash_4844(tx.value.blob_transaction);
        let (x, y) = secp256k1_recover_uint256_bigends(r, s, y_parity, hash);
        let sender = public_key_point_to_eth_address(x, y);
        return sender;
    }

    // Invariant: at least one of the transaction types is non-zero.
    with_attr error_message("InvalidTransaction") {
        assert 0 = 1;
    }
    tempvar res = Address(0);
    return res;
}
