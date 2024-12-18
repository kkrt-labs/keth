from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.cairo_builtins import (
    HashBuiltin,
    BitwiseBuiltin,
    KeccakBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
)
from starkware.cairo.common.math_cmp import is_not_zero, is_nn
from starkware.cairo.common.math import assert_not_zero, assert_nn
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.uint256 import Uint256, uint256_lt

from src.model import model
from src.constants import Constants
from src.utils.rlp import RLP
from src.utils.utils import Helpers
from src.utils.bytes import keccak
from src.utils.signature import Signature

const TX_BASE_COST = 21000;
const TX_DATA_COST_PER_NON_ZERO = 16;
const TX_DATA_COST_PER_ZERO = 4;
const TX_CREATE_COST = 32000;
const TX_ACCESS_LIST_ADDRESS_COST = 2400;
const TX_ACCESS_LIST_STORAGE_KEY_COST = 1900;

const SECP256K1N_DIV_2_LOW = 0x5d576e7357a4501ddfe92f46681b20a0;
const SECP256K1N_DIV_2_HIGH = 0x7fffffffffffffffffffffffffffffff;

// @title Transaction utils
// @notice This file contains utils for decoding eth transactions
// @custom:namespace Transaction
namespace Transaction {
    // @notice Decode a legacy Ethereum transaction
    // @dev This function decodes a legacy Ethereum transaction in accordance with EIP-155.
    // It returns transaction details including nonce, gas price, gas limit, destination address, amount, payload,
    // transaction hash, and signature (v, r, s). The transaction hash is computed by keccak hashing the signed
    // transaction data, which includes the chain ID in accordance with EIP-155.
    // @param tx_data_len The length of the raw transaction data
    // @param tx_data The raw transaction data
    func decode_legacy_tx{bitwise_ptr: BitwiseBuiltin*, range_check_ptr}(
        tx_data_len: felt, tx_data: felt*
    ) -> model.Transaction* {
        // see https://github.com/ethereum/EIPs/blob/master/EIPS/eip-155.md
        alloc_locals;
        let (tx_items: RLP.Item*) = alloc();
        RLP.decode(tx_items, tx_data_len, tx_data);

        assert [tx_items].is_list = TRUE;
        let items_len = [tx_items].data_len;
        let items = cast([tx_items].data, RLP.Item*);

        // Pre eip-155 txs have 6 fields, post eip-155 txs have 9 fields
        // We check for both cases here, and do the remaining ones in the next if block
        assert items[0].is_list = FALSE;
        assert items[1].is_list = FALSE;
        assert items[2].is_list = FALSE;
        assert items[3].is_list = FALSE;
        assert items[4].is_list = FALSE;
        assert items[5].is_list = FALSE;

        assert_nn(31 - items[0].data_len);
        let nonce = Helpers.bytes_to_felt(items[0].data_len, items[0].data);
        assert_nn(31 - items[1].data_len);
        let gas_price = Helpers.bytes_to_felt(items[1].data_len, items[1].data);
        assert_nn(31 - items[2].data_len);
        let gas_limit = Helpers.bytes_to_felt(items[2].data_len, items[2].data);
        let destination = Helpers.try_parse_destination_from_bytes(
            items[3].data_len, items[3].data
        );
        assert_nn(32 - items[4].data_len);
        let amount = Helpers.bytes_to_uint256(items[4].data_len, items[4].data);
        let payload_len = items[5].data_len;
        let payload = items[5].data;

        // pre eip-155 txs have 6 fields, post eip-155 txs have 9 fields
        if (items_len == 6) {
            tempvar range_check_ptr = range_check_ptr;
            tempvar is_some = 0;
            tempvar chain_id = 0;
        } else {
            assert items_len = 9;
            assert items[6].is_list = FALSE;
            assert items[7].is_list = FALSE;
            assert items[8].is_list = FALSE;

            assert_nn(31 - items[6].data_len);
            let chain_id = Helpers.bytes_to_felt(items[6].data_len, items[6].data);

            tempvar range_check_ptr = range_check_ptr;
            tempvar is_some = 1;
            tempvar chain_id = chain_id;
        }
        let range_check_ptr = [ap - 3];
        let is_some = [ap - 2];
        let chain_id = [ap - 1];

        tempvar tx = new model.Transaction(
            signer_nonce=nonce,
            gas_limit=gas_limit,
            max_priority_fee_per_gas=gas_price,
            max_fee_per_gas=gas_price,
            destination=destination,
            amount=amount,
            payload_len=payload_len,
            payload=payload,
            access_list_len=0,
            access_list=cast(0, felt*),
            chain_id=model.Option(is_some=is_some, value=chain_id),
        );
        return tx;
    }

    // @notice Decode an Ethereum transaction with optional access list
    // @dev See https://github.com/ethereum/EIPs/blob/master/EIPS/eip-2930.md
    // @param tx_data_len The length of the raw transaction data
    // @param tx_data The raw transaction data
    func decode_2930{bitwise_ptr: BitwiseBuiltin*, range_check_ptr}(
        tx_data_len: felt, tx_data: felt*
    ) -> model.Transaction* {
        alloc_locals;

        let (tx_items: RLP.Item*) = alloc();
        RLP.decode(tx_items, tx_data_len - 1, tx_data + 1);

        assert [tx_items].is_list = TRUE;
        let items_len = [tx_items].data_len;
        let items = cast([tx_items].data, RLP.Item*);

        assert items_len = 8;
        assert items[0].is_list = FALSE;
        assert items[1].is_list = FALSE;
        assert items[2].is_list = FALSE;
        assert items[3].is_list = FALSE;
        assert items[4].is_list = FALSE;
        assert items[5].is_list = FALSE;
        assert items[6].is_list = FALSE;
        assert items[7].is_list = TRUE;

        assert_nn(31 - items[0].data_len);
        let chain_id = Helpers.bytes_to_felt(items[0].data_len, items[0].data);
        assert_nn(31 - items[1].data_len);
        let nonce = Helpers.bytes_to_felt(items[1].data_len, items[1].data);
        assert_nn(31 - items[2].data_len);
        let gas_price = Helpers.bytes_to_felt(items[2].data_len, items[2].data);
        assert_nn(31 - items[3].data_len);
        let gas_limit = Helpers.bytes_to_felt(items[3].data_len, items[3].data);
        let destination = Helpers.try_parse_destination_from_bytes(
            items[4].data_len, items[4].data
        );
        assert_nn(32 - items[5].data_len);
        let amount = Helpers.bytes_to_uint256(items[5].data_len, items[5].data);
        let payload_len = items[6].data_len;
        let payload = items[6].data;

        let (access_list: felt*) = alloc();
        let access_list_len = parse_access_list(
            access_list, items[7].data_len, cast(items[7].data, RLP.Item*)
        );
        tempvar tx = new model.Transaction(
            signer_nonce=nonce,
            gas_limit=gas_limit,
            max_priority_fee_per_gas=gas_price,
            max_fee_per_gas=gas_price,
            destination=destination,
            amount=amount,
            payload_len=payload_len,
            payload=payload,
            access_list_len=access_list_len,
            access_list=access_list,
            chain_id=model.Option(is_some=1, value=chain_id),
        );
        return tx;
    }

    // @notice Decode an Ethereum transaction with fee market
    // @dev See https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1559.md
    // @param tx_data_len The length of the raw transaction data
    // @param tx_data The raw transaction data
    func decode_1559{bitwise_ptr: BitwiseBuiltin*, range_check_ptr}(
        tx_data_len: felt, tx_data: felt*
    ) -> model.Transaction* {
        alloc_locals;

        let (tx_items: RLP.Item*) = alloc();
        RLP.decode(tx_items, tx_data_len - 1, tx_data + 1);

        assert [tx_items].is_list = TRUE;
        let items_len = [tx_items].data_len;
        let items = cast([tx_items].data, RLP.Item*);

        assert items_len = 9;
        assert items[0].is_list = FALSE;
        assert items[1].is_list = FALSE;
        assert items[2].is_list = FALSE;
        assert items[3].is_list = FALSE;
        assert items[4].is_list = FALSE;
        assert items[5].is_list = FALSE;
        assert items[6].is_list = FALSE;
        assert items[7].is_list = FALSE;
        assert items[8].is_list = TRUE;

        assert_nn(31 - items[0].data_len);
        let chain_id = Helpers.bytes_to_felt(items[0].data_len, items[0].data);
        assert_nn(31 - items[1].data_len);
        let nonce = Helpers.bytes_to_felt(items[1].data_len, items[1].data);
        assert_nn(31 - items[2].data_len);
        let max_priority_fee_per_gas = Helpers.bytes_to_felt(items[2].data_len, items[2].data);
        assert_nn(31 - items[3].data_len);
        let max_fee_per_gas = Helpers.bytes_to_felt(items[3].data_len, items[3].data);
        assert_nn(31 - items[4].data_len);
        let gas_limit = Helpers.bytes_to_felt(items[4].data_len, items[4].data);
        let destination = Helpers.try_parse_destination_from_bytes(
            items[5].data_len, items[5].data
        );
        assert_nn(32 - items[6].data_len);
        let amount = Helpers.bytes_to_uint256(items[6].data_len, items[6].data);
        let payload_len = items[7].data_len;
        let payload = items[7].data;
        let (access_list: felt*) = alloc();
        let access_list_len = parse_access_list(
            access_list, items[8].data_len, cast(items[8].data, RLP.Item*)
        );
        tempvar tx = new model.Transaction(
            signer_nonce=nonce,
            gas_limit=gas_limit,
            max_priority_fee_per_gas=max_priority_fee_per_gas,
            max_fee_per_gas=max_fee_per_gas,
            destination=destination,
            amount=amount,
            payload_len=payload_len,
            payload=payload,
            access_list_len=access_list_len,
            access_list=access_list,
            chain_id=model.Option(is_some=1, value=chain_id),
        );
        return tx;
    }

    // @notice Returns the type of a tx, considering that legacy tx are type 0.
    // @dev This function checks if a raw transaction is a legacy Ethereum transaction by checking the transaction type
    // according to EIP-2718. If the transaction type is greater than or equal to 0xc0, it's a legacy transaction.
    // See https://eips.ethereum.org/EIPS/eip-2718#transactiontype-only-goes-up-to-0x7f
    // @param tx_data_len The len of the raw transaction data
    // @param tx_data The raw transaction data
    func get_tx_type{range_check_ptr}(tx_data_len: felt, tx_data: felt*) -> felt {
        with_attr error_message("tx_data_len is zero") {
            assert_not_zero(tx_data_len);
        }

        let type = [tx_data];
        let is_legacy = is_nn(type - 0xc0);
        if (is_legacy != FALSE) {
            return 0;
        }
        return type;
    }

    // @notice Decode a raw Ethereum transaction
    // @param tx_data_len The length of the raw transaction data
    // @param tx_data The raw transaction data
    func decode{bitwise_ptr: BitwiseBuiltin*, range_check_ptr}(
        tx_data_len: felt, tx_data: felt*
    ) -> model.Transaction* {
        let tx_type = get_tx_type(tx_data_len, tx_data);
        let is_supported = is_nn(2 - tx_type);
        with_attr error_message("Kakarot: transaction type not supported") {
            assert is_supported = TRUE;
        }
        tempvar offset = 1 + 3 * tx_type;

        [ap] = bitwise_ptr, ap++;
        [ap] = range_check_ptr, ap++;
        [ap] = tx_data_len, ap++;
        [ap] = tx_data, ap++;
        jmp rel offset;
        call decode_legacy_tx;
        ret;
        call decode_2930;
        ret;
        call decode_1559;
        ret;
    }

    // @notice Recursively parses the RLP-decoded access list.
    // @dev the parsed format is [address, storage_keys_len, *[storage_keys], address, storage_keys_len, *[storage_keys]]
    // where keys_len is the number of storage keys, and each storage key takes 2 felts.
    // @param parsed_list The pointer to the next free cell in the parsed access list.
    // @param list_len The remaining length of the RLP-decoded access list to parse.
    // @param list_items The pointer to the current RLP-decoded access list item to parse.
    // @return The length of the serialized access list, expressed in total amount of felts in the list.
    func parse_access_list{range_check_ptr}(
        parsed_list: felt*, access_list_len: felt, access_list: RLP.Item*
    ) -> felt {
        alloc_locals;
        if (access_list_len == 0) {
            return 0;
        }

        // Address
        let address_item = cast(access_list.data, RLP.Item*);
        with_attr error_message("Invalid address length") {
            assert [range_check_ptr] = address_item.data_len - 20;
        }
        let range_check_ptr = range_check_ptr + 1;
        let address = Helpers.bytes20_to_felt(address_item.data);

        // List<StorageKeys>
        let keys_item = cast(access_list.data + RLP.Item.SIZE, RLP.Item*);
        let keys_len = keys_item.data_len;
        assert [parsed_list] = address;
        assert [parsed_list + 1] = keys_len;

        let keys = cast(keys_item.data, RLP.Item*);
        parse_storage_keys(parsed_list + 2, keys_len, keys);

        let serialized_len = parse_access_list(
            parsed_list + 2 + keys_len * Uint256.SIZE,
            access_list_len - 1,
            access_list + RLP.Item.SIZE,
        );
        return serialized_len + 2 + keys_len * Uint256.SIZE;
    }

    // @notice Recursively parses the RLP-decoded storage keys list of an address
    // and returns an array containing the parsed storage keys.
    // @dev the keys are stored in the parsed format [key_low, key_high, key_low, key_high]
    // @param parsed_keys The pointer to the next free cell in the parsed access list array.
    // @param keys_list_len The remaining length of the RLP-decoded storage keys list to parse.
    // @param keys_list The pointer to the current RLP-decoded storage keys list item to parse.
    func parse_storage_keys{range_check_ptr}(
        parsed_keys: felt*, keys_list_len: felt, keys_list: RLP.Item*
    ) {
        alloc_locals;
        if (keys_list_len == 0) {
            return ();
        }

        with_attr error_message("Invalid storage key length") {
            assert [range_check_ptr] = keys_list.data_len - 32;
        }
        let range_check_ptr = range_check_ptr + 1;

        let key = Helpers.bytes32_to_uint256(keys_list.data);
        assert [parsed_keys] = key.low;
        assert [parsed_keys + 1] = key.high;

        parse_storage_keys(
            parsed_keys + Uint256.SIZE, keys_list_len - 1, keys_list + RLP.Item.SIZE
        );
        return ();
    }

    // @notice Validate an Ethereum transaction and execute it.
    // @dev This function validates the transaction by checking its signature,
    // chain_id, nonce and gas. It then sends it to Kakarot.
    // @param tx_data_len The length of tx data
    // @param tx_data The tx data.
    // @param signature_len The length of tx signature.
    // @param signature The tx signature.
    // @param chain_id The expected chain id of the tx
    func validate{
        pedersen_ptr: HashBuiltin*,
        bitwise_ptr: BitwiseBuiltin*,
        range_check_ptr,
        range_check96_ptr: felt*,
        add_mod_ptr: ModBuiltin*,
        mul_mod_ptr: ModBuiltin*,
        poseidon_ptr: PoseidonBuiltin*,
        keccak_ptr: KeccakBuiltin*,
    }(tx: model.TransactionEncoded*, chain_id: felt) {
        alloc_locals;

        with_attr error_message("Incorrect signature length") {
            assert tx.signature_len = 5;
        }

        with_attr error_message("Signatures values not in range") {
            assert [range_check_ptr] = tx.signature[0];
            assert [range_check_ptr + 1] = tx.signature[1];
            assert [range_check_ptr + 2] = tx.signature[2];
            assert [range_check_ptr + 3] = tx.signature[3];
            assert [range_check_ptr + 4] = tx.signature[4];
            let range_check_ptr = range_check_ptr + 5;
        }

        let r = Uint256(tx.signature[0], tx.signature[1]);
        let s = Uint256(tx.signature[2], tx.signature[3]);
        let v = tx.signature[4];

        let tx_type = get_tx_type(tx.rlp_len, tx.rlp);
        local y_parity: felt;
        local pre_eip155_tx: felt;
        if (tx_type == 0) {
            let is_eip155_tx = is_nn(28 - v);
            assert pre_eip155_tx = is_eip155_tx;
            if (is_eip155_tx != FALSE) {
                assert y_parity = v - 27;
            } else {
                assert y_parity = (v - 2 * chain_id - 35);
            }
            tempvar range_check_ptr = range_check_ptr;
        } else {
            assert pre_eip155_tx = FALSE;
            assert y_parity = v;
            tempvar range_check_ptr = range_check_ptr;
        }
        let range_check_ptr = [ap - 1];

        // Signature validation
        // `verify_eth_signature_uint256` verifies that r and s are in the range [1, N[
        // TX validation imposes s to be the range [1, N//2], see EIP-2
        let (is_invalid_upper_s) = uint256_lt(
            Uint256(SECP256K1N_DIV_2_LOW, SECP256K1N_DIV_2_HIGH), s
        );
        with_attr error_message("Invalid s value") {
            assert is_invalid_upper_s = FALSE;
        }

        let msg_hash = keccak(tx.rlp_len, tx.rlp);

        Signature.verify_eth_signature_uint256(
            msg_hash=msg_hash, r=r, s=s, y_parity=y_parity, eth_address=tx.sender
        );

        return ();
    }
}
