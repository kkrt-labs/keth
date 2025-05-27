// Requests were introduced in EIP-7685 as a a general purpose framework for
// storing contract-triggered requests. It extends the execution header and
// body with a single field each to store the request information.
// This inherently exposes the requests to the consensus layer, which can
// then process each one.

// [EIP-7685]: https://eips.ethereum.org/EIPS/eip-7685

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.registers import get_label_location
from ethereum_rlp.rlp import decode_to_receipt
from starkware.cairo.common.math import assert_not_zero, assert_le
from ethereum.prague.blocks import UnionBytesReceipt, Receipt, TupleLog

from cairo_core.bytes import Bytes, BytesStruct, Bytes32, Bytes32Struct, ListBytes
from ethereum.prague.trie import (
    trie_get_TrieBytesOptionalUnionBytesReceipt,
    TrieBytesOptionalUnionBytesReceipt,
)
from ethereum.prague.vm import BlockOutput, BlockOutputStruct
from ethereum.utils.bytes import Bytes_to_Bytes32, Bytes__extend__
from ethereum.utils.numeric import U256_from_be_bytes
from cairo_core.hash.sha256 import EMPTY_SHA256, sha256_bytes
from ethereum.crypto.hash import Hash32
from cairo_core.control_flow import raise

// Constants
const DEPOSIT_CONTRACT_ADDRESS = 0xfa05773d3005be9c83bb6c3540b59a2100000000;
const DEPOSIT_EVENT_SIGNATURE_HASH_LOW = 0x49402dd85c4eeaaf4213e3d062bc9b64;
const DEPOSIT_EVENT_SIGNATURE_HASH_HIGH = 0xc53890e33b8090a79a88c02f91eee1e7;

const DEPOSIT_REQUEST_TYPE = 0x00;
const WITHDRAWAL_REQUEST_TYPE = 0x01;
const CONSOLIDATION_REQUEST_TYPE = 0x02;

const DEPOSIT_EVENT_LENGTH = 576;

const PUBKEY_OFFSET = 160;
const WITHDRAWAL_CREDENTIALS_OFFSET = 256;
const AMOUNT_OFFSET = 320;
const SIGNATURE_OFFSET = 384;
const INDEX_OFFSET = 512;

const PUBKEY_SIZE = 48;
const WITHDRAWAL_CREDENTIALS_SIZE = 32;
const AMOUNT_SIZE = 8;
const SIGNATURE_SIZE = 96;
const INDEX_SIZE = 8;

// @notice Extracts Deposit Request from the DepositContract.DepositEvent data.
// @param data The event data to extract from
// @return The extracted deposit data as bytes, or null if invalid
func extract_deposit_data{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(data: Bytes) -> Bytes {
    alloc_locals;

    // Check data length
    if (data.value.len != DEPOSIT_EVENT_LENGTH) {
        raise('InvalidBlock');
    }

    // Check that all the offsets are in order
    tempvar pubkey_bytes = Bytes(new BytesStruct(data.value.data, 32));
    let pubkey_offset_u256 = U256_from_be_bytes(pubkey_bytes);
    assert pubkey_offset_u256.value.high = 0;
    let pubkey_offset = pubkey_offset_u256.value.low;
    if (pubkey_offset != PUBKEY_OFFSET) {
        raise('InvalidBlock');
    }

    tempvar withdrawal_credentials_bytes = Bytes(new BytesStruct(data.value.data + 32, 32));
    let withdrawal_credentials_offset_u256 = U256_from_be_bytes(withdrawal_credentials_bytes);
    assert withdrawal_credentials_offset_u256.value.high = 0;
    let withdrawal_credentials_offset = withdrawal_credentials_offset_u256.value.low;
    if (withdrawal_credentials_offset != WITHDRAWAL_CREDENTIALS_OFFSET) {
        raise('InvalidBlock');
    }

    tempvar amount_bytes = Bytes(new BytesStruct(data.value.data + 64, 32));
    let amount_offset_u256 = U256_from_be_bytes(amount_bytes);
    assert amount_offset_u256.value.high = 0;
    let amount_offset = amount_offset_u256.value.low;
    if (amount_offset != AMOUNT_OFFSET) {
        raise('InvalidBlock');
    }

    tempvar signature_bytes = Bytes(new BytesStruct(data.value.data + 96, 32));
    let signature_offset_u256 = U256_from_be_bytes(signature_bytes);
    assert signature_offset_u256.value.high = 0;
    let signature_offset = signature_offset_u256.value.low;
    if (signature_offset != SIGNATURE_OFFSET) {
        raise('InvalidBlock');
    }

    tempvar index_bytes = Bytes(new BytesStruct(data.value.data + 128, 32));
    let index_offset_u256 = U256_from_be_bytes(index_bytes);
    assert index_offset_u256.value.high = 0;
    let index_offset = index_offset_u256.value.low;
    if (index_offset != INDEX_OFFSET) {
        raise('InvalidBlock');
    }

    // Check that all the sizes are in order
    tempvar pubkey_size_bytes = Bytes(new BytesStruct(data.value.data + PUBKEY_OFFSET, 32));
    let pubkey_size_u256 = U256_from_be_bytes(pubkey_size_bytes);
    assert pubkey_size_u256.value.high = 0;
    let pubkey_size = pubkey_size_u256.value.low;
    if (pubkey_size != PUBKEY_SIZE) {
        raise('InvalidBlock');
    }
    tempvar pubkey = Bytes(new BytesStruct(data.value.data + PUBKEY_OFFSET + 32, pubkey_size));

    tempvar withdrawal_credentials_size_bytes = Bytes(
        new BytesStruct(data.value.data + WITHDRAWAL_CREDENTIALS_OFFSET, 32)
    );
    let withdrawal_credentials_size_u256 = U256_from_be_bytes(withdrawal_credentials_size_bytes);
    assert withdrawal_credentials_size_u256.value.high = 0;
    let withdrawal_credentials_size = withdrawal_credentials_size_u256.value.low;
    if (withdrawal_credentials_size != WITHDRAWAL_CREDENTIALS_SIZE) {
        raise('InvalidBlock');
    }
    tempvar withdrawal_credentials = Bytes(
        new BytesStruct(
            data.value.data + WITHDRAWAL_CREDENTIALS_OFFSET + 32, withdrawal_credentials_size
        ),
    );

    tempvar amount_size_bytes = Bytes(new BytesStruct(data.value.data + AMOUNT_OFFSET, 32));
    let amount_size_u256 = U256_from_be_bytes(amount_size_bytes);
    assert amount_size_u256.value.high = 0;
    let amount_size = amount_size_u256.value.low;
    if (amount_size != AMOUNT_SIZE) {
        raise('InvalidBlock');
    }
    tempvar amount = Bytes(new BytesStruct(data.value.data + AMOUNT_OFFSET + 32, amount_size));

    tempvar signature_size_bytes = Bytes(new BytesStruct(data.value.data + SIGNATURE_OFFSET, 32));
    let signature_size_u256 = U256_from_be_bytes(signature_size_bytes);
    assert signature_size_u256.value.high = 0;
    let signature_size = signature_size_u256.value.low;
    if (signature_size != SIGNATURE_SIZE) {
        raise('InvalidBlock');
    }
    tempvar signature = Bytes(
        new BytesStruct(data.value.data + SIGNATURE_OFFSET + 32, signature_size)
    );

    tempvar index_size_bytes = Bytes(new BytesStruct(data.value.data + INDEX_OFFSET, 32));
    let index_size_u256 = U256_from_be_bytes(index_size_bytes);
    assert index_size_u256.value.high = 0;
    let index_size = index_size_u256.value.low;
    if (index_size != INDEX_SIZE) {
        raise('InvalidBlock');
    }
    tempvar index = Bytes(new BytesStruct(data.value.data + INDEX_OFFSET + 32, index_size));

    // Extract the actual data
    let (result_bytes_start: felt*) = alloc();
    let result_bytes = result_bytes_start;
    let total_size = PUBKEY_SIZE + WITHDRAWAL_CREDENTIALS_SIZE + AMOUNT_SIZE + SIGNATURE_SIZE +
        INDEX_SIZE;

    // Copy pubkey
    memcpy(result_bytes, pubkey.value.data, pubkey.value.len);
    let result_bytes = result_bytes + pubkey.value.len;

    // Copy withdrawal credentials
    memcpy(result_bytes, withdrawal_credentials.value.data, withdrawal_credentials.value.len);
    let result_bytes = result_bytes + withdrawal_credentials.value.len;

    // Copy amount
    memcpy(result_bytes, amount.value.data, amount.value.len);
    let result_bytes = result_bytes + amount.value.len;

    // Copy signature
    memcpy(result_bytes, signature.value.data, signature.value.len);
    let result_bytes = result_bytes + signature.value.len;

    // Copy index
    memcpy(result_bytes, index.value.data, index.value.len);

    tempvar result = Bytes(new BytesStruct(result_bytes_start, total_size));
    return result;
}

// @notice Parse deposit requests from the block output.
// @param block_output The block output containing receipts
// @return The concatenated deposit requests as bytes
func parse_deposit_requests{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, block_output: BlockOutput
}() -> Bytes {
    alloc_locals;

    let (deposit_requests_data: felt*) = alloc();
    let receipts_trie = block_output.value.receipts_trie;
    let deposit_requests_len = _parse_deposit_requests_inner{receipts_trie=receipts_trie}(
        block_output, 0, deposit_requests_data, 0
    );

    tempvar block_output = BlockOutput(
        new BlockOutputStruct(
            block_gas_used=block_output.value.block_gas_used,
            transactions_trie=block_output.value.transactions_trie,
            receipts_trie=receipts_trie,
            receipt_keys=block_output.value.receipt_keys,
            block_logs=block_output.value.block_logs,
            withdrawals_trie=block_output.value.withdrawals_trie,
            blob_gas_used=block_output.value.blob_gas_used,
            requests=block_output.value.requests,
        ),
    );

    tempvar deposit_requests = Bytes(new BytesStruct(deposit_requests_data, deposit_requests_len));
    return deposit_requests;
}

// @notice Inner recursive function to parse deposit requests
// @param block_output The block output containing receipts
// @param key_index Current index in receipt_keys
// @param deposit_requests_data Buffer to store results
// @param current_len Current length of accumulated data
// @return Total length of deposit requests data
func _parse_deposit_requests_inner{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, receipts_trie: TrieBytesOptionalUnionBytesReceipt
}(
    block_output: BlockOutput, key_index: felt, deposit_requests_data: felt*, current_len: felt
) -> felt {
    alloc_locals;

    if (key_index == block_output.value.receipt_keys.value.len) {
        return current_len;
    }

    let key = block_output.value.receipt_keys.value.data[key_index];
    let receipt_bytes = trie_get_TrieBytesOptionalUnionBytesReceipt{trie=receipts_trie}(key);

    // Check if receipt exists
    if (cast(receipt_bytes.value, felt) == 0) {
        raise('AssertionError');
    }

    let decoded_receipt = decode_receipt(UnionBytesReceipt(receipt_bytes.value));
    let new_len = _process_receipt_logs(
        decoded_receipt.value.logs, 0, deposit_requests_data, current_len
    );

    return _parse_deposit_requests_inner(
        block_output, key_index + 1, deposit_requests_data, new_len
    );
}

// @notice Process logs from a receipt to find deposit events
// @param logs The logs from the receipt
// @param log_index Current log index
// @param deposit_requests_data Buffer to store results
// @param current_len Current length of accumulated data
// @return Updated length after processing logs
func _process_receipt_logs{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    logs: TupleLog, log_index: felt, deposit_requests_data: felt*, current_len: felt
) -> felt {
    alloc_locals;

    if (log_index == logs.value.len) {
        return current_len;
    }

    let log = logs.value.data[log_index];

    // Check if this is from the deposit contract
    if (log.value.address.value != DEPOSIT_CONTRACT_ADDRESS) {
        return _process_receipt_logs(logs, log_index + 1, deposit_requests_data, current_len);
    }

    // Check if log has topics and first topic matches deposit event signature
    if (log.value.topics.value.len == 0) {
        return _process_receipt_logs(logs, log_index + 1, deposit_requests_data, current_len);
    }

    let first_topic = log.value.topics.value.data[0];
    if (first_topic.value.low == DEPOSIT_EVENT_SIGNATURE_HASH_LOW and
        first_topic.value.high == DEPOSIT_EVENT_SIGNATURE_HASH_HIGH) {
        // Extract deposit data
        let request = extract_deposit_data(log.value.data);

        // Copy the request data to our buffer
        memcpy(deposit_requests_data + current_len, request.value.data, request.value.len);
        let new_len = current_len + request.value.len;
        return _process_receipt_logs(logs, log_index + 1, deposit_requests_data, new_len);
    }

    return _process_receipt_logs(logs, log_index + 1, deposit_requests_data, current_len);
}

// @notice Get the hash of the requests using the SHA2-256 algorithm.
// @param requests The requests to hash
// @param requests_len Number of requests
// @return The hash of the requests
func compute_requests_hash{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    requests: ListBytes
) -> Hash32 {
    alloc_locals;

    let (empty_sha256) = get_label_location(EMPTY_SHA256);
    let empty_sha256_b32 = Bytes32(cast(empty_sha256, Bytes32Struct*));
    if (requests.value.len == 0) {
        return empty_sha256_b32;
    }

    let (sha256_state_data) = alloc();
    tempvar sha256_state = Bytes(new BytesStruct(sha256_state_data, 0));
    _acc_requests_inner{sha256_state=sha256_state}(requests.value.data, requests.value.len, 0);

    let digest = sha256_bytes(sha256_state);
    let result = Bytes_to_Bytes32(digest);
    return result;
}

// @notice Inner function to hash each request and add to sha256 input
// @param requests Array of requests
// @param requests_len Total number of requests
// @param index Current index
func _acc_requests_inner{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, sha256_state: Bytes}(
    requests: Bytes*, requests_len: felt, index: felt
) {
    alloc_locals;
    if (index == requests_len) {
        return ();
    }

    let request = requests[index];
    let request_hash = sha256_bytes(request);
    Bytes__extend__{self=sha256_state}(request_hash);

    return _acc_requests_inner(requests, requests_len, index + 1);
}

// @notice Decodes a receipt
func decode_receipt{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    receipt: UnionBytesReceipt
) -> Receipt {
    alloc_locals;
    if (cast(receipt.value.bytes.value, felt) != 0) {
        // First bytes is the tx type
        let input_bytes = receipt.value.bytes;
        assert_not_zero(input_bytes.value.data[0]);
        assert_le(input_bytes.value.data[0], 4);

        tempvar receipt_bytes = Bytes(
            new BytesStruct(input_bytes.value.data + 1, input_bytes.value.len - 1)
        );
        let decoded_receipt = decode_to_receipt(receipt_bytes);
        return decoded_receipt;
    }

    return receipt.value.receipt;
}
