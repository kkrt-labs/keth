// Module adapted from starkware.cairo.common.cairo_blake2s.blake2s to use the newly introduced
// `blake2s` opcode.

// This module provides a set of functions to compute the blake2s hash function.
//
// This module is similar to the keccak.cairo module. See more info there.

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.math import split_felt, unsigned_div_rem
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.memset import memset
from starkware.cairo.common.uint256 import Uint256

from cairo_core.maths import felt252_array_to_bytes4_array

const INPUT_BLOCK_FELTS = 16;
const INPUT_BLOCK_BYTES = 64;
const STATE_SIZE_FELTS = 8;
const BLAKE2S_BYTES_IN_FELTS = 32;

// Computes blake2s of 'input'.
// To use this function, split the input into words of 32 bits (little endian).
// For example, to compute blake2s('Hello world'), use:
//   input = [1819043144, 1870078063, 6581362]
// where:
//   1819043144 == int.from_bytes(b'Hell', 'little')
//   1870078063 == int.from_bytes(b'o wo', 'little')
//   6581362 == int.from_bytes(b'rld', 'little')
//
// Returns the hash as a Uint256.
//
// Note: the interface of this function may change in the future.
// Note: Each input word is verified to be in the range [0, 2 ** 32) by the opcode runner.
func blake2s{range_check_ptr}(data: felt*, n_bytes: felt) -> (res: Uint256) {
    let (blake2s_ptr) = alloc();
    let (output) = blake2s_as_words{blake2s_ptr=blake2s_ptr}(data=data, n_bytes=n_bytes);
    let res_low = output[3] * 2 ** 96 + output[2] * 2 ** 64 + output[1] * 2 ** 32 + output[0];
    let res_high = output[7] * 2 ** 96 + output[6] * 2 ** 64 + output[5] * 2 ** 32 + output[4];
    return (res=Uint256(low=res_low, high=res_high));
}

// A truncated version of blake2s that returns a 248-bit hash.
// Expects the same input as the function above.
func blake2s_truncated{range_check_ptr}(data: felt*, n_bytes: felt) -> felt {
    let (blake2s_ptr) = alloc();
    let (output) = blake2s_as_words{blake2s_ptr=blake2s_ptr}(data=data, n_bytes=n_bytes);
    // Truncate hash - convert value to felt, by taking the 248 least significant bits.
    // Meaning we only take the lower 3 bytes of the final word.
    let (high_h, high_l) = unsigned_div_rem(output[7], 2 ** 24);
    // final_world_l is the lower 24 bits of the final word
    tempvar res_felt = 2 ** 224 * high_l + output[6] * 2 ** 192 + output[5] * 2 ** 160 + output[
        4
    ] * 2 ** 128 + output[3] * 2 ** 96 + output[2] * 2 ** 64 + output[1] * 2 ** 32 + output[0];
    return res_felt;
}

// Computes the blake2s hash of multiple field elements.
// The output is the blake2s hash truncated to 248 bits.
// The input is a pointer to an array of felts.
func blake2s_hash_many{range_check_ptr}(felt_input_len: felt, felt_input: felt*) -> (res: felt) {
    alloc_locals;
    let n_bytes = felt_input_len * BLAKE2S_BYTES_IN_FELTS;
    let (blake2s_ptr) = alloc();
    let (data_len, data) = felt252_array_to_bytes4_array(felt_input_len, felt_input);
    let res = blake2s_truncated(data=data, n_bytes=n_bytes);
    return (res=res);
}

// Computes blake2s of 'input', and returns the hash in big endian representation.
// See blake2s().
// Note that the input is still treated as little endian.
func blake2s_bigend{bitwise_ptr: BitwiseBuiltin*, range_check_ptr, blake2s_ptr: felt*}(
    data: felt*, n_bytes: felt
) -> (res: Uint256) {
    let (num) = blake2s(data=data, n_bytes=n_bytes);

    // Reverse byte endianness of 128-bit words.
    tempvar value = num.high;
    assert bitwise_ptr[0].x = value;
    assert bitwise_ptr[0].y = 0x00ff00ff00ff00ff00ff00ff00ff00ff;
    tempvar value = value + (2 ** 16 - 1) * bitwise_ptr[0].x_and_y;
    assert bitwise_ptr[1].x = value;
    assert bitwise_ptr[1].y = 0x00ffff0000ffff0000ffff0000ffff00;
    tempvar value = value + (2 ** 32 - 1) * bitwise_ptr[1].x_and_y;
    assert bitwise_ptr[2].x = value;
    assert bitwise_ptr[2].y = 0x00ffffffff00000000ffffffff000000;
    tempvar value = value + (2 ** 64 - 1) * bitwise_ptr[2].x_and_y;
    assert bitwise_ptr[3].x = value;
    assert bitwise_ptr[3].y = 0x00ffffffffffffffff00000000000000;
    tempvar value = value + (2 ** 128 - 1) * bitwise_ptr[3].x_and_y;
    tempvar high = value / 2 ** (8 + 16 + 32 + 64);
    let bitwise_ptr = bitwise_ptr + 4 * BitwiseBuiltin.SIZE;

    tempvar value = num.low;
    assert bitwise_ptr[0].x = value;
    assert bitwise_ptr[0].y = 0x00ff00ff00ff00ff00ff00ff00ff00ff;
    tempvar value = value + (2 ** 16 - 1) * bitwise_ptr[0].x_and_y;
    assert bitwise_ptr[1].x = value;
    assert bitwise_ptr[1].y = 0x00ffff0000ffff0000ffff0000ffff00;
    tempvar value = value + (2 ** 32 - 1) * bitwise_ptr[1].x_and_y;
    assert bitwise_ptr[2].x = value;
    assert bitwise_ptr[2].y = 0x00ffffffff00000000ffffffff000000;
    tempvar value = value + (2 ** 64 - 1) * bitwise_ptr[2].x_and_y;
    assert bitwise_ptr[3].x = value;
    assert bitwise_ptr[3].y = 0x00ffffffffffffffff00000000000000;
    tempvar value = value + (2 ** 128 - 1) * bitwise_ptr[3].x_and_y;
    tempvar low = value / 2 ** (8 + 16 + 32 + 64);
    let bitwise_ptr = bitwise_ptr + 4 * BitwiseBuiltin.SIZE;

    return (res=Uint256(low=high, high=low));
}

// Same as blake2s, but outputs a pointer to 8 32-bit little endian words instead.
func blake2s_as_words{range_check_ptr, blake2s_ptr: felt*}(data: felt*, n_bytes: felt) -> (
    output: felt*
) {
    // Set the initial state to IV (IV[0] is modified).
    assert blake2s_ptr[0] = 0x6B08E647;  // IV[0] ^ 0x01010020 (config: no key, 32 bytes output).
    assert blake2s_ptr[1] = 0xBB67AE85;
    assert blake2s_ptr[2] = 0x3C6EF372;
    assert blake2s_ptr[3] = 0xA54FF53A;
    assert blake2s_ptr[4] = 0x510E527F;
    assert blake2s_ptr[5] = 0x9B05688C;
    assert blake2s_ptr[6] = 0x1F83D9AB;
    assert blake2s_ptr[7] = 0x5BE0CD19;
    static_assert STATE_SIZE_FELTS == 8;
    let blake2s_ptr = blake2s_ptr + STATE_SIZE_FELTS;

    let (output) = blake2s_inner(data=data, n_bytes=n_bytes, counter=0);
    return (output=output);
}

// Inner loop for blake2s. blake2s_ptr points to after the initial state of the previous instance.
func blake2s_inner{range_check_ptr, blake2s_ptr: felt*}(
    data: felt*, n_bytes: felt, counter: felt
) -> (output: felt*) {
    alloc_locals;
    let is_last_block = is_le(n_bytes, INPUT_BLOCK_BYTES);
    if (is_last_block != 0) {
        return blake2s_last_block(data=data, n_bytes=n_bytes, counter=counter);
    }

    // Run the blake2s opcode runner, store its output in blake2s_ptr;
    let state_ptr = blake2s_ptr - STATE_SIZE_FELTS;
    run_blake2s_opcode(is_last_block=0, dst=counter + INPUT_BLOCK_BYTES, op0=state_ptr, op1=data);

    return blake2s_inner(
        data=data + INPUT_BLOCK_FELTS,
        n_bytes=n_bytes - INPUT_BLOCK_BYTES,
        counter=counter + INPUT_BLOCK_BYTES,
    );
}

func blake2s_last_block{range_check_ptr, blake2s_ptr: felt*}(
    data: felt*, n_bytes: felt, counter: felt
) -> (output: felt*) {
    alloc_locals;
    let state_ptr = blake2s_ptr - STATE_SIZE_FELTS;
    let (n_felts, _) = unsigned_div_rem(n_bytes + 3, 4);
    memset(data + n_felts, 0, INPUT_BLOCK_FELTS - n_felts);
    let blake2s_ptr = blake2s_ptr + INPUT_BLOCK_FELTS;

    // Run the blake2s opcode runner on the same inputs and store its output.
    run_blake2s_opcode(is_last_block=1, dst=counter + n_bytes, op0=state_ptr, op1=data);
    return (output=cast(blake2s_ptr - STATE_SIZE_FELTS, felt*));
}

// These functions serialize data to a data array to be used with blake2s().
// They use the property that each data word is verified by blake2s() to be in range [0, 2 ** 32).

// Serializes a uint256 number in a blake2s compatible way (little-endian).
func blake2s_add_uint256{data: felt*}(num: Uint256) {
    let high = num.high;
    let low = num.low;
    %{
        B = 32
        MASK = 2 ** 32 - 1
        segments.write_arg(ids.data, [(ids.low >> (B * i)) & MASK for i in range(4)])
        segments.write_arg(ids.data + 4, [(ids.high >> (B * i)) & MASK for i in range(4)])
    %}
    assert data[3] * 2 ** 96 + data[2] * 2 ** 64 + data[1] * 2 ** 32 + data[0] = low;
    assert data[7] * 2 ** 96 + data[6] * 2 ** 64 + data[5] * 2 ** 32 + data[4] = high;
    let data = data + 8;
    return ();
}

// Serializes a uint256 number in a blake2s compatible way (big-endian).
func blake2s_add_uint256_bigend{bitwise_ptr: BitwiseBuiltin*, data: felt*}(num: Uint256) {
    // Reverse byte endianness of 32-bit chunks.
    tempvar value = num.high;
    assert bitwise_ptr[0].x = value;
    assert bitwise_ptr[0].y = 0x00ff00ff00ff00ff00ff00ff00ff00ff;
    tempvar value = value + (2 ** 16 - 1) * bitwise_ptr[0].x_and_y;
    assert bitwise_ptr[1].x = value;
    assert bitwise_ptr[1].y = 0x00ffff0000ffff0000ffff0000ffff00;
    tempvar value = value + (2 ** 32 - 1) * bitwise_ptr[1].x_and_y;
    tempvar high = value / 2 ** (8 + 16);

    tempvar value = num.low;
    assert bitwise_ptr[2].x = value;
    assert bitwise_ptr[2].y = 0x00ff00ff00ff00ff00ff00ff00ff00ff;
    tempvar value = value + (2 ** 16 - 1) * bitwise_ptr[2].x_and_y;
    assert bitwise_ptr[3].x = value;
    assert bitwise_ptr[3].y = 0x00ffff0000ffff0000ffff0000ffff00;
    tempvar value = value + (2 ** 32 - 1) * bitwise_ptr[3].x_and_y;
    tempvar low = value / 2 ** (8 + 16);

    let bitwise_ptr = bitwise_ptr + 4 * BitwiseBuiltin.SIZE;

    %{
        B = 32
        MASK = 2 ** 32 - 1
        segments.write_arg(ids.data, [(ids.high >> (B * (3 - i))) & MASK for i in range(4)])
        segments.write_arg(ids.data + 4, [(ids.low >> (B * (3 - i))) & MASK for i in range(4)])
    %}

    assert data[0] * 2 ** 96 + data[1] * 2 ** 64 + data[2] * 2 ** 32 + data[3] = high;
    assert data[4] * 2 ** 96 + data[5] * 2 ** 64 + data[6] * 2 ** 32 + data[7] = low;
    let data = data + 8;
    return ();
}

// Serializes a field element in a blake2s compatible way.
func blake2s_add_felt{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, data: felt*}(
    num: felt, bigend: felt
) {
    let (high, low) = split_felt(num);
    if (bigend != 0) {
        blake2s_add_uint256_bigend(Uint256(low=low, high=high));
        return ();
    } else {
        blake2s_add_uint256(Uint256(low=low, high=high));
        return ();
    }
}

// Serializes multiple field elements in a blake2s compatible way.
// Note: This function does not serialize the number of elements. If desired, this is the caller's
// responsibility.
func blake2s_add_felts{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, data: felt*}(
    n_elements: felt, elements: felt*, bigend: felt
) -> () {
    if (n_elements == 0) {
        return ();
    }
    blake2s_add_felt(num=elements[0], bigend=bigend);
    return blake2s_add_felts(n_elements=n_elements - 1, elements=&elements[1], bigend=bigend);
}

// Computes the blake2s hash for multiple field elements.
func blake2s_felts{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, blake2s_ptr: felt*}(
    n_elements: felt, elements: felt*, bigend: felt
) -> (res: Uint256) {
    alloc_locals;
    let (data) = alloc();
    let data_start = data;
    with data {
        blake2s_add_felts(n_elements=n_elements, elements=elements, bigend=bigend);
    }
    let (res) = blake2s(data=data_start, n_bytes=n_elements * 32);
    return (res=res);
}

// Taken from https://github.com/starkware-libs/stwo-cairo/blob/main/stwo_cairo_prover/test_data/test_prove_verify_all_opcode_components/all_opcode_components.cairo
// Forces the runner to execute the Blake2s or Blake2sLastBlock opcode with the given operands.
// op0 is a pointer to an array of 8 felts as u32 integers of the state.
// op1 is a pointer to an array of 16 felts as u32 integers of the message.
// dst is a felt representing a u32 of the counter.
// ap contains a pointer to an array of 8 felts as u32 integers of the output state.
// Those values are stored within addresses fp-5, fp-4 and fp-3 respectively.
// An instruction encoding is built from offsets -5, -4, -3 and flags which are all 0 except for
// those denoting uses of fp as the base for operand addresses and flag_opcode_blake (16th flag).
// The instruction is then written to [pc] and the runner is forced to execute Blake2s.
// Writes the output to the pointer in blake2s_ptr.
func run_blake2s_opcode{blake2s_ptr: felt*}(
    is_last_block: felt, dst: felt, op0: felt*, op1: felt*
) {
    alloc_locals;

    // Set the offsets for the operands.
    let offset0 = (2 ** 15) - 5;
    let offset1 = (2 ** 15) - 4;
    let offset2 = (2 ** 15) - 3;
    static_assert dst == [fp - 5];
    static_assert op0 == [fp - 4];
    static_assert op1 == [fp - 3];

    // Set the flags for the instruction.
    let flag_dst_base_fp = 1;
    let flag_op0_base_fp = 1;
    let flag_op1_imm = 0;
    let flag_op1_base_fp = 1;
    let flag_op1_base_ap = 0;
    let flag_res_add = 0;
    let flag_res_mul = 0;
    let flag_PC_update_jump = 0;
    let flag_PC_update_jump_rel = 0;
    let flag_PC_update_jnz = 0;
    let flag_ap_update_add = 0;
    let flag_ap_update_add_1 = 0;
    let flag_opcode_call = 0;
    let flag_opcode_ret = 0;
    let flag_opcode_assert_eq = 0;

    let flag_num = flag_dst_base_fp + flag_op0_base_fp * (2 ** 1) + flag_op1_imm * (2 ** 2) +
        flag_op1_base_fp * (2 ** 3);
    let blake2s_opcode_extension_num = 1;
    let blake2s_last_block_opcode_extension_num = 2;
    let blake2s_instruction_num = offset0 + offset1 * (2 ** 16) + offset2 * (2 ** 32) + flag_num * (
        2 ** 48
    ) + blake2s_opcode_extension_num * (2 ** 63);
    let blake2s_last_block_instruction_num = offset0 + offset1 * (2 ** 16) + offset2 * (2 ** 32) +
        flag_num * (2 ** 48) + blake2s_last_block_opcode_extension_num * (2 ** 63);
    static_assert blake2s_instruction_num == 9226608988349300731;
    static_assert blake2s_last_block_instruction_num == 18449981025204076539;

    // Write the instruction to [pc] and point [ap] to the designated output.
    assert [ap] = cast(blake2s_ptr, felt);

    jmp last_block if is_last_block != 0;
    dw 9226608988349300731;
    ap += 1;
    let blake2s_ptr = cast([fp - 7], felt*) + STATE_SIZE_FELTS;
    return ();

    last_block:
    dw 18449981025204076539;
    ap += 1;
    let blake2s_ptr = cast([fp - 7], felt*) + STATE_SIZE_FELTS;
    return ();
}
