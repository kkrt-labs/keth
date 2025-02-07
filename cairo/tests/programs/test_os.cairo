from starkware.cairo.common.dict import dict_read
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.cairo_builtins import (
    HashBuiltin,
    BitwiseBuiltin,
    KeccakBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
)
from starkware.cairo.common.memcpy import memcpy

from programs.os import os
from src.model import model
from src.account import Internals, Account
from src.state import State
from legacy.utils.transaction import Transaction

func test_os{
    output_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    ec_op_ptr,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}() -> model.State* {
    return os();
}

func test_recover_signer{
    output_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    ec_op_ptr,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}() {
    alloc_locals;
    local block: model.Block*;
    local chain_id: felt;
    %{ block %}
    %{ chain_id %}

    with chain_id {
        validate_transactions(block.transactions_len, block.transactions);
    }
    return ();
}

func validate_transactions{
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    range_check_ptr,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    chain_id: felt,
}(txs_len: felt, tx_encoded: model.TransactionEncoded*) {
    %{
        logger.info(f"txs_len: {ids.txs_len}")
        logger.info(f"current_step: {current_step}")
    %}

    if (txs_len == 0) {
        return ();
    }

    Transaction.validate(tx_encoded, chain_id);

    return validate_transactions(txs_len - 1, tx_encoded + model.TransactionEncoded.SIZE);
}

func test_block_hint{output_ptr: felt*}() {
    alloc_locals;
    local block: model.Block*;
    %{ block %}

    // Serialize block header
    assert [output_ptr] = block.block_header.parent_hash.low;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.parent_hash.high;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.ommers_hash.low;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.ommers_hash.high;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.coinbase;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.state_root.low;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.state_root.high;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.transactions_root.low;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.transactions_root.high;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.receipt_root.low;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.receipt_root.high;
    let output_ptr = output_ptr + 1;

    // Serialize withdrawals root
    assert [output_ptr] = block.block_header.withdrawals_root.is_some;
    let output_ptr = output_ptr + 1;
    let withdrawals_root = cast(block.block_header.withdrawals_root.value, Uint256*);
    assert [output_ptr] = withdrawals_root.low;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = withdrawals_root.high;
    let output_ptr = output_ptr + 1;

    // Bloom: 256-byte array into groups of 16 bytes chunks (16 * 16 = 256)
    tempvar bloom_len = 16;
    memcpy(output_ptr, block.block_header.bloom, bloom_len);
    let output_ptr = output_ptr + bloom_len;

    assert [output_ptr] = block.block_header.difficulty.low;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.difficulty.high;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.number;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.gas_limit;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.gas_used;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.timestamp;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.mix_hash.low;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.mix_hash.high;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.nonce;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.base_fee_per_gas.is_some;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.base_fee_per_gas.value;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.blob_gas_used.is_some;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.blob_gas_used.value;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.excess_blob_gas.is_some;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = block.block_header.excess_blob_gas.value;
    let output_ptr = output_ptr + 1;

    // Serialize parent beacon block root
    assert [output_ptr] = block.block_header.parent_beacon_block_root.is_some;
    let output_ptr = output_ptr + 1;
    let parent_beacon_block_root = cast(
        block.block_header.parent_beacon_block_root.value, Uint256*
    );
    assert [output_ptr] = parent_beacon_block_root.low;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = parent_beacon_block_root.high;
    let output_ptr = output_ptr + 1;

    // Serialize requests root
    assert [output_ptr] = block.block_header.requests_root.is_some;
    let output_ptr = output_ptr + 1;
    let requests_root = cast(block.block_header.requests_root.value, Uint256*);
    assert [output_ptr] = requests_root.low;
    let output_ptr = output_ptr + 1;
    assert [output_ptr] = requests_root.high;
    let output_ptr = output_ptr + 1;

    // Serialize the extra data
    assert [output_ptr] = block.block_header.extra_data_len;
    let output_ptr = output_ptr + 1;
    memcpy(output_ptr, block.block_header.extra_data, block.block_header.extra_data_len);
    let output_ptr = output_ptr + block.block_header.extra_data_len;

    // Serialize transactions
    assert [output_ptr] = block.transactions_len;
    let output_ptr = output_ptr + 1;

    if (block.transactions_len == 0) {
        return ();
    }

    // Serialize the first transaction only for testing purposes
    assert [output_ptr] = block.transactions[0].rlp_len;
    let output_ptr = output_ptr + 1;
    memcpy(output_ptr, block.transactions[0].rlp, block.transactions[0].rlp_len);
    let output_ptr = output_ptr + block.transactions[0].rlp_len;
    assert [output_ptr] = block.transactions[0].signature_len;
    let output_ptr = output_ptr + 1;
    memcpy(output_ptr, block.transactions[0].signature, block.transactions[0].signature_len);
    let output_ptr = output_ptr + block.transactions[0].signature_len;
    assert [output_ptr] = block.transactions[0].sender;
    let output_ptr = output_ptr + 1;

    return ();
}
