%builtins output pedersen range_check ecdsa bitwise ec_op keccak poseidon range_check96 add_mod mul_mod

from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.cairo_builtins import (
    HashBuiltin,
    BitwiseBuiltin,
    KeccakBuiltin,
    PoseidonBuiltin,
    ModBuiltin,
)
from starkware.cairo.common.math import assert_le, assert_nn, split_felt
from starkware.cairo.common.math_cmp import is_nn, is_not_zero
from starkware.cairo.common.bool import FALSE, TRUE
from starkware.cairo.common.uint256 import Uint256, uint256_le

from src.instructions.system_operations import CreateHelper
from src.model import model
from src.utils.transaction import Transaction
from src.state import State
from src.utils.uint256 import uint256_add
from src.utils.array import count_not_zero
from src.interpreter import Interpreter
from src.utils.maths import unsigned_div_rem
from src.gas import Gas
from src.utils.utils import Helpers

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
    %{ block %}
    %{ state %}
    %{ chain_id %}
    // TODO: Compute initial state root hash and compare with block.parent_hash
    // TODO: Loop through transactions and apply them to the initial state

    let header = block.block_header;
    assert [range_check_ptr] = header.gas_limit;
    assert [range_check_ptr + 1] = header.gas_used;
    assert [range_check_ptr + 2] = header.base_fee_per_gas.value;
    let range_check_ptr = range_check_ptr + 3;

    with header, chain_id, state {
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

    let sender = State.get_account(tx_encoded.sender);

    // Validate nonce
    with_attr error_message("Invalid nonce") {
        assert tx.signer_nonce = sender.nonce;
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

    let max_gas_fee = tx.gas_limit * tx.max_fee_per_gas;
    let (max_fee_high, max_fee_low) = split_felt(max_gas_fee);
    let (tx_cost, carry) = uint256_add(tx.amount, Uint256(low=max_fee_low, high=max_fee_high));
    assert carry = 0;
    let (is_balance_enough) = uint256_le(tx_cost, [sender.balance]);
    with_attr error_message("Not enough ETH to pay msg.value + max gas fees") {
        assert is_balance_enough = TRUE;
    }

    let possible_priority_fee = tx.max_fee_per_gas - header.base_fee_per_gas.value;
    let priority_fee_is_max_priority_fee = is_nn(
        possible_priority_fee - tx.max_priority_fee_per_gas
    );
    let priority_fee_per_gas = priority_fee_is_max_priority_fee * tx.max_priority_fee_per_gas + (
        1 - priority_fee_is_max_priority_fee
    ) * possible_priority_fee;
    let effective_gas_price = priority_fee_per_gas + header.base_fee_per_gas.value;

    // Compute intrinsic gas usage
    // See https://www.evm.codes/about#gascosts
    let calldata_len = tx.payload_len;
    let calldata = tx.payload;
    let count = count_not_zero(calldata_len, calldata);
    let zeroes = calldata_len - count;
    let calldata_gas = zeroes * 4 + count * 16;
    tempvar intrinsic_gas = Gas.TX_BASE_COST + calldata_gas;

    // If tx.destination.is_some is FALSE, then it's a deploy tx and bytecode is data and data is empty
    if (tx.destination.is_some != FALSE) {
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar keccak_ptr = keccak_ptr;
        tempvar to = tx.destination.value;
        tempvar intrinsic_gas = intrinsic_gas;
    } else {
        let (init_code_words, _) = unsigned_div_rem(calldata_len + 31, 32);
        let init_code_gas = Gas.INIT_CODE_WORD_COST * init_code_words;
        tempvar create_gas = Gas.CREATE + init_code_gas;
        let (to) = CreateHelper.get_create_address(tx_encoded.sender, sender.nonce);
        tempvar intrinsic_gas = intrinsic_gas + create_gas;
        static_assert range_check_ptr == [ap - 5];
        static_assert bitwise_ptr == [ap - 4];
        static_assert keccak_ptr == [ap - 3];
        static_assert to == [ap - 2];
        static_assert intrinsic_gas == [ap - 1];
    }
    let range_check_ptr = [ap - 5];
    let bitwise_ptr = cast([ap - 4], BitwiseBuiltin*);
    let keccak_ptr = cast([ap - 3], KeccakBuiltin*);
    let to = [ap - 2];
    let intrinsic_gas = [ap - 1];
    let destination = State.get_account(to);
    if (tx.destination.is_some != FALSE) {
        tempvar bytecode_len = destination.code_len;
        tempvar bytecode = destination.code;
        tempvar calldata_len = calldata_len;
    } else {
        tempvar bytecode_len = calldata_len;
        tempvar bytecode = calldata;
        tempvar calldata_len = 0;
    }
    let bytecode_len = [ap - 3];
    let bytecode = cast([ap - 2], felt*);
    let calldata_len = [ap - 1];

    // TODO: Investigate how this could be cached
    let (valid_jumpdests_start, valid_jumpdests) = Helpers.initialize_jumpdests(
        bytecode_len=bytecode_len, bytecode=bytecode
    );

    tempvar env = new model.Environment(
        origin=tx_encoded.sender,
        gas_price=effective_gas_price,
        chain_id=chain_id,
        prev_randao=header.mix_hash,
        block_number=header.number,
        block_gas_limit=header.gas_limit,
        block_timestamp=header.timestamp,
        coinbase=header.coinbase,
        base_fee=header.base_fee_per_gas.value,
    );

    // Storing the initial state in the Parent struct to be able to check what was the state
    // before the transaction is applied
    tempvar parent = new model.Parent(
        evm=cast(0, model.EVM*),
        stack=cast(0, model.Stack*),
        memory=cast(0, model.Memory*),
        state=state,
    );

    // FIXME: need to update default_dict_new since it's now initialized with non-default values
    // let state = State.copy();

    let code_address = tx.destination.is_some * tx.destination.value;
    tempvar message = new model.Message(
        bytecode=bytecode,
        bytecode_len=bytecode_len,
        valid_jumpdests_start=valid_jumpdests_start,
        valid_jumpdests=valid_jumpdests,
        calldata=calldata,
        calldata_len=calldata_len,
        value=&tx.amount,
        caller=tx_encoded.sender,
        parent=parent,
        address=to,
        code_address=code_address,
        read_only=FALSE,
        is_create=1 - tx.destination.is_some,
        depth=0,
        env=env,
        cairo_precompile_called=FALSE,
    );

    return apply_transactions(txs_len - 1, tx_encoded + model.TransactionEncoded.SIZE);
}

// main entrypoint is required to have this signature in this order, with no other arguments
// nor returned values.
// Consequently, we just call the os function, which in turns can have any signature, and especially
// can return a model.State* convenient for testing.
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
