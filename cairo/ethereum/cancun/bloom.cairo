from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE, TRUE
from starkware.cairo.common.dict import DictAccess
from starkware.cairo.common.default_dict import default_dict_new
from starkware.cairo.common.memset import memset
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc
from starkware.cairo.common.math import assert_le, assert_lt
from starkware.cairo.common.math_cmp import is_le, is_not_zero
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin

from ethereum_types.bytes import Bytes, BytesStruct, Bytes1DictAccess, Bytes32, TupleBytes32
from ethereum_types.numeric import U256, Uint, U128
from ethereum.utils.numeric import max, U64_from_be_bytes, divmod
from ethereum.utils.bytes import Bytes20_to_Bytes, Bytes32_to_Bytes
from ethereum.crypto.hash import keccak256
from ethereum.cancun.blocks import TupleLog
from ethereum.cancun.fork_types import Bloom

from legacy.utils.bytes import uint256_to_bytes32, felt_to_bytes16_little
from legacy.utils.dict import dict_read, dict_write, default_dict_finalize
from cairo_core.maths import pow2
from cairo_core.comparison import is_zero
const BIT_MASK_11_BITS = 0x07FF;

struct MutableBloomStruct {
    dict_ptr_start: Bytes1DictAccess*,
    dict_ptr: Bytes1DictAccess*,
    len: felt,
}

struct MutableBloom {
    value: MutableBloomStruct*,
}

func add_to_bloom{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*, bloom: MutableBloom
}(bloom_entry: Bytes) {
    alloc_locals;
    let hash = keccak256(bloom_entry);
    let (hash_low_bytes: felt*) = alloc();
    felt_to_bytes16_little(hash_low_bytes, hash.value.low);
    tempvar hash_bytes = Bytes(new BytesStruct(hash_low_bytes, 16));
    _add_bloom_index(hash_bytes, 0);
    _add_bloom_index(hash_bytes, 2);
    _add_bloom_index(hash_bytes, 4);

    return ();
}

// @dev does not expect to be called with indexes other than 0, 2, 4
func _add_bloom_index{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, bloom: MutableBloom}(
    bloom_entry_hash: Bytes, index: felt
) {
    alloc_locals;
    tempvar hash_subset = Bytes(new BytesStruct(bloom_entry_hash.value.data + index, 2));
    let hash_subset_uint = U64_from_be_bytes(hash_subset);

    assert bitwise_ptr.x = hash_subset_uint.value;
    assert bitwise_ptr.y = BIT_MASK_11_BITS;
    tempvar bit_to_set = bitwise_ptr.x_and_y;
    let bitwise_ptr = bitwise_ptr + BitwiseBuiltin.SIZE;

    let bit_index = BIT_MASK_11_BITS - bit_to_set;
    let (byte_index, bit_position) = divmod(bit_index, 8);

    // Calculate 1 << (7 - bit_position) using multiplication
    // This is equivalent to 2^bit_shift where bit_shift = 7 - bit_position
    let bit_shift_value = 7 - bit_position;
    let bit_value = pow2(bit_shift_value);

    // Read current byte value
    let bloom_ptr = cast(bloom.value.dict_ptr, DictAccess*);
    let (current_value) = dict_read{dict_ptr=bloom_ptr}(byte_index);

    // Set the bit using OR operation
    assert bitwise_ptr.x = current_value;
    assert bitwise_ptr.y = bit_value;
    let new_value = bitwise_ptr.x_or_y;
    let bitwise_ptr = bitwise_ptr + BitwiseBuiltin.SIZE;

    // Write back the updated byte
    dict_write{dict_ptr=bloom_ptr}(byte_index, new_value);

    tempvar bloom = MutableBloom(
        new MutableBloomStruct(
            dict_ptr_start=bloom.value.dict_ptr_start,
            dict_ptr=cast(bloom_ptr, Bytes1DictAccess*),
            len=bloom.value.len,
        ),
    );

    return ();
}

func logs_bloom{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}(
    logs: TupleLog
) -> Bloom {
    alloc_locals;
    let (local mutable_bloom_start) = default_dict_new(0);
    let mutable_bloom_end = mutable_bloom_start;

    tempvar mutable_bloom = MutableBloom(
        new MutableBloomStruct(
            dict_ptr_start=cast(mutable_bloom_start, Bytes1DictAccess*),
            dict_ptr=cast(mutable_bloom_end, Bytes1DictAccess*),
            len=256,
        ),
    );

    _iter_logs{bloom=mutable_bloom}(logs, 0);

    let (local bloom_buffer: felt*) = alloc();
    local range_check_ptr = range_check_ptr;
    local bitwise_ptr: BitwiseBuiltin* = bitwise_ptr;
    local keccak_ptr: KeccakBuiltin* = keccak_ptr;

    tempvar index = 255;
    tempvar bloom_end = cast(mutable_bloom.value.dict_ptr, DictAccess*);

    loop:
    let index = [ap - 2];
    let dict_ptr = cast([ap - 1], DictAccess*);

    let (value) = dict_read{dict_ptr=dict_ptr}(index);
    assert bloom_buffer[index] = value;

    let is_done = is_zero(index);
    tempvar dict_ptr = dict_ptr;
    jmp done if is_done != 0;

    tempvar index = index - 1;
    tempvar dict_ptr = dict_ptr;
    jmp loop;

    done:
    let dict_ptr = cast([ap - 1], DictAccess*);
    default_dict_finalize(mutable_bloom_start, dict_ptr, 0);

    tempvar bloom = Bloom(cast(bloom_buffer, U128*));
    return bloom;
}

func _iter_logs{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*, bloom: MutableBloom
}(logs: TupleLog, index) {
    if (index == logs.value.len) {
        return ();
    }
    let log = logs.value.data[index];
    let address_bytes = Bytes20_to_Bytes(log.value.address);
    add_to_bloom(address_bytes);
    _iter_topics(log.value.topics, 0);

    return _iter_logs(logs, index + 1);
}

func _iter_topics{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*, bloom: MutableBloom
}(topics: TupleBytes32, index) {
    if (index == topics.value.len) {
        return ();
    }
    let topic = topics.value.data[index];
    let topic_bytes = Bytes32_to_Bytes(topic);
    add_to_bloom(topic_bytes);
    return _iter_topics(topics, index + 1);
}
