from starkware.cairo.common.cairo_builtins import HashBuiltin, KeccakBuiltin, BitwiseBuiltin
from starkware.cairo.common.builtin_keccak.keccak import keccak_bigend
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import split_int, split_felt, assert_le_felt, assert_nn_le
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.memset import memset
from starkware.cairo.common.registers import get_label_location

from src.utils.array import reverse
from cairo_core.maths import unsigned_div_rem

func felt_to_ascii{range_check_ptr}(dst: felt*, n: felt) -> felt {
    alloc_locals;
    let (local ascii: felt*) = alloc();

    tempvar range_check_ptr = range_check_ptr;
    tempvar n = n;
    tempvar ascii_len = 0;

    body:
    let ascii = cast([fp], felt*);
    let range_check_ptr = [ap - 3];
    let n = [ap - 2];
    let ascii_len = [ap - 1];

    let (n, chunk) = unsigned_div_rem(n, 10);
    assert [ascii + ascii_len] = chunk + '0';

    tempvar range_check_ptr = range_check_ptr;
    tempvar n = n;
    tempvar ascii_len = ascii_len + 1;

    jmp body if n != 0;

    let range_check_ptr = [ap - 3];
    let ascii_len = [ap - 1];
    let ascii = cast([fp], felt*);

    reverse(dst, ascii_len, ascii);

    return ascii_len;
}

// @notice Split a felt into an array of bytes little endian
// @dev Use a hint from split_int: the value must be lower than 248 bits
// as the prover assumption is n_bytes**256 < PRIME
func felt_to_bytes_little{range_check_ptr}(dst: felt*, value: felt) -> felt {
    alloc_locals;

    with_attr error_message("felt_to_bytes_little: value >= 2**248") {
        assert_le_felt(value, 2 ** 248 - 1);
    }

    tempvar range_check_ptr = range_check_ptr;
    tempvar value = value;
    tempvar bytes_len = 0;

    body:
    let range_check_ptr = [ap - 3];
    let value = [ap - 2];
    let bytes_len = [ap - 1];
    let bytes = cast([fp - 4], felt*);
    let output = bytes + bytes_len;
    let base = 2 ** 8;
    let bound = base;

    %{
        memory[ids.output] = res = (int(ids.value) % PRIME) % ids.base
        assert res < ids.bound, f'split_int(): Limb {res} is out of range.'
    %}
    let byte = [output];
    with_attr error_message("felt_to_bytes_little: byte value is too big") {
        assert_nn_le(byte, bound - 1);
    }
    tempvar value = (value - byte) / base;

    tempvar range_check_ptr = range_check_ptr;
    tempvar value = value;
    tempvar bytes_len = bytes_len + 1;

    jmp body if value != 0;

    let range_check_ptr = [ap - 3];
    let value = [ap - 2];
    let bytes_len = [ap - 1];
    assert value = 0;

    let (pow256_address) = get_label_location(pow256_table);
    if (bytes_len == 1) {
        tempvar lower_bound = 0;
    } else {
        let lower_bound_ = pow256_address[bytes_len - 1];
        tempvar lower_bound = lower_bound_;
    }

    // Assert that the `bytes_len` found is the minimal one possible to represent the value.
    let initial_value = [fp - 3];
    let lower_bound = [ap - 1];
    let upper_bound = pow256_address[bytes_len];
    with_attr error_message("bytes_len is not the minimal possible") {
        assert_le_felt(bytes_len, 31);
        assert_le_felt(lower_bound, initial_value);
        assert_le_felt(initial_value, upper_bound - 1);
    }
    return bytes_len;

    pow256_table:
    dw 256 ** 0;
    dw 256 ** 1;
    dw 256 ** 2;
    dw 256 ** 3;
    dw 256 ** 4;
    dw 256 ** 5;
    dw 256 ** 6;
    dw 256 ** 7;
    dw 256 ** 8;
    dw 256 ** 9;
    dw 256 ** 10;
    dw 256 ** 11;
    dw 256 ** 12;
    dw 256 ** 13;
    dw 256 ** 14;
    dw 256 ** 15;
    dw 256 ** 16;
    dw 256 ** 17;
    dw 256 ** 18;
    dw 256 ** 19;
    dw 256 ** 20;
    dw 256 ** 21;
    dw 256 ** 22;
    dw 256 ** 23;
    dw 256 ** 24;
    dw 256 ** 25;
    dw 256 ** 26;
    dw 256 ** 27;
    dw 256 ** 28;
    dw 256 ** 29;
    dw 256 ** 30;
    dw 256 ** 31;
}

// @notice Split a felt into an array of bytes
// @dev Use felt_to_bytes_little: the value must be lower than 248 bits
// as the prover assumption is n_bytes**256 < PRIME
func felt_to_bytes{range_check_ptr}(dst: felt*, value: felt) -> felt {
    alloc_locals;
    let (local bytes: felt*) = alloc();
    let bytes_len = felt_to_bytes_little(bytes, value);
    reverse(dst, bytes_len, bytes);

    return bytes_len;
}

// @notice Loads a sequence of bytes into a single felt in big-endian.
// @param len: number of bytes.
// @param ptr: pointer to bytes array.
// @return: packed felt.
func bytes_to_felt(len: felt, ptr: felt*) -> felt {
    if (len == 0) {
        return 0;
    }
    tempvar current = 0;

    // len, ptr, ?, ?, current
    // ?, ? are intermediate steps created by the compiler to unfold the
    // complex expression.
    loop:
    let len = [ap - 5];
    let ptr = cast([ap - 4], felt*);
    let current = [ap - 1];

    tempvar len = len - 1;
    tempvar ptr = ptr + 1;
    tempvar current = current * 256 + [ptr - 1];

    static_assert len == [ap - 5];
    static_assert ptr == [ap - 4];
    static_assert current == [ap - 1];
    jmp loop if len != 0;

    return current;
}

// @notice Split a felt into an array of 20 bytes, little endian
// @dev Truncate the high 12 bytes
func felt_to_bytes20_little{range_check_ptr}(dst: felt*, value: felt) {
    alloc_locals;
    let (high, low) = split_felt(value);
    let (_, high) = unsigned_div_rem(high, 2 ** 32);
    split_int(low, 16, 256, 256, dst);
    split_int(high, 4, 256, 256, dst + 16);
    return ();
}

// @notice Split a felt into an array of 16 bytes, little endian
// @dev Raise if the value is greater than 2**128 - 1
func felt_to_bytes16_little{range_check_ptr}(dst: felt*, value: felt) {
    alloc_locals;
    assert [range_check_ptr] = value;
    let range_check_ptr = range_check_ptr + 1;
    split_int(value, 16, 256, 256, dst);
    return ();
}

// @notice Split a felt into an array of 20 bytes, big endian
// @dev Truncate the high 12 bytes
func felt_to_bytes20{range_check_ptr}(dst: felt*, value: felt) {
    alloc_locals;
    let (bytes20: felt*) = alloc();
    felt_to_bytes20_little(bytes20, value);
    reverse(dst, 20, bytes20);
    return ();
}

func felt_to_bytes32_little{range_check_ptr}(dst: felt*, value: felt) {
    alloc_locals;
    let (high, low) = split_felt(value);
    split_int(low, 16, 256, 256, dst);
    split_int(high, 16, 256, 256, dst + 16);
    return ();
}

func felt_to_bytes32{range_check_ptr}(dst: felt*, value: felt) {
    alloc_locals;
    let (bytes32: felt*) = alloc();
    felt_to_bytes32_little(bytes32, value);
    reverse(dst, 32, bytes32);
    return ();
}

func uint256_to_bytes_little{range_check_ptr}(dst: felt*, n: Uint256) -> felt {
    alloc_locals;
    let (local highest_byte, safe_high) = unsigned_div_rem(n.high, 2 ** 120);
    local range_check_ptr = range_check_ptr;

    let value = n.low + safe_high * 2 ** 128;
    let len = felt_to_bytes_little(dst, value);
    if (highest_byte != 0) {
        memset(dst + len, 0, 31 - len);
        assert [dst + 31] = highest_byte;
        tempvar bytes_len = 32;
    } else {
        tempvar bytes_len = len;
    }

    return bytes_len;
}

func uint256_to_bytes{range_check_ptr}(dst: felt*, n: Uint256) -> felt {
    alloc_locals;
    let (bytes: felt*) = alloc();
    let bytes_len = uint256_to_bytes_little(bytes, n);
    reverse(dst, bytes_len, bytes);
    return bytes_len;
}

func uint256_to_bytes32_little{range_check_ptr}(dst: felt*, n: Uint256) {
    alloc_locals;
    let bytes_len = uint256_to_bytes_little(dst, n);
    memset(dst + bytes_len, 0, 32 - bytes_len);
    return ();
}

func uint256_to_bytes32{range_check_ptr}(dst: felt*, n: Uint256) {
    alloc_locals;
    let (bytes: felt*) = alloc();
    uint256_to_bytes32_little(bytes, n);
    reverse(dst, 32, bytes);
    return ();
}

// @notice Converts an array of bytes to an array of bytes8, little endian
// @dev The function is sound because the number of steps is limited to 2^50 by the verifier.
//      Consequently, `bytes8` cannot wrap around P. No range_check is needed in the main loop.
//      Only in the final step, depending on the size of the remainder, is the total length of the
//      output array checked.
// @param dst The destination array.
// @param bytes_len The number of bytes in the input array.
// @param bytes The input array.
func bytes_to_bytes8_little_endian{range_check_ptr}(dst: felt*, bytes_len: felt, bytes: felt*) -> (
    ) {
    alloc_locals;

    if (bytes_len == 0) {
        return ();
    }

    tempvar less_than_8;
    %{ bytes_len_less_than_8 %}
    tempvar bytes8 = dst;
    tempvar bytes = bytes;

    static_assert bytes8 == [ap - 2];
    static_assert bytes == [ap - 1];

    jmp skip_full_word_loop if less_than_8 != 0;

    // Main loop done a random number of times
    full_word_loop:
    let bytes8 = cast([ap - 2], felt*);
    let bytes = cast([ap - 1], felt*);

    assert [bytes8] = bytes[0] + bytes[1] * 256 + bytes[2] * 256 ** 2 + bytes[3] * 256 ** 3 + bytes[
        4
    ] * 256 ** 4 + bytes[5] * 256 ** 5 + bytes[6] * 256 ** 6 + bytes[7] * 256 ** 7;
    tempvar continue_loop;
    tempvar bytes8 = bytes8 + 1;
    tempvar bytes = bytes + 8;
    %{ remaining_bytes_greater_than_8 %}

    jmp full_word_loop if continue_loop != 0;

    skip_full_word_loop:
    let bytes8 = cast([ap - 2], felt*);
    let bytes = cast([ap - 1], felt*);

    tempvar remaining_offset;
    %{ remaining_bytes_jmp_offset %}
    static_assert bytes8 == [ap - 3];
    static_assert bytes == [ap - 2];
    jmp rel remaining_offset;
    jmp remaining_0;
    jmp remaining_1;
    jmp remaining_2;
    jmp remaining_3;
    jmp remaining_4;
    jmp remaining_5;
    jmp remaining_6;
    jmp remaining_7;

    // Remaining bytes, one case per possible number of bytes
    // Each case assert the number of bytes written to the destination array
    // and the value of the bytes

    remaining_7:
    let dst = cast([fp - 5], felt*);
    let bytes_len = cast([fp - 4], felt);
    let bytes8 = cast([ap - 3], felt*);
    let bytes = cast([ap - 2], felt*);
    assert (bytes8 - dst) * 8 = bytes_len - 7;
    assert [bytes8] = bytes[0] + bytes[1] * 256 + bytes[2] * 256 ** 2 + bytes[3] * 256 ** 3 + bytes[
        4
    ] * 256 ** 4 + bytes[5] * 256 ** 5 + bytes[6] * 256 ** 6;
    let range_check_ptr = [fp - 6];
    return ();

    remaining_6:
    let dst = cast([fp - 5], felt*);
    let bytes_len = cast([fp - 4], felt);
    let bytes8 = cast([ap - 3], felt*);
    let bytes = cast([ap - 2], felt*);
    assert (bytes8 - dst) * 8 = bytes_len - 6;
    assert [bytes8] = bytes[0] + bytes[1] * 256 + bytes[2] * 256 ** 2 + bytes[3] * 256 ** 3 + bytes[
        4
    ] * 256 ** 4 + bytes[5] * 256 ** 5;
    let range_check_ptr = [fp - 6];
    return ();

    remaining_5:
    let dst = cast([fp - 5], felt*);
    let bytes_len = cast([fp - 4], felt);
    let bytes8 = cast([ap - 3], felt*);
    let bytes = cast([ap - 2], felt*);
    assert (bytes8 - dst) * 8 = bytes_len - 5;
    assert [bytes8] = bytes[0] + bytes[1] * 256 + bytes[2] * 256 ** 2 + bytes[3] * 256 ** 3 + bytes[
        4
    ] * 256 ** 4;
    let range_check_ptr = [fp - 6];
    return ();

    remaining_4:
    let dst = cast([fp - 5], felt*);
    let bytes_len = cast([fp - 4], felt);
    let bytes8 = cast([ap - 3], felt*);
    let bytes = cast([ap - 2], felt*);
    assert (bytes8 - dst) * 8 = bytes_len - 4;
    assert [bytes8] = bytes[0] + bytes[1] * 256 + bytes[2] * 256 ** 2 + bytes[3] * 256 ** 3;
    let range_check_ptr = [fp - 6];
    return ();

    remaining_3:
    let dst = cast([fp - 5], felt*);
    let bytes_len = cast([fp - 4], felt);
    let bytes8 = cast([ap - 3], felt*);
    let bytes = cast([ap - 2], felt*);
    assert (bytes8 - dst) * 8 = bytes_len - 3;
    assert [bytes8] = bytes[0] + bytes[1] * 256 + bytes[2] * 256 ** 2;
    let range_check_ptr = [fp - 6];
    return ();

    remaining_2:
    let dst = cast([fp - 5], felt*);
    let bytes_len = cast([fp - 4], felt);
    let bytes8 = cast([ap - 3], felt*);
    let bytes = cast([ap - 2], felt*);
    assert (bytes8 - dst) * 8 = bytes_len - 2;
    assert [bytes8] = bytes[0] + bytes[1] * 256;
    let range_check_ptr = [fp - 6];
    return ();

    remaining_1:
    let dst = cast([fp - 5], felt*);
    let bytes_len = cast([fp - 4], felt);
    let bytes8 = cast([ap - 3], felt*);
    let bytes = cast([ap - 2], felt*);
    assert (bytes8 - dst) * 8 = bytes_len - 1;
    assert [bytes8] = bytes[0];
    let range_check_ptr = [fp - 6];
    return ();

    remaining_0:
    let dst = cast([fp - 5], felt*);
    let bytes_len = cast([fp - 4], felt);
    let bytes8 = cast([ap - 3], felt*);
    let bytes = cast([ap - 2], felt*);
    assert (bytes8 - dst) * 8 = bytes_len;
    let range_check_ptr = [fp - 6];
    return ();
}

func keccak{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}(
    code_len: felt, code: felt*
) -> Uint256 {
    alloc_locals;
    let (local dst: felt*) = alloc();
    bytes_to_bytes8_little_endian(dst, code_len, code);

    let (code_hash) = keccak_bigend(dst, code_len);
    return code_hash;
}
