%builtins range_check

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import Uint256

from cairo_core.numeric import U256
from cairo_core.bytes import Bytes

from legacy.utils.bytes import (
    felt_to_bytes_little,
    felt_to_bytes,
    uint256_to_bytes_little,
    uint256_to_bytes,
    uint256_to_bytes32,
    bytes_to_bytes8_little_endian,
    bytes_to_bytes4_little_endian,
    bytes_to_felt,
    bytes_to_felt_le,
)

func test__felt_to_bytes_little{range_check_ptr}(n: felt) -> felt* {
    alloc_locals;

    let (output) = alloc();
    felt_to_bytes_little(output, n);
    return output;
}

func test__felt_to_bytes{range_check_ptr}(n: felt) -> felt* {
    alloc_locals;
    let (output) = alloc();
    felt_to_bytes(output, n);
    return output;
}

func test__uint256_to_bytes_little{range_check_ptr}(n: U256) -> felt* {
    alloc_locals;
    let (output) = alloc();
    uint256_to_bytes_little(output, [n.value]);
    return output;
}

func test__uint256_to_bytes{range_check_ptr}(n: U256) -> felt* {
    alloc_locals;
    let (output) = alloc();
    uint256_to_bytes(output, [n.value]);
    return output;
}

func test__uint256_to_bytes32{range_check_ptr}(n: U256) -> felt* {
    alloc_locals;
    let (output) = alloc();
    uint256_to_bytes32(output, [n.value]);
    return output;
}

func test__bytes_to_bytes8_little_endian{range_check_ptr}(bytes: Bytes) -> felt* {
    alloc_locals;
    let (bytes8) = alloc();
    bytes_to_bytes8_little_endian(bytes8, bytes.value.len, bytes.value.data);

    return bytes8;
}

func test__bytes_to_bytes4_little_endian{range_check_ptr}(bytes: Bytes) -> felt* {
    alloc_locals;
    let (bytes4) = alloc();
    bytes_to_bytes4_little_endian(bytes4, bytes.value.len, bytes.value.data);
    return bytes4;
}

func test__bytes_to_felt(bytes: Bytes) -> felt {
    alloc_locals;
    let res = bytes_to_felt(bytes.value.len, bytes.value.data);
    return res;
}

func test__bytes_to_felt_le(bytes: Bytes) -> felt {
    alloc_locals;
    let res = bytes_to_felt_le(bytes.value.len, bytes.value.data);
    return res;
}
