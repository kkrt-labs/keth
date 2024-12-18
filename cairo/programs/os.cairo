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
from starkware.cairo.common.math_cmp import is_not_zero
from starkware.cairo.common.uint256 import Uint256

from src.model import model
from src.utils.transaction import Transaction
from src.state import State
from src.instructions.system_operations import CreateHelper
from src.interpreter import Interpreter

func os{
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
    alloc_locals;
    %{ dict_manager %}
    local block: model.Block*;
    local state: model.State*;
    local chain_id: felt;
    local block_hashes: Uint256*;
    %{ block %}
    // TODO: Validate header
    %{ state %}
    // TODO: Compute initial state root hash and compare with block.parent_hash
    %{ chain_id %}
    %{ block_hashes %}

    let header = block.block_header;
    with header, chain_id, state, block_hashes {
        apply_transactions(block.transactions_len, block.transactions);
    }

    state_root:
    // TODO: Compute the state root hash after applying all transactions

    // TODO: Compare the final state root hash with block.state_root
    end:
    return state;
}

func apply_transactions{
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    range_check_ptr,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    header: model.BlockHeader*,
    block_hashes: Uint256*,
    chain_id: felt,
    state: model.State*,
}(txs_len: felt, tx_encoded: model.TransactionEncoded*) {
    alloc_locals;
    %{
        logger.info(f"txs_len: {ids.txs_len}")
        logger.info(f"current_step: {current_step}")
    %}

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
        assert_le(tx.signer_nonce, 2 ** 64 - 2);
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
        assert_nn(tx.max_fee_per_gas - header.base_fee_per_gas.value);
    }

    with_attr error_message("Max priority fee greater than max fee per gas") {
        assert [range_check_ptr] = tx.max_priority_fee_per_gas;
        let range_check_ptr = range_check_ptr + 1;
        assert_le(tx.max_priority_fee_per_gas, tx.max_fee_per_gas);
    }

    let is_regular_tx = is_not_zero(tx.destination.is_some);

    let is_deploy_tx = 1 - is_regular_tx;
    let evm_contract_address = resolve_to(tx.destination, tx_encoded.sender, tx.signer_nonce);
    let code_account = State.get_account(evm_contract_address);
    tempvar env = new model.Environment(
        origin=tx_encoded.sender,
        gas_price=tx.max_fee_per_gas,
        chain_id=chain_id,
        prev_randao=header.mix_hash,
        block_number=header.number,
        block_gas_limit=header.gas_limit,
        block_timestamp=header.timestamp,
        coinbase=header.coinbase,
        base_fee=header.base_fee_per_gas.value,
        block_hashes=block_hashes,
        excess_blob_gas=header.excess_blob_gas,
    );

    Interpreter.execute(
        env,
        evm_contract_address,
        is_deploy_tx,
        code_account.code_len,
        code_account.code,
        tx.payload_len,
        tx.payload,
        &tx.amount,
        tx.gas_limit,
        tx.access_list_len,
        tx.access_list,
    );

    return apply_transactions(txs_len - 1, tx_encoded + model.TransactionEncoded.SIZE);
}

// @notice Get the EVM address from the transaction
// @dev When to=None, it's a deploy tx so we first compute the target address
// @param to The transaction to parameter
// @param origin The transaction origin parameter
// @param nonce The transaction nonce parameter, used to compute the target address if it's a deploy tx
// @return the target evm address
func resolve_to{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}(to: model.Option, origin: felt, nonce: felt) -> felt {
    alloc_locals;
    if (to.is_some != 0) {
        return to.value;
    }
    let (local evm_contract_address) = CreateHelper.get_create_address(origin, nonce);
    return evm_contract_address;
}

// @notice The main function for the os program
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
    os();

    return ();
}
