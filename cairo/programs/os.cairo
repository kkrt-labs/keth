%builtins output pedersen range_check ecdsa bitwise ec_op keccak poseidon range_check96 add_mod mul_mod

from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.cairo_builtins import (
    HashBuiltin,
    BitwiseBuiltin,
    KeccakBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
)
from starkware.cairo.common.math import assert_le, assert_nn
from starkware.cairo.common.bool import FALSE

from src.model import model
from src.utils.transaction import Transaction
from src.state import State

func main{
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
    %{ dict_manager %}
    local block: model.Block*;
    local state: model.State*;
    local chain_id: felt;
    %{ block %}
    %{ state %}
    %{ chain_id %}
    // TODO: Compute initial state root hash and compare with block.parent_hash
    // TODO: Loop through transactions and apply them to the initial state

    let header = block.block_header;
    assert [range_check_ptr] = header.gas_limit;
    assert [range_check_ptr + 1] = header.gas_used;
    assert [range_check_ptr + 2] = header.base_fee_per_gas;
    let range_check_ptr = range_check_ptr + 3;

    with header, chain_id, state {
        apply_transactions(block.transactions_len, block.transactions);
    }

    state_root:
    // TODO: Compute the state root hash after applying all transactions

    // TODO: Compare the final state root hash with block.state_root
    end:
    return ();
}

func apply_transactions{
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    range_check_ptr,
    keccak_ptr: KeccakBuiltin*,
    header: model.BlockHeader*,
    chain_id: felt,
    state: model.State*,
}(txs_len: felt, tx_encoded: model.TransactionEncoded*) {
    alloc_locals;
    if (txs_len == 0) {
        return ();
    }

    Transaction.validate(tx_encoded, chain_id);
    let tx = Transaction.decode(tx_encoded.rlp_len, tx_encoded.rlp);

    // Validate chain_id for post eip155
    if (tx.chain_id.is_some != FALSE) {
        with_attr error_message("Invalid chain id") {
            assert tx.chain_id.value = chain_id;
        }
    }

    let account = State.get_account(tx_encoded.sender);

    // Validate nonce
    with_attr error_message("Invalid nonce") {
        assert tx.signer_nonce = account.nonce;
    }

    // Validate gas
    with_attr error_message("Gas limit too high") {
        assert [range_check_ptr] = tx.gas_limit;
        let range_check_ptr = range_check_ptr + 1;
        assert_le(tx.gas_limit, 2 ** 64 - 1);
    }

    with_attr error_message("Max fee per gas too high") {
        assert [range_check_ptr] = tx.max_fee_per_gas;
        let range_check_ptr = range_check_ptr + 1;
    }

    with_attr error_message("Transaction gas_limit > Block gas_limit") {
        assert_nn(header.gas_limit - tx.gas_limit);
    }

    with_attr error_message("Max fee per gas too low") {
        assert_nn(tx.max_fee_per_gas - header.base_fee_per_gas);
    }

    with_attr error_message("Max priority fee greater than max fee per gas") {
        assert [range_check_ptr] = tx.max_priority_fee_per_gas;
        let range_check_ptr = range_check_ptr + 1;
        assert_le(tx.max_priority_fee_per_gas, tx.max_fee_per_gas);
    }

    return apply_transactions(txs_len - 1, tx_encoded + model.TransactionEncoded.SIZE);
}
