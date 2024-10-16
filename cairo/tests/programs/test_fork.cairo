from programs.fork import check_gas_limit, calculate_base_fee_per_gas, validate_header, Uint128
from src.model import model

func test_check_gas_limit{range_check_ptr}() {
    tempvar gas_limit: Uint128;
    tempvar parent_gas_limit: Uint128;
    %{
        ids.gas_limit = program_input["gas_limit"]
        ids.parent_gas_limit = program_input["parent_gas_limit"]
    %}
    check_gas_limit(gas_limit, parent_gas_limit);

    return ();
}

func test_calculate_base_fee_per_gas{range_check_ptr}() -> Uint128 {
    tempvar block_gas_limit: Uint128;
    tempvar parent_gas_limit: Uint128;
    tempvar parent_gas_used: Uint128;
    tempvar parent_base_fee_per_gas: Uint128;
    %{
        ids.block_gas_limit = program_input["block_gas_limit"]
        ids.parent_gas_limit = program_input["parent_gas_limit"]
        ids.parent_gas_used = program_input["parent_gas_used"]
        ids.parent_base_fee_per_gas = program_input["parent_base_fee_per_gas"]
    %}
    return calculate_base_fee_per_gas(
        block_gas_limit, parent_gas_limit, parent_gas_used, parent_base_fee_per_gas
    );
}

func test_validate_header{range_check_ptr}() {
    alloc_locals;
    local header: model.BlockHeader*;
    local parent_header: model.BlockHeader*;
    %{
        if '__dict_manager' not in globals():
            from starkware.cairo.common.dict import DictManager
            __dict_manager = DictManager()

        from tests.utils.hints import gen_arg

        ids.header = gen_arg(__dict_manager, segments, program_input["header"])
        ids.parent_header = gen_arg(__dict_manager, segments, program_input["parent_header"])
    %}
    validate_header([header], [parent_header]);
    return ();
}
