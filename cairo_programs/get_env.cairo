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
    %{ get_env %}

    return env;
}

func main() {
    let env = get_env();
    %{
        print(f"{ids.origin=}")
        print(f"{ids.gas_price=}")
        print(f"{ids.chain_id=}")
        print(f"{ids.prev_randao=}")
        print(f"{ids.block_number=}")
        print(f"{ids.block_gas_limit=}")
        print(f"{ids.block_timestamp=}")
        print(f"{ids.coinbase=}")
        print(f"{ids.base_fee=}")
    %}

    return ();
}
