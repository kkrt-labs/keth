// See https://github.com/ethereum/execution-specs/blob/master/src/ethereum/cancun/fork.py

from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.math import unsigned_div_rem, split_felt
from starkware.cairo.common.math_cmp import is_nn
from starkware.cairo.common.bool import FALSE

from src.model import model

using Uint128 = felt;
using Uint64 = felt;

const ELASTICITY_MULTIPLIER = 2;
const GAS_LIMIT_ADJUSTMENT_FACTOR = 1024;
const GAS_LIMIT_MINIMUM = 5000;
const BASE_FEE_MAX_CHANGE_DENOMINATOR = 8;
const EMPTY_OMMER_HASH_LOW = 0xd312451b948a7413f0a142fd40d49347;
const EMPTY_OMMER_HASH_HIGH = 0x1dcc4de8dec75d7aab85b567b6ccd41a;

// @notice See https://github.com/ethereum/execution-specs/blob/master/src/ethereum/cancun/fork.py#L1118-L1154
// @dev We use the Uint128 alias to strenghten the fact that these felts should have been range_checked before
func check_gas_limit{range_check_ptr}(gas_limit: Uint64, parent_gas_limit: Uint64) {
    let (max_adjustment_delta, _) = unsigned_div_rem(parent_gas_limit, GAS_LIMIT_ADJUSTMENT_FACTOR);

    with_attr error_message("InvalidBlock") {
        assert [range_check_ptr] = parent_gas_limit + max_adjustment_delta - gas_limit - 1;
        assert [range_check_ptr + 1] = gas_limit - (parent_gas_limit - max_adjustment_delta) - 1;
        assert [range_check_ptr + 2] = gas_limit - GAS_LIMIT_MINIMUM;
        let range_check_ptr = range_check_ptr + 3;
    }

    return ();
}

// @notice See https://github.com/ethereum/execution-specs/blob/master/src/ethereum/cancun/fork.py#L226-L285
// @dev We use the Uint64 alias to strenghten the fact that these felts should have been range_checked before
func calculate_base_fee_per_gas{range_check_ptr}(
    block_gas_limit: Uint64,
    parent_gas_limit: Uint64,
    parent_gas_used: Uint64,
    parent_base_fee_per_gas: Uint64,
) -> Uint128 {
    let (parent_gas_target, _) = unsigned_div_rem(parent_gas_limit, ELASTICITY_MULTIPLIER);

    check_gas_limit(block_gas_limit, parent_gas_limit);

    if (parent_gas_used == parent_gas_target) {
        return parent_base_fee_per_gas;
    }

    let is_parent_gas_used_greater_than_parent_gas_target = is_nn(
        parent_gas_used - parent_gas_target - 1
    );
    if (is_parent_gas_used_greater_than_parent_gas_target != FALSE) {
        let gas_used_delta = parent_gas_used - parent_gas_target;
        let parent_fee_gas_delta = parent_base_fee_per_gas * gas_used_delta;
        let (target_fee_gas_delta, _) = unsigned_div_rem(parent_fee_gas_delta, parent_gas_target);
        let (base_fee_per_gas_delta, _) = unsigned_div_rem(
            target_fee_gas_delta, BASE_FEE_MAX_CHANGE_DENOMINATOR
        );
        if (base_fee_per_gas_delta == 0) {
            return 1;
        }
        return base_fee_per_gas_delta;
    }

    let gas_used_delta = parent_gas_target - parent_gas_used;
    let parent_fee_gas_delta = parent_base_fee_per_gas * gas_used_delta;
    let (target_fee_gas_delta, _) = unsigned_div_rem(parent_fee_gas_delta, parent_gas_target);
    let (base_fee_per_gas_delta, _) = unsigned_div_rem(
        target_fee_gas_delta, BASE_FEE_MAX_CHANGE_DENOMINATOR
    );

    return parent_base_fee_per_gas - base_fee_per_gas_delta;
}

// @notice See https://github.com/ethereum/execution-specs/blob/master/src/ethereum/cancun/fork.py#L288-L332
// @dev Initial range checks for all values because header is filled with a hint
func validate_header{range_check_ptr}(header: model.BlockHeader, parent_header: model.BlockHeader) {
    // parent_hash
    assert [range_check_ptr] = header.parent_hash.low;
    assert [range_check_ptr + 1] = header.parent_hash.high;
    let range_check_ptr = range_check_ptr + 2;

    // ommers_hash
    assert [range_check_ptr] = header.ommers_hash.low;
    assert [range_check_ptr + 1] = header.ommers_hash.high;
    let range_check_ptr = range_check_ptr + 2;

    // coinbase
    let (coinbase_high, coinbase_low) = split_felt(header.coinbase);
    assert [range_check_ptr] = coinbase_low;
    assert [range_check_ptr + 1] = coinbase_high;
    assert [range_check_ptr + 2] = 2 ** 32 - coinbase_high - 1;
    let range_check_ptr = range_check_ptr + 3;

    // state_root
    assert [range_check_ptr] = header.state_root.low;
    assert [range_check_ptr + 1] = header.state_root.high;
    let range_check_ptr = range_check_ptr + 2;

    // transactions_root
    assert [range_check_ptr] = header.transactions_root.low;
    assert [range_check_ptr + 1] = header.transactions_root.high;
    let range_check_ptr = range_check_ptr + 2;

    // receipt_root
    assert [range_check_ptr] = header.receipt_root.low;
    assert [range_check_ptr + 1] = header.receipt_root.high;
    let range_check_ptr = range_check_ptr + 2;

    // withdrawals_root
    assert header.withdrawals_root.is_some * (1 - header.withdrawals_root.is_some) = 0;
    let withdrawals_root = cast(header.withdrawals_root.value, Uint256*);
    assert [range_check_ptr] = withdrawals_root.low;
    assert [range_check_ptr + 1] = withdrawals_root.high;
    let range_check_ptr = range_check_ptr + 2;

    // difficulty
    assert [range_check_ptr] = header.difficulty.low;
    assert [range_check_ptr + 1] = header.difficulty.high;
    let range_check_ptr = range_check_ptr + 2;

    // number
    assert [range_check_ptr] = header.number;
    assert [range_check_ptr + 1] = 2 ** 64 - header.number - 1;
    let range_check_ptr = range_check_ptr + 2;

    // gas_limit
    assert [range_check_ptr] = header.gas_limit;
    assert [range_check_ptr + 1] = 2 ** 64 - header.gas_limit - 1;
    let range_check_ptr = range_check_ptr + 2;

    // gas_used
    assert [range_check_ptr] = header.gas_used;
    assert [range_check_ptr + 1] = 2 ** 64 - header.gas_used - 1;
    let range_check_ptr = range_check_ptr + 2;

    // timestamp
    assert [range_check_ptr] = header.timestamp;
    assert [range_check_ptr + 1] = 2 ** 64 - header.timestamp - 1;
    let range_check_ptr = range_check_ptr + 2;

    // mix_hash
    assert [range_check_ptr] = header.mix_hash.low;
    assert [range_check_ptr + 1] = header.mix_hash.high;
    let range_check_ptr = range_check_ptr + 2;

    // nonce
    assert [range_check_ptr] = header.nonce;
    assert [range_check_ptr + 1] = 2 ** 64 - header.nonce - 1;
    let range_check_ptr = range_check_ptr + 2;

    // base_fee_per_gas
    assert header.base_fee_per_gas.is_some * (1 - header.base_fee_per_gas.is_some) = 0;
    assert [range_check_ptr] = header.base_fee_per_gas.value;
    assert [range_check_ptr + 1] = 2 ** 64 - header.base_fee_per_gas.value - 1;
    let range_check_ptr = range_check_ptr + 2;

    // blob_gas_used
    assert header.blob_gas_used.is_some * (1 - header.blob_gas_used.is_some) = 0;
    assert [range_check_ptr] = header.blob_gas_used.value;
    assert [range_check_ptr + 1] = 2 ** 64 - header.blob_gas_used.value - 1;
    let range_check_ptr = range_check_ptr + 2;

    // excess_blob_gas
    assert header.excess_blob_gas.is_some * (1 - header.excess_blob_gas.is_some) = 0;
    assert [range_check_ptr] = header.excess_blob_gas.value;
    assert [range_check_ptr + 1] = 2 ** 64 - header.excess_blob_gas.value - 1;
    let range_check_ptr = range_check_ptr + 2;

    // parent_beacon_block_root
    assert header.parent_beacon_block_root.is_some * (
        1 - header.parent_beacon_block_root.is_some
    ) = 0;
    let parent_beacon_block_root = cast(header.parent_beacon_block_root.value, Uint256*);
    assert [range_check_ptr] = parent_beacon_block_root.low;
    assert [range_check_ptr + 1] = parent_beacon_block_root.high;
    let range_check_ptr = range_check_ptr + 2;

    // requests_root
    assert header.requests_root.is_some * (1 - header.requests_root.is_some) = 0;
    let requests_root = cast(header.requests_root.value, Uint256*);
    assert [range_check_ptr] = requests_root.low;
    assert [range_check_ptr + 1] = requests_root.high;
    let range_check_ptr = range_check_ptr + 2;

    // extra_data_len
    assert [range_check_ptr] = header.extra_data_len;
    let range_check_ptr = range_check_ptr + 1;

    with_attr error_message("InvalidBlock") {
        assert [range_check_ptr] = header.gas_limit - header.gas_used;
        let range_check_ptr = range_check_ptr + 1;
        let expected_base_fee_per_gas = calculate_base_fee_per_gas(
            header.gas_limit,
            parent_header.gas_limit,
            parent_header.gas_used,
            parent_header.base_fee_per_gas.value,
        );

        assert expected_base_fee_per_gas = header.base_fee_per_gas.value;
        assert [range_check_ptr] = header.timestamp - parent_header.timestamp - 1;
        assert [range_check_ptr + 1] = header.number - parent_header.number - 1;
        assert [range_check_ptr + 2] = 32 - header.extra_data_len;
        let range_check_ptr = range_check_ptr + 3;
        assert header.difficulty.low = 0;
        assert header.difficulty.high = 0;
        assert header.nonce = 0;
        assert header.ommers_hash.low = EMPTY_OMMER_HASH_LOW;
        assert header.ommers_hash.high = EMPTY_OMMER_HASH_HIGH;
    }

    // TODO: Implement block header hash check
    // block_parent_hash = keccak256(rlp.encode(parent_header))
    // if header.parent_hash != block_parent_hash:
    //     raise InvalidBlock
    return ();
}
