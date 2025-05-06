from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from cairo_core.maths import (
    assert_uint256_le,
    felt252_to_bytes_le,
    felt252_to_bytes_be,
    felt252_to_bits_rev,
    felt252_to_bytes4_le,
)
from cairo_core.numeric import U256
from starkware.cairo.common.alloc import alloc

func test__assert_uint256_le{range_check_ptr}(a: U256, b: U256) {
    alloc_locals;
    assert_uint256_le([a.value], [b.value]);

    return ();
}

func test__felt252_to_bytes_le{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    value: felt, len: felt
) -> felt* {
    alloc_locals;
    let (dst) = alloc();
    let res = felt252_to_bytes_le(value, len, dst);
    return dst;
}

func test__felt252_to_bytes_be{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    value: felt, len: felt
) -> felt* {
    alloc_locals;
    let (dst) = alloc();
    let res = felt252_to_bytes_be(value, len, dst);
    return dst;
}

func test__felt252_to_bits_rev{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    value: felt, len: felt
) -> felt* {
    alloc_locals;
    let (dst) = alloc();
    felt252_to_bits_rev(value, len, dst);
    return dst;
}

func test__felt252_to_bytes4_le{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    value: felt, num_words: felt
) -> felt* {
    alloc_locals;
    let (dst) = alloc();
    let res = felt252_to_bytes4_le(value, num_words, dst);
    return dst;
}
