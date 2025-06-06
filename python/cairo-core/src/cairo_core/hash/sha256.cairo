from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.math import assert_nn_le, unsigned_div_rem
from starkware.cairo.common.math_cmp import is_le_felt
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.memset import memset
from starkware.cairo.common.pow import pow
from starkware.cairo.common.cairo_sha256.sha256_utils import (
    compute_message_schedule,
    BATCH_SIZE,
    finalize_sha256,
)
from ethereum_types.bytes import Bytes, Bytes4, ListBytes4, ListBytes4Struct
from ethereum.utils.bytes import Bytes_to_be_ListBytes4, ListBytes4_be_to_bytes

// The hints are whitelisted with 'BLOCK_SIZE' in the rust VM but starkware renamed to 'BATCH_SIZE'
const BLOCK_SIZE = BATCH_SIZE;

EMPTY_SHA256:
dw 0x24b96f99c8f4fb9a141cfc9842c4b0e3;
dw 0x55b852781b9995a44c939b64e441ae27;

// Source: https://github.com/cartridge-gg/cairo-sha256/blob/8d2ae515ab5cc9fc530c2dcf3ed1172bd181136e/src/sha256.cairo
const SHA256_INPUT_CHUNK_SIZE_FELTS = 16;
const SHA256_INPUT_CHUNK_SIZE_BYTES = 64;
const SHA256_STATE_SIZE_FELTS = 8;
// Each instance consists of 16 words of message, 8 words for the input state and 8 words
// for the output state.
const SHA256_INSTANCE_SIZE = SHA256_INPUT_CHUNK_SIZE_FELTS + 2 * SHA256_STATE_SIZE_FELTS;

func sha256_bytes{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(buffer: Bytes) -> Bytes {
    alloc_locals;
    let list_bytes4_be = Bytes_to_be_ListBytes4(buffer);
    // The number of bytes to hash is taken from the original input
    let hash = sha256_be_output(list_bytes4_be.value.data, buffer.value.len);
    tempvar hash_bytes4 = ListBytes4(new ListBytes4Struct(cast(hash, Bytes4*), 8));
    // Split words and return bytes hash code.
    let hash_bytes = ListBytes4_be_to_bytes(hash_bytes4);
    return hash_bytes;
}

// Computes SHA256 of 'input'. Inputs of arbitrary length are supported.
// To use this function, split the input into (up to) 14 words of 32 bits (big endian).
// For example, to compute sha256('Hello world'), use:
//   input = [1214606444, 1864398703, 1919706112]
// where:
//   1214606444 == int.from_bytes(b'Hell', 'big')
//   1864398703 == int.from_bytes(b'o wo', 'big')
//   1919706112 == int.from_bytes(b'rld\x00', 'big')  # Note the '\x00' padding.
//
// block layout:
// 0 - 15: Message
// 16 - 23: Input State
// 24 - 32: Output
//
// output is an array of 8 32-bit words (big endian).
//
// Note: This function ensures soundness by calling finalize_sha256() at the end of the function.
// Otherwise, this function is not sound and a malicious prover may return a wrong result.
// If multiple sha256 are being ran sequentially, use `sha256_unfinalized` and finalize manually.
func sha256_be_output{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    data: felt*, n_bytes: felt
) -> felt* {
    alloc_locals;

    let (local sha256_ptr_start: felt*) = alloc();
    let sha256_ptr = sha256_ptr_start;

    let (res) = sha256_unfinalized{sha256_ptr=sha256_ptr}(data, n_bytes);
    finalize_sha256(sha256_ptr_start, sha256_ptr);

    return res;
}

// Does not ensure soundness. `finalize_sha256()` must be called before the end of the program
func sha256_unfinalized{range_check_ptr, sha256_ptr: felt*}(data: felt*, n_bytes: felt) -> (
    output: felt*
) {
    alloc_locals;

    // Set the initial input state to IV.
    assert sha256_ptr[16] = 0x6A09E667;
    assert sha256_ptr[17] = 0xBB67AE85;
    assert sha256_ptr[18] = 0x3C6EF372;
    assert sha256_ptr[19] = 0xA54FF53A;
    assert sha256_ptr[20] = 0x510E527F;
    assert sha256_ptr[21] = 0x9B05688C;
    assert sha256_ptr[22] = 0x1F83D9AB;
    assert sha256_ptr[23] = 0x5BE0CD19;

    sha256_inner(data=data, n_bytes=n_bytes, total_bytes=n_bytes);

    // Set `output` to the start of the final state.
    let output = sha256_ptr;
    // Set `sha256_ptr` to the end of the output state.
    let sha256_ptr = sha256_ptr + SHA256_STATE_SIZE_FELTS;
    return (output,);
}

// Computes the sha256 hash of the input chunk from `message` to `message + SHA256_INPUT_CHUNK_SIZE_FELTS`
func _sha256_chunk{range_check_ptr, sha256_start: felt*, state: felt*, output: felt*}() {
    %{
        from starkware.cairo.common.cairo_sha256.sha256_utils import (
            compute_message_schedule, sha2_compress_function)

        _sha256_input_chunk_size_felts = int(ids.SHA256_INPUT_CHUNK_SIZE_FELTS)
        assert 0 <= _sha256_input_chunk_size_felts < 100
        _sha256_state_size_felts = int(ids.SHA256_STATE_SIZE_FELTS)
        assert 0 <= _sha256_state_size_felts < 100
        w = compute_message_schedule(memory.get_range(
            ids.sha256_start, _sha256_input_chunk_size_felts))
        new_state = sha2_compress_function(memory.get_range(ids.state, _sha256_state_size_felts), w)
        segments.write_arg(ids.output, new_state)
    %}
    return ();
}

// Inner loop for sha256. `sha256_ptr` points to the start of the block.
func sha256_inner{range_check_ptr, sha256_ptr: felt*}(
    data: felt*, n_bytes: felt, total_bytes: felt
) {
    alloc_locals;

    let message = sha256_ptr;
    let state = sha256_ptr + SHA256_INPUT_CHUNK_SIZE_FELTS;
    let output = state + SHA256_STATE_SIZE_FELTS;

    let zero_bytes = is_le_felt(n_bytes, 0);
    let zero_total_bytes = is_le_felt(total_bytes, 0);

    // If the previous message block was full we are still missing "1" at the end of the message
    let (_, r_div_by_64) = unsigned_div_rem(total_bytes, 64);
    let missing_bit_one = is_le_felt(r_div_by_64, 0);

    // This works for 0 total bytes too, because zero_chunk will be -1 and, therefore, not 0.
    let zero_chunk = zero_bytes - zero_total_bytes - missing_bit_one;

    let is_last_block = is_le_felt(n_bytes, 55);
    if (is_last_block == 1) {
        _sha256_input(data, n_bytes, SHA256_INPUT_CHUNK_SIZE_FELTS - 2, zero_chunk);
        // Append the original message length at the end of the message block as a 64-bit big-endian integer.
        assert sha256_ptr[0] = 0;
        assert sha256_ptr[1] = total_bytes * 8;
        let sha256_ptr = sha256_ptr + 2;
        _sha256_chunk{sha256_start=message, state=state, output=output}();
        let sha256_ptr = sha256_ptr + SHA256_STATE_SIZE_FELTS;

        return ();
    }

    let (q, r) = unsigned_div_rem(n_bytes, SHA256_INPUT_CHUNK_SIZE_BYTES);
    let is_remainder_block = is_le_felt(q, 0);
    if (is_remainder_block == 1) {
        _sha256_input(data, r, SHA256_INPUT_CHUNK_SIZE_FELTS, 0);
        _sha256_chunk{sha256_start=message, state=state, output=output}();

        let sha256_ptr = sha256_ptr + SHA256_STATE_SIZE_FELTS;
        memcpy(
            output + SHA256_STATE_SIZE_FELTS + SHA256_INPUT_CHUNK_SIZE_FELTS,
            output,
            SHA256_STATE_SIZE_FELTS,
        );
        let sha256_ptr = sha256_ptr + SHA256_STATE_SIZE_FELTS;

        return sha256_inner(data=data, n_bytes=n_bytes - r, total_bytes=total_bytes);
    } else {
        _sha256_input(data, SHA256_INPUT_CHUNK_SIZE_BYTES, SHA256_INPUT_CHUNK_SIZE_FELTS, 0);
        _sha256_chunk{sha256_start=message, state=state, output=output}();

        let sha256_ptr = sha256_ptr + SHA256_STATE_SIZE_FELTS;
        memcpy(
            output + SHA256_STATE_SIZE_FELTS + SHA256_INPUT_CHUNK_SIZE_FELTS,
            output,
            SHA256_STATE_SIZE_FELTS,
        );
        let sha256_ptr = sha256_ptr + SHA256_STATE_SIZE_FELTS;

        return sha256_inner(
            data=data + SHA256_INPUT_CHUNK_SIZE_FELTS,
            n_bytes=n_bytes - SHA256_INPUT_CHUNK_SIZE_BYTES,
            total_bytes=total_bytes,
        );
    }
}

// 1. Encode the input to binary using UTF-8 and append a single '1' to it.
// 2. Prepend that binary to the message block.
func _sha256_input{range_check_ptr, sha256_ptr: felt*}(
    input: felt*, n_bytes: felt, n_words: felt, pad_chunk: felt
) {
    alloc_locals;

    local full_word;
    %{ ids.full_word = int(ids.n_bytes >= 4) %}

    if (full_word != 0) {
        assert sha256_ptr[0] = input[0];
        let sha256_ptr = sha256_ptr + 1;
        return _sha256_input(
            input=input + 1, n_bytes=n_bytes - 4, n_words=n_words - 1, pad_chunk=pad_chunk
        );
    }

    if (n_words == 0) {
        return ();
    }

    if (n_bytes == 0 and pad_chunk == 1) {
        // Add zeros between the encoded message and the length integer so that the message block is a multiple of 512.
        memset(dst=sha256_ptr, value=0, n=n_words);
        let sha256_ptr = sha256_ptr + n_words;
        return ();
    }

    if (n_bytes == 0) {
        // This is the last input word, so we should add a byte '0x80' at the end and fill the rest with zeros.
        assert sha256_ptr[0] = 0x80000000;
        // Add zeros between the encoded message and the length integer so that the message block is a multiple of 512.
        memset(dst=sha256_ptr + 1, value=0, n=n_words - 1);
        let sha256_ptr = sha256_ptr + n_words;
        return ();
    }

    assert_nn_le(n_bytes, 3);
    let (padding) = pow(256, 3 - n_bytes);
    local range_check_ptr = range_check_ptr;

    assert sha256_ptr[0] = input[0] + padding * 0x80;

    memset(dst=sha256_ptr + 1, value=0, n=n_words - 1);
    let sha256_ptr = sha256_ptr + n_words;
    return ();
}
