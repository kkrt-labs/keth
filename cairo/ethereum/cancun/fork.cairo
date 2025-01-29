from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.alloc import alloc
from ethereum_types.numeric import Uint, bool
from ethereum_types.bytes import Bytes, Bytes0, BytesStruct
from ethereum.utils.numeric import divmod
from ethereum.cancun.blocks import Header, Receipt, ReceiptStruct, TupleLog
from ethereum.cancun.transactions_types import (
    TX_ACCESS_LIST_ADDRESS_COST,
    TX_ACCESS_LIST_STORAGE_KEY_COST,
    TX_BASE_COST,
    TX_CREATE_COST,
    TX_DATA_COST_PER_NON_ZERO,
    TX_DATA_COST_PER_ZERO,
    Transaction,
    TupleAccessListStruct,
    To,
    ToStruct,
)
from ethereum.cancun.fork_types import Address
from ethereum.crypto.hash import keccak256
from ethereum.cancun.vm.gas import init_code_cost
from ethereum.exceptions import OptionalEthereumException
from ethereum.cancun.bloom import logs_bloom

from ethereum_rlp.rlp import Extended, ExtendedImpl, encode_receipt_to_buffer

from src.utils.array import count_not_zero

const ELASTICITY_MULTIPLIER = 2;
const BASE_FEE_MAX_CHANGE_DENOMINATOR = 8;
const GAS_LIMIT_ADJUSTMENT_FACTOR = 1024;
const GAS_LIMIT_MINIMUM = 5000;
const EMPTY_OMMER_HASH_LOW = 0xd312451b948a7413f0a142fd40d49347;
const EMPTY_OMMER_HASH_HIGH = 0x1dcc4de8dec75d7aab85b567b6ccd41a;

func calculate_base_fee_per_gas{range_check_ptr}(
    block_gas_limit: Uint,
    parent_gas_limit: Uint,
    parent_gas_used: Uint,
    parent_base_fee_per_gas: Uint,
) -> Uint {
    alloc_locals;
    let (parent_gas_target, _) = divmod(parent_gas_limit.value, ELASTICITY_MULTIPLIER);

    let cond_ = check_gas_limit(block_gas_limit, parent_gas_limit);
    with_attr error_message("InvalidBlock") {
        assert_not_zero(cond_.value);
    }

    if (parent_gas_used.value == parent_gas_target) {
        return parent_base_fee_per_gas;
    }

    let cond = is_le(parent_gas_target + 1, parent_gas_used.value);
    if (cond == TRUE) {
        let gas_used_delta = parent_gas_used.value - parent_gas_target;
        let parent_fee_gas_delta = parent_base_fee_per_gas.value * gas_used_delta;
        let (target_fee_gas_delta, _) = divmod(parent_fee_gas_delta, parent_gas_target);
        let (base_fee_per_gas_delta, _) = divmod(
            target_fee_gas_delta, BASE_FEE_MAX_CHANGE_DENOMINATOR
        );
        if (base_fee_per_gas_delta == 0) {
            let base_fee_per_gas = Uint(parent_base_fee_per_gas.value + 1);
            return base_fee_per_gas;
        }
        let base_fee_per_gas = Uint(parent_base_fee_per_gas.value + base_fee_per_gas_delta);
        return base_fee_per_gas;
    }

    let gas_used_delta = parent_gas_target - parent_gas_used.value;
    let parent_fee_gas_delta = parent_base_fee_per_gas.value * gas_used_delta;
    let (target_fee_gas_delta, _) = divmod(parent_fee_gas_delta, parent_gas_target);
    let (base_fee_per_gas_delta, _) = divmod(target_fee_gas_delta, BASE_FEE_MAX_CHANGE_DENOMINATOR);

    let base_fee_per_gas = Uint(parent_base_fee_per_gas.value - base_fee_per_gas_delta);
    return base_fee_per_gas;
}

func validate_header{range_check_ptr}(header: Header, parent_header: Header) {
    with_attr error_message("InvalidBlock") {
        assert [range_check_ptr] = header.value.gas_limit.value - header.value.gas_used.value;
        let range_check_ptr = range_check_ptr + 1;

        let expected_base_fee_per_gas = calculate_base_fee_per_gas(
            header.value.gas_limit,
            parent_header.value.gas_limit,
            parent_header.value.gas_used,
            parent_header.value.base_fee_per_gas,
        );

        assert expected_base_fee_per_gas = header.value.base_fee_per_gas;
        assert [range_check_ptr] = header.value.timestamp.value -
            parent_header.value.timestamp.value - 1;
        assert [range_check_ptr + 1] = header.value.number.value -
            parent_header.value.number.value - 1;
        assert [range_check_ptr + 2] = 32 - header.value.extra_data.value.len;
        let range_check_ptr = range_check_ptr + 3;
        assert header.value.difficulty.value = 0;
        assert header.value.nonce.value = 0;
        assert header.value.ommers_hash.value.low = EMPTY_OMMER_HASH_LOW;
        assert header.value.ommers_hash.value.high = EMPTY_OMMER_HASH_HIGH;
    }

    // TODO: Implement block header hash check
    // let block_parent_hash = keccak256(rlp.encode(parent_header));
    // assert header.value.parent_hash = block_parent_hash;
    return ();
}

func check_gas_limit{range_check_ptr}(gas_limit: Uint, parent_gas_limit: Uint) -> bool {
    alloc_locals;
    let (max_adjustment_delta, _) = divmod(parent_gas_limit.value, GAS_LIMIT_ADJUSTMENT_FACTOR);
    let cond = is_le(parent_gas_limit.value + max_adjustment_delta, gas_limit.value);
    if (cond == TRUE) {
        tempvar value = bool(FALSE);
        return value;
    }
    let cond = is_le(gas_limit.value, parent_gas_limit.value - max_adjustment_delta);
    if (cond == TRUE) {
        tempvar value = bool(FALSE);
        return value;
    }
    let cond = is_le(gas_limit.value, GAS_LIMIT_MINIMUM);
    if (cond == TRUE) {
        tempvar value = bool(FALSE);
        return value;
    }

    tempvar value = bool(TRUE);
    return value;
}

struct UnionBytesReceiptEnum {
    bytes: Bytes,
    receipt: Receipt,
}

struct UnionBytesReceipt {
    value: UnionBytesReceiptEnum*,
}

func make_receipt{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}(
    tx: Transaction, error: OptionalEthereumException, cumulative_gas_used: Uint, logs: TupleLog
) -> UnionBytesReceipt {
    alloc_locals;
    if (cast(error.value, felt) != 0) {
        [ap] = 0, ap++;
    } else {
        [ap] = 1, ap++;
    }
    let succeeded = bool([ap - 1]);

    let bloom = logs_bloom(logs);
    tempvar receipt = Receipt(
        new ReceiptStruct(
            succeeded=succeeded, cumulative_gas_used=cumulative_gas_used, bloom=bloom, logs=logs
        ),
    );

    if (cast(tx.value.access_list_transaction.value, felt) != 0) {
        let (buffer: felt*) = alloc();
        assert [buffer] = 1;
        let encoding = encode_receipt_to_buffer(1, buffer + 1, receipt);
        tempvar res = UnionBytesReceipt(
            new UnionBytesReceiptEnum(bytes=encoding, receipt=Receipt(cast(0, ReceiptStruct*)))
        );
        return res;
    }

    if (cast(tx.value.fee_market_transaction.value, felt) != 0) {
        let (buffer: felt*) = alloc();
        assert [buffer] = 2;
        let encoding = encode_receipt_to_buffer(1, buffer + 1, receipt);
        tempvar res = UnionBytesReceipt(
            new UnionBytesReceiptEnum(bytes=encoding, receipt=Receipt(cast(0, ReceiptStruct*)))
        );
        return res;
    }

    if (cast(tx.value.blob_transaction.value, felt) != 0) {
        let (buffer: felt*) = alloc();
        assert [buffer] = 3;
        let encoding = encode_receipt_to_buffer(1, buffer + 1, receipt);
        tempvar res = UnionBytesReceipt(
            new UnionBytesReceiptEnum(bytes=encoding, receipt=Receipt(cast(0, ReceiptStruct*)))
        );
        return res;
    }

    tempvar res = UnionBytesReceipt(
        new UnionBytesReceiptEnum(bytes=Bytes(cast(0, BytesStruct*)), receipt=receipt)
    );
    return res;
}
