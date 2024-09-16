%builtins output

// Represents an integer in the range [0, 2^256).
struct Uint256 {
    // The low 128 bits of the value.
    low: felt,
    // The high 128 bits of the value.
    high: felt,
}

// @notice Store all environment data relevant to the current execution context.
// @param origin The origin of the transaction.
// @param gas_price The gas price for the call.
// @param chain_id The chain id of the current block.
// @param prev_randao The previous RANDAO value.
// @param block_number The block number of the current block.
// @param block_gas_limit The gas limit for the current block.
// @param block_timestamp The timestamp of the current block.
// @param coinbase The address of the miner of the current block.
// @param base_fee The basefee of the current block.
struct Environment {
    origin: felt,
    gas_price: felt,
    chain_id: felt,
    prev_randao: Uint256,
    block_number: felt,
    block_gas_limit: felt,
    block_timestamp: felt,
    coinbase: felt,
    base_fee: felt,
}

// @notice Populate an Environment with hint
func get_env() -> Environment* {
    tempvar env = cast(nondet %{ segments.add() %}, Environment*);

    // The hint should populate env.
    %{ block_info %}

    return env;
}

func main{output_ptr: felt*}() {
    let env = get_env();

    assert [output_ptr] = env.origin;
    assert [output_ptr + 1] = env.gas_price;
    assert [output_ptr + 2] = env.chain_id;
    assert [output_ptr + 3] = env.prev_randao.low;
    assert [output_ptr + 4] = env.prev_randao.high;
    assert [output_ptr + 5] = env.block_number;
    assert [output_ptr + 6] = env.block_gas_limit;
    assert [output_ptr + 7] = env.block_timestamp;
    assert [output_ptr + 8] = env.coinbase;
    assert [output_ptr + 9] = env.base_fee;
    let output_ptr = output_ptr + 10;

    return ();
}
